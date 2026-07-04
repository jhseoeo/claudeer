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
    private var isPaused = false
    private var idleTimer: TimeInterval = 0
    private var idleDuration: TimeInterval = 0
    private var transitionWorkItem: DispatchWorkItem?

    private var velocity: CGVector = .zero
    private var flocking: FlockingSettings = .default
    private var cursorGather: CursorGatherSettings = .default
    private var isMeeting = false

    /// Supplies snapshots of the *other* eligible mascots. Defaults to none, so a
    /// solo controller behaves exactly as before. Injected by `MascotManager`.
    var neighbors: () -> [NeighborState] = { [] }

    // Flock tuning (px unless noted). Refined during visual verification (Task 8).
    private static let perceptionRadius: CGFloat = 600   // global-ish, so the group reliably gathers
    private static let separationDistance: CGFloat = 64
    private static let separationWeight: CGFloat = 2.0
    private static let cohesionWeight: CGFloat = 1.6
    private static let alignmentWeight: CGFloat = 0.5
    private static let wanderWeight: CGFloat = 0.5       // keep wander from overpowering cohesion

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
            velocity = .zero
        }
    }

    func setSpeed(_ value: CGFloat) {
        speed = value
    }

    func setFlocking(_ settings: FlockingSettings) {
        flocking = settings
    }

    func setCursorGather(_ settings: CursorGatherSettings) {
        cursorGather = settings
    }

    /// The sprite's center in global screen coordinates.
    var center: CGPoint {
        let p = spriteEngine.position
        let s = spriteEngine.size
        return CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
    }

    var currentVelocity: CGVector { velocity }

    /// Idle, movement-enabled, and not paused/frozen/dragging/meeting.
    var engageableForMeeting: Bool {
        currentState == .idle && !isPaused && !isFrozen && !isDragging
            && !isMeeting && movements.value(for: currentState)
    }

    func setBeingDragged(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            isMoving = false
            isMeeting = false
            velocity = .zero
        } else {
            pickNewIdleDuration()
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            isMoving = false
            isMeeting = false
            velocity = .zero
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
        if isPaused || isFrozen || isDragging { return }
        if !movements.value(for: currentState) {
            isMoving = false
            velocity = .zero
            return
        }
        if flocking.enabled || cursorGather.enabled {
            steeringTick()
        } else {
            legacyWanderTick()
        }
    }

    /// The original target-based wander (both toggles off → identical to before).
    private func legacyWanderTick() {
        if isMoving {
            moveTowardTarget()
        } else {
            idleTimer += 1.0 / 30.0
            if idleTimer >= idleDuration {
                startWalking()
            }
        }
    }

    private func steeringTick() {
        let neighborList = neighbors()
        handleWander(neighborList)
    }

    /// Wander to a random in-area target with stop-and-go rests; blend in flock
    /// forces when flocking is enabled.
    private func handleWander(_ neighborList: [NeighborState]) {
        if !isMoving {
            idleTimer += 1.0 / 30.0
            applySeparationNudge(neighborList)   // don't get overlapped while resting
            if idleTimer >= idleDuration { startWalking() }
            return
        }
        let pos = spriteEngine.position
        let dx = target.x - pos.x
        let dy = target.y - pos.y
        if (dx * dx + dy * dy).squareRoot() < speed {
            spriteEngine.setPosition(clampToAreas(target))
            isMoving = false
            velocity = .zero
            pickNewIdleDuration()
            return
        }
        let toTarget = Flocking.normalized(CGVector(dx: dx, dy: dy))
        var forces: [(CGVector, CGFloat)] = []
        if flocking.enabled {
            let c = center
            forces = [
                (Flocking.separation(center: c, neighbors: neighborList, minDistance: Self.separationDistance), Self.separationWeight),
                (Flocking.cohesion(center: c, neighbors: neighborList, perception: Self.perceptionRadius), Self.cohesionWeight),
                (Flocking.alignment(center: c, velocity: velocity, neighbors: neighborList, perception: Self.perceptionRadius), Self.alignmentWeight),
            ]
        }
        velocity = Flocking.steer(base: CGVector(dx: toTarget.dx * speed * Self.wanderWeight, dy: toTarget.dy * speed * Self.wanderWeight), forces: forces, maxSpeed: speed)
        advance(by: velocity, clampToArea: true)
    }

    /// While resting, still push apart from any overlapping neighbor.
    private func applySeparationNudge(_ neighborList: [NeighborState]) {
        guard flocking.enabled else { return }
        let sep = Flocking.separation(center: center, neighbors: neighborList, minDistance: Self.separationDistance)
        guard sep.dx != 0 || sep.dy != 0 else { return }
        velocity = Flocking.steer(base: .zero, forces: [(sep, Self.separationWeight)], maxSpeed: speed)
        advance(by: velocity, clampToArea: true)
    }

    /// Move by `v`, optionally clamp into the roaming area, and face the movement.
    private func advance(by v: CGVector, clampToArea: Bool) {
        var pos = spriteEngine.position
        pos.x += v.dx
        pos.y += v.dy
        if clampToArea { pos = clampToAreas(pos) }
        if abs(v.dx) > 0.01 { spriteEngine.setFacing(left: v.dx < 0) }
        spriteEngine.setPosition(pos)
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
        isMeeting = false
        velocity = .zero
        isFrozen = true
        let workItem = DispatchWorkItem { [weak self] in
            self?.isFrozen = false
            self?.pickNewIdleDuration()
        }
        transitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }
}
