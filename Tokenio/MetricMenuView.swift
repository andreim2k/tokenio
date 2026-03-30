import AppKit

private let menuW: CGFloat = 220
private let menuPad: CGFloat = 14
private let viewH: CGFloat = 52

class MetricMenuView: NSView {
    private var title: String
    private var titleSuffix: String = ""
    private var value: String = "—"
    private var usageFrac: Double = 0
    private var timeFrac: Double = 0
    private var resetText: String = "—"
    private var provider: String = ""

    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: menuW, height: viewH))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func setTitle(_ title: String, suffix: String = "") {
        self.title = title
        self.titleSuffix = suffix
        needsDisplay = true
    }

    func setData(value: String, usageFrac: Double, timeFrac: Double, resetStr: String) {
        self.value = value
        self.usageFrac = usageFrac
        self.timeFrac = timeFrac
        self.resetText = resetStr
        needsDisplay = true
    }

    func setProvider(_ p: String) {
        provider = p
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fTitle = NSFont.systemFont(ofSize: 11, weight: .regular)
        let fVal   = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let fReset = NSFont.systemFont(ofSize: 10, weight: .regular)
        let cLabel = NSColor.labelColor
        let cSec   = NSColor.secondaryLabelColor
        let cTert  = NSColor.tertiaryLabelColor

        let titleStr = NSAttributedString(string: title, attributes: [
            .font: fTitle, .foregroundColor: cSec
        ])
        titleStr.draw(at: NSPoint(x: menuPad, y: 9))

        if !titleSuffix.isEmpty {
            let fSuffix = NSFont.systemFont(ofSize: 9, weight: .regular)
            let sfx = NSAttributedString(string: " \(titleSuffix)", attributes: [
                .font: fSuffix, .foregroundColor: cTert
            ])
            sfx.draw(at: NSPoint(x: menuPad + titleStr.size().width, y: 10))
        }

        let valStr = NSAttributedString(string: value, attributes: [
            .font: fVal, .foregroundColor: cLabel
        ])
        valStr.draw(at: NSPoint(x: menuW - menuPad - valStr.size().width, y: 8))

        let bx = menuPad
        let bw = menuW - 2 * menuPad
        let by: CGFloat = 20

        drawBar(x: bx, y: by, w: bw, h: menuBarH,
                corner: menuBarCorner, fillFrac: usageFrac, tickFrac: timeFrac,
                bgAlpha: 0.10, provider: provider)

        let resetStr = NSAttributedString(string: resetText, attributes: [
            .font: fReset, .foregroundColor: cTert
        ])
        resetStr.draw(at: NSPoint(x: menuPad, y: 33))
    }
}
