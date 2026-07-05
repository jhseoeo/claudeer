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

    /// When set (by `EncounterController`) the mascot obeys the social directive
    /// — gather to a point / cuddle facing it / disperse from it — instead of
    /// wandering. Cleared when the encounter ends.
    private var interaction: InteractionDirective?
    private var cuddleBaseY: CGFloat?   // resting y captured when cuddling starts; hop bounces around it
    private var cuddleFrame = 0

    /// Supplies snapshots of the *other* mascots (centers) so wanderers avoid
    /// overlapping. Defaults to none, so a solo controller behaves as before.
    var neighbors: () -> [NeighborState] = { [] }

    // Movement tuning (px unless noted).
    private static let separationDistance: CGFloat = 64
    private static let separationWeight: CGFloat = 2.0
    private static let cursorSeekWeight: CGFloat = 1.0
    private static let facingFlipThreshold: CGFloat = 0.3   // smoothed |v.x| needed to turn the sprite
    private static let velocityDamping: CGFloat = 0.82      // momentum low-pass; smooth, no dense-cluster vibration
    private static let hopHeight: CGFloat = 16              // cuddle bounce height (px)
    private static let hopSpeed: Double = 0.32             // cuddle bounce rate (radians/frame; ~0.3s per hop)

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

    /// Idle, movement-enabled, and not paused/frozen/dragging — eligible to be
    /// pulled into a social encounter.
    var availableForEncounter: Bool {
        currentState == .idle && !isPaused && !isFrozen && !isDragging
            && movements.value(for: currentState)
    }

    /// Drive this mascot's current encounter phase (set every tick by the
    /// coordinator while an encounter is active).
    func setInteraction(_ directive: InteractionDirective) {
        interaction = directive
    }

    /// Release the mascot back to free wandering.
    func clearInteraction() {
        interaction = nil
        cuddleBaseY = nil
        pickNewIdleDuration()
    }

    func setBeingDragged(_ dragging: Bool) {
        isDragging = dragging
        if dragging {
            isMoving = false
            interaction = nil
            velocity = .zero
        } else {
            pickNewIdleDuration()
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            isMoving = false
            interaction = nil
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
        if let directive = interaction {
            handleInteraction(directive)
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
        if handleCursorSeek(neighborList) { return }
        handleWander(neighborList)
    }

    /// Coordinator-driven social behavior: gather toward / cuddle facing /
    /// disperse from the encounter focus point.
    private func handleInteraction(_ directive: InteractionDirective) {
        isMoving = false
        if directive.mode != .cuddle { cuddleBaseY = nil }
        let c = center
        switch directive.mode {
        case .cuddle:
            velocity = .zero
            // A little celebratory hop, bouncing around the spot where cuddling began.
            if cuddleBaseY == nil { cuddleBaseY = spriteEngine.position.y; cuddleFrame = 0 }
            cuddleFrame += 1
            let hop = Self.hopHeight * CGFloat(abs(sin(Double(cuddleFrame) * Self.hopSpeed)))
            spriteEngine.setPosition(NSPoint(x: spriteEngine.position.x, y: (cuddleBaseY ?? spriteEngine.position.y) + hop))
            if abs(directive.focus.x - c.x) > 0.01 {
                spriteEngine.setFacing(left: directive.focus.x < c.x)
            }
        case .gather:
            let toFocus = Flocking.normalized(CGVector(dx: directive.focus.x - c.x, dy: directive.focus.y - c.y))
            let sep = Flocking.separation(center: c, neighbors: neighbors(), minDistance: Self.separationDistance)
            let desired = Flocking.steer(base: CGVector(dx: toFocus.dx * speed, dy: toFocus.dy * speed),
                                         forces: [(sep, Self.separationWeight)], maxSpeed: speed)
            move(toward: desired, clampToArea: true)
        case .disperse:
            var away = Flocking.normalized(CGVector(dx: c.x - directive.focus.x, dy: c.y - directive.focus.y))
            if away.dx == 0 && away.dy == 0 { away = CGVector(dx: 1, dy: 0) }
            move(toward: CGVector(dx: away.dx * speed, dy: away.dy * speed), clampToArea: true)
        }
    }

    /// If cursor-gather is on and the cursor is within radius, steer toward it
    /// (still separating from neighbors) without clamping to the roaming area.
    /// Returns true when it handled this tick.
    private func handleCursorSeek(_ neighborList: [NeighborState]) -> Bool {
        guard cursorGather.enabled else { return false }
        let cursor = NSEvent.mouseLocation   // NSPoint == CGPoint, global screen coords
        guard let dir = Flocking.cursorSeek(center: center, cursor: cursor, radius: CGFloat(cursorGather.radius)) else {
            return false
        }
        isMoving = false
        let sep = Flocking.separation(center: center, neighbors: neighborList, minDistance: Self.separationDistance)
        let desired = Flocking.steer(
            base: CGVector(dx: dir.dx * speed * Self.cursorSeekWeight, dy: dir.dy * speed * Self.cursorSeekWeight),
            forces: [(sep, Self.separationWeight)],
            maxSpeed: speed
        )
        move(toward: desired, clampToArea: false)
        return true
    }

    /// Random wander to an in-area target with stop-and-go rests; just avoid
    /// overlapping neighbors (no constant cohesion — grouping is episodic and
    /// driven by `EncounterController`).
    private func handleWander(_ neighborList: [NeighborState]) {
        if !isMoving {
            idleTimer += 1.0 / 30.0
            applySeparationNudge(neighborList)
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
        let forces: [(CGVector, CGFloat)] = flocking.enabled
            ? [(Flocking.separation(center: center, neighbors: neighborList, minDistance: Self.separationDistance), Self.separationWeight)]
            : []
        let desired = Flocking.steer(base: CGVector(dx: toTarget.dx * speed, dy: toTarget.dy * speed), forces: forces, maxSpeed: speed)
        move(toward: desired, clampToArea: true)
    }

    /// While resting, still push apart from any overlapping neighbor.
    private func applySeparationNudge(_ neighborList: [NeighborState]) {
        guard flocking.enabled else { return }
        let sep = Flocking.separation(center: center, neighbors: neighborList, minDistance: Self.separationDistance)
        guard sep.dx != 0 || sep.dy != 0 else { return }
        let desired = Flocking.steer(base: .zero, forces: [(sep, Self.separationWeight)], maxSpeed: speed)
        move(toward: desired, clampToArea: true)
    }

    private var smoothedVX: CGFloat = 0    // low-pass filter so cluster jitter doesn't flip the sprite

    /// Apply `desired` velocity through a momentum low-pass, then move. Damping
    /// averages out any per-frame direction flips so mascots drift smoothly
    /// instead of vibrating, while a sustained direction ramps up to full speed.
    private func move(toward desired: CGVector, clampToArea: Bool) {
        let d = Self.velocityDamping
        velocity = CGVector(dx: velocity.dx * d + desired.dx * (1 - d),
                            dy: velocity.dy * d + desired.dy * (1 - d))
        advance(by: velocity, clampToArea: clampToArea)
    }

    /// Move by `v`, optionally clamp into the roaming area, and face the movement.
    private func advance(by v: CGVector, clampToArea: Bool) {
        var pos = spriteEngine.position
        pos.x += v.dx
        pos.y += v.dy
        if clampToArea { pos = clampToAreas(pos) }
        // Face by a *smoothed* horizontal velocity so brief jitter doesn't flip
        // the sprite — it only turns on sustained travel.
        smoothedVX = smoothedVX * 0.85 + v.dx * 0.15
        if abs(smoothedVX) > Self.facingFlipThreshold {
            spriteEngine.setFacing(left: smoothedVX < 0)
        }
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
        interaction = nil
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
