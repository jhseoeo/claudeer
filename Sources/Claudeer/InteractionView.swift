import AppKit

protocol InteractionViewDelegate: AnyObject {
    func interactionMouseDown(at locationInWindow: NSPoint)
    func interactionMouseDragged(to locationInWindow: NSPoint)
    func interactionMouseUp(at locationInWindow: NSPoint)
}

class InteractionView: NSView {
    weak var delegate: InteractionViewDelegate?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.interactionMouseDown(at: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.interactionMouseDragged(to: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.interactionMouseUp(at: event.locationInWindow)
    }
}
