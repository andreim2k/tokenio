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

private typealias RGBA = (CGFloat, CGFloat, CGFloat, CGFloat)

// Generic fallback
private let colorNormal: RGBA = (0.18, 0.82, 0.30, 1.0)
private let colorWarn:   RGBA = (1.0,  0.45, 0.10, 1.0)
private let colorCrit:   RGBA = (1.0,  0.25, 0.20, 1.0)

// Apple system colors (vibrant)
private let colorICloudNormal: RGBA = (0.10,  0.90,  0.22,  1.0)  // Apple green vibrant
private let colorICloudWarn:   RGBA = (1.0,   0.62,  0.0,   1.0)  // Apple orange vibrant
private let colorICloudCrit:   RGBA = (1.0,   0.15,  0.10,  1.0)  // Apple red vibrant

// Google brand colors
private let colorGmailNormal: RGBA = (0.204, 0.659, 0.325, 1.0)  // Google green
private let colorGmailWarn:   RGBA = (0.984, 0.737, 0.020, 1.0)  // Google yellow
private let colorGmailCrit:   RGBA = (0.918, 0.263, 0.208, 1.0)  // Google red

private func providerColor(usageFrac: Double, provider: String) -> RGBA {
    switch provider {
    case "icloud":
        if usageFrac >= 0.9 { return colorICloudCrit }
        if usageFrac >= 0.7 { return colorICloudWarn }
        return colorICloudNormal
    case "gmail":
        if usageFrac >= 0.9 { return colorGmailCrit }
        if usageFrac >= 0.7 { return colorGmailWarn }
        return colorGmailNormal
    default:
        if usageFrac >= 0.9 { return colorCrit }
        if usageFrac >= 0.7 { return colorWarn }
        return colorNormal
    }
}

func usageColor(usageFrac: Double, provider: String = "") -> NSColor {
    let c = providerColor(usageFrac: usageFrac, provider: provider)
    return NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
}

private func providerNormal(_ provider: String) -> RGBA {
    switch provider {
    case "gmail":  return colorGmailNormal
    case "icloud": return colorICloudNormal
    default:       return colorNormal
    }
}

// MARK: - Popup: split-pill bar (left = elapsed, right = remaining)

func drawBar(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
             corner: CGFloat, fillFrac: Double, tickFrac: Double,
             bgAlpha: CGFloat, provider: String = "") {
    guard let ctx = NSGraphicsContext.current else { return }

    // Split point — clamp so both pills are always visible (min 4px each)
    let gap: CGFloat = 3.0
    let minW: CGFloat = 4.0
    let splitX = max(minW, min(CGFloat(tickFrac) * w, w - minW - gap))
    let leftW  = splitX
    let rightX = x + splitX + gap
    let rightW = w - splitX - gap

    let leftPath  = NSBezierPath(roundedRect: NSRect(x: x,      y: y, width: leftW,  height: h), xRadius: corner, yRadius: corner)
    let rightPath = NSBezierPath(roundedRect: NSRect(x: rightX, y: y, width: rightW, height: h), xRadius: corner, yRadius: corner)

    // Tracks
    NSColor(white: 1.0, alpha: bgAlpha).setFill()
    leftPath.fill()
    rightPath.fill()

    let c = providerColor(usageFrac: fillFrac, provider: provider)
    let barColor = NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)

    // Fill spans across both pills (gap is transparent space)
    let totalFill = max(0, min(CGFloat(fillFrac), 1.0)) * w

    let leftFill = min(totalFill, leftW)
    if leftFill > 0 {
        ctx.saveGraphicsState()
        leftPath.setClip()
        barColor.setFill()
        NSRect(x: x, y: y, width: leftFill, height: h).fill()
        ctx.restoreGraphicsState()
    }

    let rightFill = totalFill - leftW - gap
    if rightFill > 0 {
        ctx.saveGraphicsState()
        rightPath.setClip()
        barColor.setFill()
        NSRect(x: rightX, y: y, width: rightFill, height: h).fill()
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
    let fc = providerColor(usageFrac: fillFrac, provider: provider)
    let fillColor = NSColor(red: fc.0, green: fc.1, blue: fc.2, alpha: fc.3)

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
        let c = providerColor(usageFrac: frac, provider: "gmail")
        return NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
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
                                bgAlpha: CGFloat, isDark: Bool, provider: String = "") {
    let baseWhite: CGFloat = isDark ? 1.0 : 0.0
    let c = providerColor(usageFrac: fillFrac, provider: provider)
    let fillColor = NSColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)

    guard let ctx = NSGraphicsContext.current else { return }

    // Split into two pills at tick position
    let gap: CGFloat = 2.0
    let minW: CGFloat = 3.0
    let splitX = max(minW, min(CGFloat(tickFrac) * w, w - minW - gap))
    let leftW  = splitX
    let rightX = x + splitX + gap
    let rightW = w - splitX - gap

    let leftPath  = NSBezierPath(roundedRect: NSRect(x: x,      y: y, width: leftW,  height: h), xRadius: corner, yRadius: corner)
    let rightPath = NSBezierPath(roundedRect: NSRect(x: rightX, y: y, width: rightW, height: h), xRadius: corner, yRadius: corner)

    NSColor(white: baseWhite, alpha: bgAlpha).setFill()
    leftPath.fill()
    rightPath.fill()

    let totalFill = max(0, min(CGFloat(fillFrac), 1.0)) * w

    let leftFill = min(totalFill, leftW)
    if leftFill > 0 {
        ctx.saveGraphicsState()
        leftPath.setClip()
        fillColor.setFill()
        NSRect(x: x, y: y, width: leftFill, height: h).fill()
        ctx.restoreGraphicsState()
    }

    let rightFill = totalFill - leftW - gap
    if rightFill > 0 {
        ctx.saveGraphicsState()
        rightPath.setClip()
        fillColor.setFill()
        NSRect(x: rightX, y: y, width: rightFill, height: h).fill()
        ctx.restoreGraphicsState()
    }
}

// MARK: - Icon factory

private func drawNoDataDash(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, isDark: Bool) {
    let baseWhite: CGFloat = isDark ? 1.0 : 0.0
    let dashH: CGFloat = 1.0
    let dashY = y + (h - dashH) / 2
    NSColor(white: baseWhite, alpha: iconBgAlpha).setFill()
    NSRect(x: x + w * 0.15, y: dashY, width: w * 0.7, height: dashH).fill()
}

func makeIcon(sUsage: Double, sTime: Double, wUsage: Double, wTime: Double,
              sHasData: Bool = true, isDark: Bool = true, accountName: String? = nil) -> NSImage {
    let provider = accountName.map { getEmailProvider($0) } ?? ""
    let img = NSImage(size: NSSize(width: iconW, height: iconH), flipped: false) { _ in
        if sHasData {
            drawICloudIconBar(x: barX0, y: sessionY, w: barW, h: barH,
                              corner: barCorner, fillFrac: sUsage / 100, tickFrac: sTime / 100,
                              bgAlpha: iconBgAlpha, isDark: isDark, provider: provider)
        } else {
            drawNoDataDash(x: barX0, y: sessionY, w: barW, h: barH, isDark: isDark)
        }
        drawICloudIconBar(x: barX0, y: weeklyY, w: barW, h: barH,
                          corner: barCorner, fillFrac: wUsage / 100, tickFrac: wTime / 100,
                          bgAlpha: iconBgAlpha, isDark: isDark, provider: provider)
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
