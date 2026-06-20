import AppKit

class CharacterController {
    private let spriteEngine: SpriteEngine
    private var movementTimer: Timer?
    private var currentAreas: [CGRect] = []
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

    func setAreas(_ rects: [CGRect]) {
        currentAreas = rects.filter { !$0.isEmpty }
        let pos = clampToAreas(spriteEngine.position)
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
        guard let next = randomPointInAreas() else { return }
        isMoving = true
        target = next
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

    private func randomPointInAreas() -> NSPoint? {
        let spriteSize = spriteEngine.size
        let usable = currentAreas.compactMap { rect -> CGRect? in
            let r = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(0, rect.width - spriteSize.width),
                height: max(0, rect.height - spriteSize.height)
            )
            return r.width >= 0 && r.height >= 0 ? r : nil
        }
        guard !usable.isEmpty else { return nil }
        let weights = usable.map { max(1, $0.width * $0.height) }
        let total = weights.reduce(0, +)
        var pick = CGFloat.random(in: 0...total)
        var index = 0
        for (i, w) in weights.enumerated() {
            pick -= w
            if pick <= 0 { index = i; break }
            index = i
        }
        let rect = usable[index]
        return NSPoint(
            x: CGFloat.random(in: rect.minX...max(rect.minX, rect.maxX)),
            y: CGFloat.random(in: rect.minY...max(rect.minY, rect.maxY))
        )
    }

    private func clampToAreas(_ point: NSPoint) -> NSPoint {
        let spriteSize = spriteEngine.size
        guard !currentAreas.isEmpty else { return point }
        if currentAreas.contains(where: { $0.contains(point) }) {
            return point
        }
        var bestPoint = point
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for rect in currentAreas {
            let maxX = max(rect.minX, rect.maxX - spriteSize.width)
            let maxY = max(rect.minY, rect.maxY - spriteSize.height)
            let clamped = NSPoint(
                x: min(max(point.x, rect.minX), maxX),
                y: min(max(point.y, rect.minY), maxY)
            )
            let dx = clamped.x - point.x
            let dy = clamped.y - point.y
            let dist = dx * dx + dy * dy
            if dist < bestDistance {
                bestDistance = dist
                bestPoint = clamped
            }
        }
        return bestPoint
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
