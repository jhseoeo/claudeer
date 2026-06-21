import AppKit

/// A small rounded pill showing a session name, displayed under a mascot.
class NameLabelView: NSView {
    private let label: NSTextField
    private let hPadding: CGFloat = 6
    private let vPadding: CGFloat = 2
    private let maxTextWidth: CGFloat = 160

    init() {
        label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Update the displayed text and resize the pill to fit (capped width).
    func setText(_ text: String) {
        label.stringValue = text
        label.sizeToFit()

        let textWidth = min(label.frame.width, maxTextWidth)
        let width = textWidth + hPadding * 2
        let height = label.frame.height + vPadding * 2

        setFrameSize(NSSize(width: width, height: height))
        label.frame = NSRect(x: hPadding, y: vPadding, width: textWidth, height: label.frame.height)
        layer?.cornerRadius = height / 2
    }
}
