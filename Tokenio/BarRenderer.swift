import AppKit

// MARK: - Visual constants

private let iconW: CGFloat = 36
private let iconH: CGFloat = 22

private let barW: CGFloat = 31
private let barH: CGFloat = 6
private let barX0: CGFloat = (iconW - barW) / 2
private let sessionY: CGFloat = 13
private let weeklyY: CGFloat = 3
private let barCorner: CGFloat = 2.5
private let iconBgAlpha: CGFloat = 0.35

// Gmail icon: 2 vertical bars (bar chart style)
private let vBarW: CGFloat = 12
private let vBarH: CGFloat = 18
private let vBarSpacing: CGFloat = 5
private let vBarY: CGFloat = 2  // bottom margin (bottom-left origin)
private let vBarLeftX: CGFloat = (iconW - 2 * vBarW - vBarSpacing) / 2  // ≈ 3.5
private let vBarRightX: CGFloat = vBarLeftX + vBarW + vBarSpacing
private let vBarCorner: CGFloat = 2.0

// Popup menu bars
let menuBarH: CGFloat = 4
let menuBarCorner: CGFloat = 2.0  // = menuBarH/2: perfect pill for iCloud

// MARK: - Colors

private let colorNormal: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.18, 0.82, 0.30, 1.0)
private let colorWarn:   (CGFloat, CGFloat, CGFloat, CGFloat) = (1.0,  0.45, 0.10, 1.0)
private let colorCrit:   (CGFloat, CGFloat, CGFloat, CGFloat) = (1.0,  0.25, 0.20, 1.0)
private let colorGmail:  (CGFloat, CGFloat, CGFloat, CGFloat) = (0.918, 0.263, 0.208, 1.0)
private let colorICloud: (CGFloat, CGFloat, CGFloat, CGFloat) = (0.0,   0.478, 1.0,   1.0)

private func lerp(_ a: (CGFloat, CGFloat, CGFloat, CGFloat),
                  _ b: (CGFloat, CGFloat, CGFloat, CGFloat),
                  _ t: CGFloat) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    let t = max(0, min(1, t))
    return (a.0+(b.0-a.0)*t, a.1+(b.1-a.1)*t, a.2+(b.2-a.2)*t, a.3+(b.3-a.3)*t)
}

private func providerNormal(_ provider: String) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
    switch provider {
    case "gmail":  return colorGmail
    case "icloud": return colorICloud
    default:       return colorNormal
    }
}

func usageColor(usageFrac: Double, provider: String = "") -> NSColor {
    let c: (CGFloat, CGFloat, CGFloat, CGFloat)
    if usageFrac >= 1.0 { c = colorCrit }
    else if usageFrac >= 0.9 { c = lerp(colorWarn, colorCrit, (usageFrac - 0.9) / 0.1) }
    else { c = providerNormal(provider) }
    return NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
}

// MARK: - Popup: smooth capsule bar (iCloud / default)

func drawBar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
             corner: CGFloat, fillFrac: Double, tickFrac: Double,
             bgAlpha: CGFloat, provider: String = "") {
    let trackPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                                  xRadius: corner, yRadius: corner)
    guard let ctx = NSGraphicsContext.current else { return }

    NSColor(white: 1.0, alpha: bgAlpha).setFill()
    trackPath.fill()

    let fw = max(0, min(CGFloat(fillFrac), 1.0)) * w
    if fw > 0 {
        ctx.saveGraphicsState()
        trackPath.setClip()
        usageColor(usageFrac: fillFrac, provider: provider).setFill()
        NSRect(x: x, y: y, width: fw, height: h).fill()
        ctx.restoreGraphicsState()
    }
}

// MARK: - Popup: segmented bar (Gmail)

func drawSegmentedBar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                      fillFrac: Double, bgAlpha: CGFloat,
                      provider: String = "", numSegments: Int = 5) {
    guard let ctx = NSGraphicsContext.current else { return }
    let gapW: CGFloat = 2.5
    let segW = (w - CGFloat(numSegments - 1) * gapW) / CGFloat(numSegments)
    let fw = max(0, min(CGFloat(fillFrac), 1.0)) * w
    let fillColor = usageColor(usageFrac: fillFrac, provider: provider)

    for i in 0..<numSegments {
        let segX = x + CGFloat(i) * (segW + gapW)
        let segPath = NSBezierPath(roundedRect: NSRect(x: segX, y: y, width: segW, height: h),
                                    xRadius: 1.0, yRadius: 1.0)
        NSColor(white: 1.0, alpha: bgAlpha).setFill()
        segPath.fill()

        let overlapW = min(x + fw, segX + segW) - segX
        if overlapW > 0 {
            ctx.saveGraphicsState()
            segPath.setClip()
            fillColor.setFill()
            NSRect(x: segX, y: y, width: overlapW, height: h).fill()
            ctx.restoreGraphicsState()
        }
    }
}

// MARK: - Icon: Gmail vertical bar chart

private func drawGmailIconBars(sUsage: Double, wUsage: Double, isDark: Bool) {
    let baseWhite: CGFloat = isDark ? 1.0 : 0.0
    guard let ctx = NSGraphicsContext.current else { return }

    func barFillColor(_ frac: Double) -> NSColor {
        if frac >= 1.0 { return NSColor(red: 1.0, green: 0.25, blue: 0.20, alpha: 1.0) }
        if frac >= 0.9 { return NSColor(red: 1.0, green: 0.45, blue: 0.10, alpha: 1.0) }
        return NSColor(white: baseWhite, alpha: 0.82)
    }

    func drawOneBar(x: CGFloat, fillFrac: Double) {
        let trackPath = NSBezierPath(roundedRect: NSRect(x: x, y: vBarY, width: vBarW, height: vBarH),
                                      xRadius: vBarCorner, yRadius: vBarCorner)
        NSColor(white: baseWhite, alpha: iconBgAlpha).setFill()
        trackPath.fill()

        let fh = CGFloat(max(0, min(fillFrac, 1.0))) * vBarH
        if fh > 0 {
            ctx.saveGraphicsState()
            trackPath.setClip()
            barFillColor(fillFrac).setFill()
            // Fill from the bottom upward
            NSRect(x: x, y: vBarY, width: vBarW, height: fh).fill()
            ctx.restoreGraphicsState()
        }
    }

    drawOneBar(x: vBarLeftX,  fillFrac: sUsage)
    drawOneBar(x: vBarRightX, fillFrac: wUsage)
}

// MARK: - Icon: iCloud/default horizontal capsule bars

private func drawICloudIconBar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
                                corner: CGFloat, fillFrac: Double, tickFrac: Double,
                                bgAlpha: CGFloat, isDark: Bool) {
    let baseWhite: CGFloat = isDark ? 1.0 : 0.0
    let fillColor: NSColor
    if fillFrac >= 1.0 { fillColor = NSColor(red: 1.0, green: 0.25, blue: 0.20, alpha: 1.0) }
    else if fillFrac >= 0.9 { fillColor = NSColor(red: 1.0, green: 0.45, blue: 0.10, alpha: 1.0) }
    else { fillColor = NSColor(white: baseWhite, alpha: 0.82) }

    let trackPath = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                                  xRadius: corner, yRadius: corner)
    guard let ctx = NSGraphicsContext.current else { return }

    NSColor(white: baseWhite, alpha: bgAlpha).setFill()
    trackPath.fill()

    let fw = max(0, min(CGFloat(fillFrac), 1.0)) * w
    if fw > 0 {
        ctx.saveGraphicsState()
        trackPath.setClip()
        fillColor.setFill()
        NSRect(x: x, y: y, width: fw, height: h).fill()
        ctx.restoreGraphicsState()
    }

    // Soft tick marker
    let tx = x + CGFloat(tickFrac) * w
    ctx.saveGraphicsState()
    trackPath.setClip()
    NSColor(white: baseWhite, alpha: 0.45).setFill()
    NSRect(x: tx - 0.75, y: y, width: 1.5, height: h).fill()
    ctx.restoreGraphicsState()
}

// MARK: - Icon factory

func makeIcon(sUsage: Double, sTime: Double, wUsage: Double, wTime: Double,
              isDark: Bool = true, accountName: String? = nil) -> NSImage {
    let img = NSImage(size: NSSize(width: iconW, height: iconH), flipped: false) { _ in
        drawICloudIconBar(x: barX0, y: sessionY, w: barW, h: barH,
                          corner: barCorner, fillFrac: sUsage / 100, tickFrac: sTime / 100,
                          bgAlpha: iconBgAlpha, isDark: isDark)
        drawICloudIconBar(x: barX0, y: weeklyY, w: barW, h: barH,
                          corner: barCorner, fillFrac: wUsage / 100, tickFrac: wTime / 100,
                          bgAlpha: iconBgAlpha, isDark: isDark)
        return true
    }
    img.isTemplate = false
    return img
}

func makeDisconnectedIcon() -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
    let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Disconnected")?
        .withSymbolConfiguration(config)
    let img = symbol ?? NSImage()
    img.isTemplate = true
    return img
}
