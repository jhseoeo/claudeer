import AppKit

class CharacterController {
    private let spriteEngine: SpriteEngine
    private var movementTimer: Timer?
    private var currentArea: CGRect = .zero
    private var target: NSPoint = .zero
    private var speed: CGFloat = 2.0
    private var movements: MovementSettings = .allOn
    private var currentState: MascotState = .idle

    private var isMoving = false
    private var isFrozen = false
    private var isDragging = false
    private var idleTimer: TimeInterval = 0
    private var idleDuration: TimeInterval = 0
    private var transitionWorkItem: DispatchWorkItem?

    init(spriteEngine: SpriteEngine) {
        self.spriteEngine = spriteEngine
    }

    func setArea(_ preset: AreaPreset, screenSize: CGSize) {
        currentArea = preset.rect(for: screenSize)
        let pos = clampToArea(spriteEngine.position)
        spriteEngine.setPosition(pos)
    }

    func setMovement(_ settings: MovementSettings) {
        movements = settings
        if !movements.value(for: currentState) {
            isMoving = false
        }
    }

    func setSpeed(_ value: CGFloat) {
        speed = value
    }

    func setBeingDragged(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            isMoving = false
        } else {
            pickNewIdleDuration()
        }
    }

    var spriteFrame: NSRect { spriteEngine.view.frame }

    func setSpritePosition(_ point: NSPoint) {
        spriteEngine.setPosition(point)
    }

    func start() {
        pickNewIdleDuration()
        movementTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        movementTimer?.invalidate()
        movementTimer = nil
    }

    private func tick() {
        if isFrozen || isDragging { return }
        if !movements.value(for: currentState) {
            isMoving = false
            return
        }
        if isMoving {
            moveTowardTarget()
        } else {
            idleTimer += 1.0 / 30.0
            if idleTimer >= idleDuration {
                startWalking()
            }
        }
    }

    private func startWalking() {
        isMoving = true
        target = randomPointInArea()
    }

    private func moveTowardTarget() {
        var pos = spriteEngine.position
        let dx = target.x - pos.x
        let dy = target.y - pos.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist < speed {
            pos = target
            isMoving = false
            pickNewIdleDuration()
        } else {
            if abs(dx) > 0.01 {
                let left = dx < 0
                spriteEngine.setFacing(left: left)
            }
            pos.x += (dx / dist) * speed
            pos.y += (dy / dist) * speed
        }
        spriteEngine.setPosition(pos)
    }

    private func randomPointInArea() -> NSPoint {
        let spriteSize = spriteEngine.size
        let minX = currentArea.minX
        let maxX = currentArea.maxX - spriteSize.width
        let minY = currentArea.minY
        let maxY = currentArea.maxY - spriteSize.height
        return NSPoint(
            x: CGFloat.random(in: minX...max(minX, maxX)),
            y: CGFloat.random(in: minY...max(minY, maxY))
        )
    }

    private func clampToArea(_ point: NSPoint) -> NSPoint {
        let spriteSize = spriteEngine.size
        return NSPoint(
            x: min(max(point.x, currentArea.minX), currentArea.maxX - spriteSize.width),
            y: min(max(point.y, currentArea.minY), currentArea.maxY - spriteSize.height)
        )
    }

    private func pickNewIdleDuration() {
        idleTimer = 0
        idleDuration = Double.random(in: 2.0...6.0)
    }

    func transitionTo(_ state: MascotState) {
        transitionWorkItem?.cancel()
        spriteEngine.setState(state)
        currentState = state
        isMoving = false
        isFrozen = true
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFrozen = false
            self?.pickNewIdleDuration()
        }
        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
}
