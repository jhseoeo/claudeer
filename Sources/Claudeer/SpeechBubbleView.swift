import AppKit

class SpeechBubbleView: NSView {
    private let label: NSTextField
    private let padding: CGFloat = 10
    private let tailHeight: CGFloat = 8
    private var dismissTimer: Timer?

    init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13)
        label.textColor = .black
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping

        super.init(frame: .zero)
        wantsLayer = true
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(text: String, above anchorPoint: NSPoint, duration: TimeInterval = 4.0) {
        label.stringValue = text
        label.sizeToFit()

        let bubbleWidth = label.frame.width + padding * 2
        let bubbleHeight = label.frame.height + padding * 2 + tailHeight

        let origin = NSPoint(
            x: anchorPoint.x - bubbleWidth / 2,
            y: anchorPoint.y + 4
        )
        frame = NSRect(x: origin.x, y: origin.y, width: bubbleWidth, height: bubbleHeight)
        label.frame = NSRect(
            x: padding,
            y: tailHeight + padding,
            width: label.frame.width,
            height: label.frame.height
        )

        isHidden = false
        needsDisplay = true

        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTimer?.invalidate()
        isHidden = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden else { return }

        let bubbleRect = NSRect(
            x: 0, y: tailHeight,
            width: bounds.width, height: bounds.height - tailHeight
        )

        let path = NSBezierPath(roundedRect: bubbleRect, xRadius: 8, yRadius: 8)

        let tailPath = NSBezierPath()
        let midX = bounds.midX
        tailPath.move(to: NSPoint(x: midX - 6, y: tailHeight))
        tailPath.line(to: NSPoint(x: midX, y: 0))
        tailPath.line(to: NSPoint(x: midX + 6, y: tailHeight))
        tailPath.close()
        path.append(tailPath)

        NSColor.white.setFill()
        path.fill()
        NSColor.gray.withAlphaComponent(0.5).setStroke()
        path.stroke()
    }
}
