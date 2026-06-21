import AppKit

protocol InteractionViewDelegate: AnyObject {
    func interactionMouseDown(at locationInWindow: NSPoint, in view: InteractionView)
    func interactionMouseDragged(to locationInWindow: NSPoint, in view: InteractionView)
    func interactionMouseUp(at locationInWindow: NSPoint, in view: InteractionView)
}

class InteractionView: NSView {
    weak var delegate: InteractionViewDelegate?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return self
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.interactionMouseDown(at: event.locationInWindow, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.interactionMouseDragged(to: event.locationInWindow, in: self)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.interactionMouseUp(at: event.locationInWindow, in: self)
    }
}
