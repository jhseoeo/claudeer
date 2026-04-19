import AppKit

class CharacterController {
    private let spriteEngine: SpriteEngine
    private var movementTimer: Timer?
    private var currentArea: CGRect = .zero
    private var target: NSPoint = .zero
    private var speed: CGFloat = 2.0

    private var isMoving = false
    private var idleTimer: TimeInterval = 0
    private var idleDuration: TimeInterval = 0

    init(spriteEngine: SpriteEngine) {
        self.spriteEngine = spriteEngine
    }

    func setArea(_ preset: AreaPreset, screenSize: CGSize) {
        currentArea = preset.rect(for: screenSize)
        let pos = clampToArea(spriteEngine.position)
        spriteEngine.setPosition(pos)
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
        spriteEngine.setState(.walk)
    }

    private func moveTowardTarget() {
        var pos = spriteEngine.position
        let dx = target.x - pos.x
        let dy = target.y - pos.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist < speed {
            pos = target
            isMoving = false
            spriteEngine.setState(.idle)
            pickNewIdleDuration()
        } else {
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

    private var alertWorkItem: DispatchWorkItem?

    func triggerAlert() {
        alertWorkItem?.cancel()
        spriteEngine.setState(.alert)
        isMoving = false
        let workItem = DispatchWorkItem { [weak self] in
            self?.spriteEngine.setState(.idle)
            self?.pickNewIdleDuration()
        }
        alertWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
}
