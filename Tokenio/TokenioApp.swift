import AppKit
import ServiceManagement

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var statusItem: NSStatusItem!
    private var sessionView: MetricMenuView!
    private var weeklyView: MetricMenuView!
    private var sonnetView: MetricMenuView!
    private var extraView: MetricMenuView!
    private var updatedItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var logoutItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var accountItem: NSMenuItem!
    private var launchInstanceItem: NSMenuItem!

    private var fetchTimer: Timer?
    private var uiTimer: Timer?
    private var lastFetched: TimeInterval = 0
    private var loading = false
    private var authFailed = false
    private var loginWindow: LoginWindow?
    private var welcomeWindow: WelcomeWindow?
    private var aboutWindow: NSWindow?

    // Last known icon values for redraw on appearance change
    private var lastSU: Double = 0, lastWU: Double = 0
    private var lastSR: TimeInterval = 0, lastWR: TimeInterval = 0, lastSnR: TimeInterval = 0   // reset timestamps

    // Tick fracs computed live from reset timestamps so they update every 30s
    private var lastST: Double { elapsedPct(resetTs: lastSR, windowSecs: 5 * 3600) }
    private var lastWT: Double { elapsedPct(resetTs: lastWR, windowSecs: 7 * 24 * 3600) }
    private var currentAccountName: String? = nil

    private let refreshIntervalOptions: [(label: String, seconds: TimeInterval)] = [
        ("1 minute",   60),
        ("2 minutes",  120),
        ("5 minutes",  300),
        ("10 minutes", 600),
        ("30 minutes", 1800),
    ]
    private var refreshInterval: TimeInterval {
        let saved = UserDefaults.standard.double(forKey: "refreshInterval")
        return saved > 0 ? saved : 300
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Multi-instance slot isolation
        let env = ProcessInfo.processInfo.environment
        if let slot = env["TOKENIO_SLOT"], !slot.isEmpty {
            currentSlot = slot
        }

        NSApp.setActivationPolicy(.accessory)

        // Enable launch at login on first run
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            if LaunchAtLogin.isEnabled || LaunchAtLogin.enable() {
                UserDefaults.standard.set(true, forKey: "hasLaunched")
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()

        if let session = loadSession() {
            // Logged in — show snapshot immediately if available, then refresh
            currentAccountName = session.accountName
            updateProviderViews()
            let initials = session.accountName.map { makeInitials($0) } ?? ""
            applyInitials(initials, accountName: session.accountName)
            updateAccountItem(name: session.accountName)

            // If accountName missing from old session, re-fetch it in background
            if session.accountName == nil {
                DispatchQueue.global().async { [weak self] in
                    if let orgInfo = validateAndGetOrg(sessionKey: session.sessionKey) {
                        let updated = Session(sessionKey: session.sessionKey, orgId: session.orgId, accountName: orgInfo.name)
                        saveSession(updated)
                        DispatchQueue.main.async {
                            self?.currentAccountName = orgInfo.name
                            self?.updateProviderViews()
                            self?.updateAccountItem(name: orgInfo.name)
                        }
                    }
                }
            }
            if let (snapshot, ts) = loadSnapshot() {
                applySnapshot(snapshot)
                lastFetched = ts
                updatedItem.title = "Updated \(fmtAgo(ts))  \u{21bb}"
            } else {
                applyIcon(makeIcon(sUsage: 0, sTime: 0, wUsage: 0, wTime: 0, isDark: isDarkMenuBar, accountName: session.accountName))
            }
            triggerFetch(isBackground: true)
        } else {
            // Not logged in — warning icon, show stale data if any
            applyIcon(makeDisconnectedIcon())
            if let (snapshot, ts) = loadSnapshot() {
                applySnapshot(snapshot, iconOverride: false)
                lastFetched = ts
                updatedItem.title = "Not logged in  \u{26a0}"
            } else {
                updatedItem.title = "Not logged in  \u{26a0}"
            }
            authFailed = true
            updateAuthVisibility()
            // Show welcome window on first launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.loginClicked()
            }
        }

        fetchTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.triggerFetch(isBackground: true)
        }
        RunLoop.main.add(fetchTimer!, forMode: .common)

        uiTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.updateRelativeTime()
        }
        RunLoop.main.add(uiTimer!, forMode: .common)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(wakeRefresh),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Account label (shown when logged in)
        accountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        accountItem.isEnabled = true
        menu.addItem(accountItem)

        menu.addItem(.separator())

        func addMetric(_ view: MetricMenuView) {
            let item = NSMenuItem()
            item.view = view
            menu.addItem(item)
        }

        sessionView = MetricMenuView(title: "Current session")
        weeklyView = MetricMenuView(title: "Weekly - All models")
        sonnetView = MetricMenuView(title: "Weekly - Sonnet only")
        extraView = MetricMenuView(title: "Extra usage")

        addMetric(sessionView)
        addMetric(weeklyView)
        addMetric(sonnetView)
        addMetric(extraView)

        updatedItem = NSMenuItem(title: "Refreshing\u{2026}  \u{21bb}", action: #selector(refreshClicked), keyEquivalent: "")
        updatedItem.target = self
        menu.addItem(updatedItem)

        menu.addItem(.separator())

        // Auth actions
        loginItem = NSMenuItem(title: "Log in to Claude\u{2026}", action: #selector(loginClicked), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        logoutItem = NSMenuItem(title: "Log out", action: #selector(logoutClicked), keyEquivalent: "")
        logoutItem.target = self
        menu.addItem(logoutItem)

        launchInstanceItem = NSMenuItem(title: "Launch another instance\u{2026}", action: #selector(launchAnotherInstance), keyEquivalent: "")
        launchInstanceItem.target = self
        menu.addItem(launchInstanceItem)

        updateAuthVisibility()

        menu.addItem(.separator())

        // Settings
        launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        let refreshMenu = NSMenu()
        for opt in refreshIntervalOptions {
            let item = NSMenuItem(title: opt.label, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = opt.seconds
            item.state = (opt.seconds == refreshInterval) ? .on : .off
            refreshMenu.addItem(item)
        }
        let refreshParent = NSMenuItem(title: "Refresh every\u{2026}", action: nil, keyEquivalent: "")
        refreshParent.submenu = refreshMenu
        menu.addItem(refreshParent)

        menu.addItem(.separator())

        // About + Quit
        let aboutItem = NSMenuItem(title: "About Tokenio", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Tokenio", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Icon

    private var isDarkMenuBar: Bool {
        statusItem.button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyIcon(_ img: NSImage) {
        statusItem.button?.image = img
        statusItem.button?.imageScaling = .scaleProportionallyDown
    }

    private func applyInitials(_ initials: String, accountName: String? = nil) {
        // Hide all text/icons - just show the progress bars
        statusItem.button?.title = ""
        statusItem.button?.image = nil
    }

    // MARK: - Fetch

    private func triggerFetch(isBackground: Bool = false) {
        guard !loading, !authFailed else { return }
        loading = true
        if !isBackground { updatedItem?.title = "Refreshing\u{2026}  \u{21bb}" }
        DispatchQueue.global().async { [weak self] in
            let result = fetchUsage()
            DispatchQueue.main.async { self?.handleResult(result, isBackground: isBackground) }
        }
    }

    private func handleResult(_ result: UsageResult, isBackground: Bool) {
        loading = false

        switch result {
        case .success(let d):
            applySnapshot(d)
            lastFetched = Date().timeIntervalSince1970
            authFailed = false
            updatedItem.title = "Updated just now  \u{21bb}"
            updateAuthVisibility()

        case .needsLogin:
            authFailed = true
            applyIcon(makeDisconnectedIcon())
            if lastFetched > 0 {
                updatedItem.title = "Session expired (\(fmtAgo(lastFetched)))  \u{26a0}"
            } else {
                updatedItem.title = "Not logged in  \u{26a0}"
            }
            updateAuthVisibility()

        case .error(let msg):
            let short = msg.count > 40 ? String(msg.prefix(40)) + "\u{2026}" : msg
            updatedItem.title = "\(short)  \u{26a0}"
        }
    }

    private func applySnapshot(_ d: UsageData, iconOverride: Bool = true) {
        var sU = d.sessionPct
        let sR = d.sessionReset
        if sR > 0, sR < Date().timeIntervalSince1970 { sU = 0 }
        let sT = elapsedPct(resetTs: sR, windowSecs: 5 * 3600)

        let wU = d.weeklyPct
        let wR = d.weeklyReset
        let wT = elapsedPct(resetTs: wR, windowSecs: 7 * 24 * 3600)

        lastSU = sU; lastSR = sR; lastWU = wU; lastWR = wR

        let snU = d.sonnetPct
        let snR = d.sonnetReset
        let snT = elapsedPct(resetTs: snR, windowSecs: 7 * 24 * 3600)

        lastSnR = snR
        if iconOverride {
            applyIcon(makeIcon(sUsage: sU, sTime: sT, wUsage: wU, wTime: wT, isDark: isDarkMenuBar, accountName: currentAccountName))
        }

        sessionView.setData(value: "\(Int(sU))%", usageFrac: sU / 100, timeFrac: sT / 100, resetStr: sR == 0 ? "" : "Resets in \(fmtReset(sR))")
        weeklyView.setData(value: "\(Int(wU))%", usageFrac: wU / 100, timeFrac: wT / 100, resetStr: wR == 0 ? "" : "Resets in \(fmtReset(wR))")
        sonnetView.setData(value: "\(Int(snU))%", usageFrac: snU / 100, timeFrac: snT / 100, resetStr: snR == 0 ? "" : "Resets in \(fmtReset(snR))")

        if d.extraEnabled {
            let oU = d.overagePct
            let oR = d.overageReset
            let daysInMonth = Double(Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30)
            let oT = elapsedPct(resetTs: oR, windowSecs: daysInMonth * 24 * 3600)
            extraView.setTitle("Extra usage", suffix: "$\(String(format: "%.2f", d.extraDollars))")
            extraView.setData(value: "\(Int(oU))%", usageFrac: oU / 100, timeFrac: oT / 100, resetStr: "Resets in \(fmtReset(oR))")
        } else {
            extraView.setTitle("Extra usage")
            extraView.setData(value: "Not enabled", usageFrac: 0, timeFrac: 0, resetStr: "")
        }
    }

    // MARK: - Auth visibility

    private func updateAuthVisibility() {
        let session = loadSession()
        let loggedIn = session != nil
        loginItem.isHidden = loggedIn
        logoutItem.isHidden = !loggedIn
        updateAccountItem(name: session?.accountName)
    }

    private func updateProviderViews() {
        let p = currentAccountName.map { getEmailProvider($0) } ?? ""
        [sessionView, weeklyView, sonnetView, extraView].forEach { $0?.setProvider(p) }
    }

    private func updateAccountItem(name: String?) {
        guard let name = name, !name.isEmpty else { accountItem.isHidden = true; return }

        // Strip "'s Organization" suffix (Claude API returns this for personal accounts)
        let displayName = name.hasSuffix("'s Organization")
            ? String(name.dropLast("'s Organization".count)).trimmingCharacters(in: .whitespaces)
            : name

        let provider = getEmailProvider(displayName)
        let brandColor: NSColor = provider == "gmail"
            ? NSColor(red: 0.918, green: 0.263, blue: 0.208, alpha: 1.0)
            : provider == "icloud"
            ? NSColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
            : NSColor.secondaryLabelColor

        let badge = provider == "gmail" ? "Google  ·  " : provider == "icloud" ? "Apple  ·  " : ""
        let attrs = NSMutableAttributedString()
        if !badge.isEmpty {
            attrs.append(NSAttributedString(string: badge, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: brandColor
            ]))
        }
        attrs.append(NSAttributedString(string: displayName, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: brandColor.withAlphaComponent(0.70)
        ]))

        accountItem.attributedTitle = attrs
        accountItem.isEnabled = true   // must be true or macOS overrides attributedTitle colors
        accountItem.isHidden = false
    }

    // MARK: - Relative time

    private func updateRelativeTime() {
        guard lastFetched > 0, !authFailed else { return }
        updatedItem.title = "Updated \(fmtAgo(lastFetched))  \u{21bb}"
        applyIcon(makeIcon(sUsage: lastSU, sTime: lastST, wUsage: lastWU, wTime: lastWT, isDark: isDarkMenuBar, accountName: currentAccountName))
    }

    // MARK: - Actions

    @objc private func refreshClicked() { triggerFetch(isBackground: false) }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        UserDefaults.standard.set(seconds, forKey: "refreshInterval")
        // Update checkmarks
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? TimeInterval == seconds) ? .on : .off }
        // Restart timer with new interval
        fetchTimer?.invalidate()
        fetchTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            self?.triggerFetch(isBackground: true)
        }
        RunLoop.main.add(fetchTimer!, forMode: .common)
    }

    @objc private func wakeRefresh() { triggerFetch(isBackground: true) }

    private func showWelcome() {
        welcomeWindow = WelcomeWindow(onLogin: { [weak self] in
            self?.welcomeWindow = nil
            self?.loginClicked()
        })
        welcomeWindow?.show()
    }

    @objc private func loginClicked() {
        loginWindow = LoginWindow(
            onSuccess: { [weak self] _, _ in
                // Session already saved by LoginWindow with accountName; just refresh UI
                self?.authFailed = false
                self?.loginWindow = nil
                self?.updateAuthVisibility()
                // Apply initials from the freshly saved session
                if let session = loadSession() {
                    self?.currentAccountName = session.accountName
                    self?.updateProviderViews()
                    let initials = session.accountName.map { makeInitials($0) } ?? ""
                    self?.applyInitials(initials, accountName: session.accountName)
                    self?.updateAccountItem(name: session.accountName)
                }
                self?.triggerFetch(isBackground: false)
            },
            onCancel: { [weak self] in
                self?.loginWindow = nil
            }
        )
        loginWindow?.show()
    }

    @objc private func logoutClicked() {
        clearSession()
        clearSnapshot()
        authFailed = true
        lastFetched = 0
        currentAccountName = nil
        updateProviderViews()
        applyIcon(makeDisconnectedIcon())
        applyInitials("")
        updateAccountItem(name: nil)
        updatedItem.title = "Not logged in  \u{26a0}"
        sessionView.setData(value: "\u{2014}", usageFrac: 0, timeFrac: 0, resetStr: "\u{2014}")
        weeklyView.setData(value: "\u{2014}", usageFrac: 0, timeFrac: 0, resetStr: "\u{2014}")
        sonnetView.setData(value: "\u{2014}", usageFrac: 0, timeFrac: 0, resetStr: "\u{2014}")
        extraView.setTitle("Extra usage")
        extraView.setData(value: "\u{2014}", usageFrac: 0, timeFrac: 0, resetStr: "\u{2014}")
        updateAuthVisibility()
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLogin.toggle()
        launchAtLoginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func launchAnotherInstance() {
        guard let execURL = Bundle.main.executableURL else { return }
        let newSlot = String(UUID().uuidString.prefix(8))
        var env = ProcessInfo.processInfo.environment
        env["TOKENIO_SLOT"] = newSlot
        let process = Process()
        process.executableURL = execURL
        process.environment = env
        do {
            try process.run()
        } catch {
            log.error("Failed to launch new instance: \(error.localizedDescription)")
        }
    }

    @objc private func aboutClicked() {
        if let win = aboutWindow { win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let w: CGFloat = 340
        let pad: CGFloat = 28

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 0
        root.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        root.translatesAutoresizingMaskIntoConstraints = false

        // Icon
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.widthAnchor.constraint(equalToConstant: 72).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 72).isActive = true
        root.addArrangedSubview(iconView)
        root.setCustomSpacing(12, after: iconView)

        // App name
        let nameLabel = NSTextField(labelWithString: "Tokenio")
        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.alignment = .center
        root.addArrangedSubview(nameLabel)
        root.setCustomSpacing(4, after: nameLabel)

        // Version
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNum = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        let verLabel = NSTextField(labelWithString: "Version \(version) (\(buildNum))")
        verLabel.font = .systemFont(ofSize: 11)
        verLabel.textColor = .tertiaryLabelColor
        verLabel.alignment = .center
        root.addArrangedSubview(verLabel)
        root.setCustomSpacing(20, after: verLabel)

        // Divider
        let div = NSBox(); div.boxType = .separator
        div.widthAnchor.constraint(equalToConstant: w - pad * 2).isActive = true
        root.addArrangedSubview(div)
        root.setCustomSpacing(20, after: div)

        func section(_ heading: String, _ body: String) {
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 3
            stack.widthAnchor.constraint(equalToConstant: w - pad * 2).isActive = true

            let h = NSTextField(labelWithString: heading)
            h.font = .systemFont(ofSize: 11, weight: .semibold)
            h.textColor = .labelColor
            stack.addArrangedSubview(h)

            let b = NSTextField(wrappingLabelWithString: body)
            b.font = .systemFont(ofSize: 11)
            b.textColor = .secondaryLabelColor
            b.preferredMaxLayoutWidth = w - pad * 2
            stack.addArrangedSubview(b)

            root.addArrangedSubview(stack)
            root.setCustomSpacing(16, after: stack)
        }

        section("Usage Bars",
            "Bars fill green below 70%, yellow from 70–90%, and red above 90%.")
        section("Split Bar Design",
            "Each bar splits at the current time position within the window. The left pill shows elapsed time, the right shows remaining. If the fill overflows the gap, you're using quota faster than pace.")
        section("Multiple Accounts",
            "Use \u{201c}Launch another instance\u{2026}\u{201d} to monitor a second Claude account simultaneously.")
        section("Accessibility",
            "Tokenio lives in the menu bar only — no Dock icon, no App Switcher. No special system permissions required.")

        // GitHub link
        let link = NSButton(title: "github.com/elomid/tokenio", target: self, action: #selector(openGitHub))
        link.bezelStyle = .inline
        link.isBordered = false
        link.font = .systemFont(ofSize: 11)
        link.contentTintColor = NSColor.linkColor
        root.addArrangedSubview(link)
        root.setCustomSpacing(20, after: link)

        // Close button
        let closeBtn = NSButton(title: "Close", target: self, action: #selector(closeAbout))
        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\u{1b}"
        root.addArrangedSubview(closeBtn)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 100))
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: w),
        ])

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: 500),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "About Tokenio"
        win.contentView = contentView
        win.isReleasedWhenClosed = false
        win.level = .floating
        contentView.layoutSubtreeIfNeeded()
        let fittingH = root.fittingSize.height
        win.setContentSize(NSSize(width: w, height: fittingH))
        win.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: win, queue: .main) { [weak self] _ in
            self?.aboutWindow = nil
        }
        aboutWindow = win
        win.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/elomid/tokenio")!)
    }

    @objc private func closeAbout() {
        aboutWindow?.close()
        aboutWindow = nil
    }

    @objc private func quitClicked() { NSApp.terminate(nil) }
}

// MARK: - Launch at Login (SMAppService, macOS 13+)

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func enable() -> Bool {
        do {
            try SMAppService.mainApp.register()
            return true
        } catch {
            log.error("LaunchAtLogin register failed: \(error.localizedDescription)")
            return false
        }
    }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("LaunchAtLogin toggle failed: \(error.localizedDescription)")
        }
    }
}
