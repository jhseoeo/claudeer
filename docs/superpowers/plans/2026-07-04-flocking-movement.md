# Flocking Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the per-session mascots social "NPC" movement — they loosely flock together, briefly face-and-pause when they meet, and (optionally) gather to the mouse cursor — all config-gated.

**Architecture:** Keep each mascot's own `CharacterController` + 30 fps timer. Add a pure, testable `Flocking` module for the force math. `MascotManager` injects neighbor snapshots into each controller; the cursor is read directly from `NSEvent.mouseLocation`. The controller's tick gains a velocity-based "steering engine" (mode priority: meeting → cursor-seek → wander+flock) used only when a behavior is enabled; with both off it runs the unchanged legacy wander.

**Tech Stack:** Swift, AppKit (overlay/sprites), SwiftUI (Preferences), XCTest. Pure stdlib only.

## Global Constraints

- Pure stdlib on both sides — no external Swift packages, no Python pip deps.
- New config keys use snake_case JSON (`flocking`, `cursor_gather`) and the existing `decodeIfPresent(...) ?? .default` backward-compat pattern — old config files must still load.
- All positions/cursor are AppKit **global screen coordinates** (y-up, primary-screen-relative). Distances are measured between sprite **centers** (`position + size/2`).
- 30 fps tick (`1.0 / 30.0` per frame). Max step magnitude per frame = `config.speed` (range `0.5...6.0`).
- `swift test` requires a full Xcode.app install (not just CLT).
- `Flocking.swift` must have **no AppKit/UI dependency** (CoreGraphics only) so it stays unit-testable — the cursor is read in `CharacterController` and passed in as a `CGPoint`.
- Bump `.claude-plugin/plugin.json` version on functional changes (done in the final task).
- Default behavior: `flocking` **ON**, `cursor_gather` **OFF**.

---

### Task 1: Config — flocking & cursor-gather settings

**Files:**
- Modify: `Sources/Claudeer/Config.swift` (add two structs after `FlipSettings` at line 41; extend `SpeakiConfig` at lines 55–136)
- Modify: `Sources/Claudeer/AssetStore.swift` (extend `setConfig` at lines 150–173; add two update methods after line 148)
- Test: `Tests/ClaudeerTests/ConfigTests.swift` (append test methods)

**Interfaces:**
- Produces:
  - `struct FlockingSettings: Codable { let enabled: Bool; static let default }`
  - `struct CursorGatherSettings: Codable { let enabled: Bool; let radius: Double; static let defaultRadius: Double; static let radiusRange: ClosedRange<Double>; static let default }`
  - `SpeakiConfig.flocking: FlockingSettings`, `SpeakiConfig.cursorGather: CursorGatherSettings`
  - `AssetStore.updateFlocking(_ enabled: Bool)`, `AssetStore.updateCursorGather(_ value: CursorGatherSettings)`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeerTests/ConfigTests.swift` (inside the `ConfigTests` class):

```swift
    func testParseConfigWithFlockingAndCursorGather() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" },
          "flocking": { "enabled": false },
          "cursor_gather": { "enabled": true, "radius": 320 }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertFalse(config.flocking.enabled)
        XCTAssertTrue(config.cursorGather.enabled)
        XCTAssertEqual(config.cursorGather.radius, 320)
    }

    func testParseConfigWithoutFlockingUsesDefaults() throws {
        let json = """
        {
          "default_area": "bottom",
          "speeches": { "idle": "a", "working": "b" }
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(SpeakiConfig.self, from: json)
        XCTAssertTrue(config.flocking.enabled)          // default ON
        XCTAssertFalse(config.cursorGather.enabled)      // default OFF
        XCTAssertEqual(config.cursorGather.radius, 250)
    }

    func testConfigRoundTripsFlockingAndCursor() throws {
        let config = SpeakiConfig(
            defaultArea: "bottom",
            speeches: Speeches(idle: "a", working: "b"),
            loops: .off, movements: .allOn, speed: 2.0, flips: .off,
            flocking: FlockingSettings(enabled: false),
            cursorGather: CursorGatherSettings(enabled: true, radius: 300)
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(SpeakiConfig.self, from: data)
        XCTAssertFalse(decoded.flocking.enabled)
        XCTAssertTrue(decoded.cursorGather.enabled)
        XCTAssertEqual(decoded.cursorGather.radius, 300)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConfigTests`
Expected: FAIL — `value of type 'SpeakiConfig' has no member 'flocking'` (compile error).

- [ ] **Step 3: Add the two settings structs**

In `Sources/Claudeer/Config.swift`, immediately after the `FlipSettings` struct (line 41), add:

```swift
struct FlockingSettings: Codable {
    let enabled: Bool

    static let `default` = FlockingSettings(enabled: true)
}

struct CursorGatherSettings: Codable {
    let enabled: Bool
    let radius: Double

    static let defaultRadius: Double = 250
    static let radiusRange: ClosedRange<Double> = 100...600
    static let `default` = CursorGatherSettings(enabled: false, radius: defaultRadius)
}
```

- [ ] **Step 4: Extend `SpeakiConfig`**

In `Sources/Claudeer/Config.swift`, replace the entire `struct SpeakiConfig: Codable { ... }` (lines 55–136) with:

```swift
struct SpeakiConfig: Codable {
    let defaultArea: String
    let speeches: Speeches
    let loops: LoopSettings
    let movements: MovementSettings
    let speed: Double
    let flips: FlipSettings
    let targetScreenID: String?
    let showSessionLabel: Bool
    let ntfy: NtfySettings
    let flocking: FlockingSettings
    let cursorGather: CursorGatherSettings

    static let defaultSpeed: Double = 2.0
    static let speedRange: ClosedRange<Double> = 0.5...6.0

    enum CodingKeys: String, CodingKey {
        case defaultArea = "default_area"
        case speeches
        case loops
        case movements
        case speed
        case flips
        case targetScreenID = "target_screen_id"
        case showSessionLabel = "show_session_label"
        case ntfy
        case flocking
        case cursorGather = "cursor_gather"
    }

    init(defaultArea: String, speeches: Speeches, loops: LoopSettings, movements: MovementSettings, speed: Double, flips: FlipSettings, targetScreenID: String? = nil, showSessionLabel: Bool = true, ntfy: NtfySettings = .off, flocking: FlockingSettings = .default, cursorGather: CursorGatherSettings = .default) {
        self.defaultArea = defaultArea
        self.speeches = speeches
        self.loops = loops
        self.movements = movements
        self.speed = speed
        self.flips = flips
        self.targetScreenID = targetScreenID
        self.showSessionLabel = showSessionLabel
        self.ntfy = ntfy
        self.flocking = flocking
        self.cursorGather = cursorGather
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultArea = try container.decode(String.self, forKey: .defaultArea)
        self.speeches = try container.decode(Speeches.self, forKey: .speeches)
        self.loops = try container.decodeIfPresent(LoopSettings.self, forKey: .loops) ?? .off
        self.movements = try container.decodeIfPresent(MovementSettings.self, forKey: .movements) ?? .allOn
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? Self.defaultSpeed
        self.flips = try container.decodeIfPresent(FlipSettings.self, forKey: .flips) ?? .off
        self.targetScreenID = try container.decodeIfPresent(String.self, forKey: .targetScreenID)
        self.showSessionLabel = try container.decodeIfPresent(Bool.self, forKey: .showSessionLabel) ?? true
        self.ntfy = try container.decodeIfPresent(NtfySettings.self, forKey: .ntfy) ?? .off
        self.flocking = try container.decodeIfPresent(FlockingSettings.self, forKey: .flocking) ?? .default
        self.cursorGather = try container.decodeIfPresent(CursorGatherSettings.self, forKey: .cursorGather) ?? .default
    }

    static let `default` = SpeakiConfig(
        defaultArea: "bottom",
        speeches: Speeches(
            idle: "Need your input!",
            working: "On it!"
        ),
        loops: .off,
        movements: .allOn,
        speed: defaultSpeed,
        flips: .off,
        targetScreenID: nil,
        showSessionLabel: true,
        ntfy: .off,
        flocking: .default,
        cursorGather: .default
    )

    static func load(from url: URL) -> SpeakiConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(SpeakiConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
```

- [ ] **Step 5: Extend `AssetStore.setConfig` and add update methods**

In `Sources/Claudeer/AssetStore.swift`, add these two methods immediately after `updateNtfy` (line 148):

```swift
    func updateFlocking(_ enabled: Bool) {
        setConfig(flocking: FlockingSettings(enabled: enabled))
    }

    func updateCursorGather(_ value: CursorGatherSettings) {
        setConfig(cursorGather: value)
    }
```

Then replace the `setConfig(...)` method (lines 150–173) with:

```swift
    private func setConfig(
        speeches: Speeches? = nil,
        loops: LoopSettings? = nil,
        movements: MovementSettings? = nil,
        speed: Double? = nil,
        flips: FlipSettings? = nil,
        targetScreenID: String??  = nil,
        showSessionLabel: Bool? = nil,
        ntfy: NtfySettings? = nil,
        flocking: FlockingSettings? = nil,
        cursorGather: CursorGatherSettings? = nil
    ) {
        config = SpeakiConfig(
            defaultArea: config.defaultArea,
            speeches: speeches ?? config.speeches,
            loops: loops ?? config.loops,
            movements: movements ?? config.movements,
            speed: speed ?? config.speed,
            flips: flips ?? config.flips,
            targetScreenID: targetScreenID ?? config.targetScreenID,
            showSessionLabel: showSessionLabel ?? config.showSessionLabel,
            ntfy: ntfy ?? config.ntfy,
            flocking: flocking ?? config.flocking,
            cursorGather: cursorGather ?? config.cursorGather
        )
        try? config.save(to: configURL)
        notify()
    }
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ConfigTests`
Expected: PASS (all `ConfigTests`, including the three new ones).

- [ ] **Step 7: Commit**

```bash
git add Sources/Claudeer/Config.swift Sources/Claudeer/AssetStore.swift Tests/ClaudeerTests/ConfigTests.swift
git commit -m "feat: add flocking and cursor-gather config settings"
```

---

### Task 2: `Flocking.swift` — pure force math

**Files:**
- Create: `Sources/Claudeer/Flocking.swift`
- Test: `Tests/ClaudeerTests/FlockingTests.swift`

**Interfaces:**
- Produces:
  - `struct NeighborState { let center: CGPoint; let velocity: CGVector; let engageableForMeeting: Bool }`
  - `enum Flocking` with static funcs:
    - `separation(center:neighbors:minDistance:) -> CGVector`
    - `cohesion(center:neighbors:perception:) -> CGVector`
    - `alignment(center:velocity:neighbors:perception:) -> CGVector`
    - `cursorSeek(center:cursor:radius:) -> CGVector?`
    - `nearestMeetTarget(center:neighbors:meetDistance:) -> CGPoint?`
    - `steer(base:forces:maxSpeed:) -> CGVector`  (`forces: [(CGVector, CGFloat)]`)
    - `normalized(_:) -> CGVector`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeerTests/FlockingTests.swift`:

```swift
import XCTest
@testable import Claudeer

final class FlockingTests: XCTestCase {
    private func neighbor(_ x: CGFloat, _ y: CGFloat, vx: CGFloat = 0, vy: CGFloat = 0, engageable: Bool = false) -> NeighborState {
        NeighborState(center: CGPoint(x: x, y: y), velocity: CGVector(dx: vx, dy: vy), engageableForMeeting: engageable)
    }

    func testSeparationPushesAwayFromCloseNeighbor() {
        let f = Flocking.separation(center: CGPoint(x: 100, y: 100), neighbors: [neighbor(110, 100)], minDistance: 50)
        XCTAssertLessThan(f.dx, 0)   // neighbor is on the right → pushed left
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testSeparationIgnoresFarNeighbor() {
        let f = Flocking.separation(center: CGPoint(x: 100, y: 100), neighbors: [neighbor(400, 100)], minDistance: 50)
        XCTAssertEqual(f.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testCohesionPointsTowardGroupCentroid() {
        let f = Flocking.cohesion(center: CGPoint(x: 0, y: 0), neighbors: [neighbor(100, 0), neighbor(100, 100)], perception: 500)
        XCTAssertGreaterThan(f.dx, 0)
        XCTAssertGreaterThan(f.dy, 0)
    }

    func testCohesionIgnoresNeighborsOutsidePerception() {
        let f = Flocking.cohesion(center: CGPoint(x: 0, y: 0), neighbors: [neighbor(1000, 0)], perception: 100)
        XCTAssertEqual(f.dx, 0, accuracy: 0.0001)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testAlignmentPointsTowardMeanVelocity() {
        let f = Flocking.alignment(center: CGPoint(x: 0, y: 0), velocity: .zero,
                                   neighbors: [neighbor(10, 0, vx: 2), neighbor(0, 10, vx: 2)], perception: 500)
        XCTAssertGreaterThan(f.dx, 0)
        XCTAssertEqual(f.dy, 0, accuracy: 0.0001)
    }

    func testCursorSeekNilOutsideRadius() {
        XCTAssertNil(Flocking.cursorSeek(center: CGPoint(x: 0, y: 0), cursor: CGPoint(x: 300, y: 0), radius: 250))
    }

    func testCursorSeekUnitVectorTowardCursorInsideRadius() {
        let f = Flocking.cursorSeek(center: CGPoint(x: 0, y: 0), cursor: CGPoint(x: 100, y: 0), radius: 250)
        XCTAssertNotNil(f)
        XCTAssertEqual(f!.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(f!.dy, 0, accuracy: 0.0001)
    }

    func testNearestMeetTargetPicksClosestEngageable() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(40, 0, engageable: true), neighbor(20, 0, engageable: true)],
                                           meetDistance: 48)
        XCTAssertEqual(t?.x, 20)
    }

    func testNearestMeetTargetIgnoresNonEngageable() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(20, 0, engageable: false)], meetDistance: 48)
        XCTAssertNil(t)
    }

    func testNearestMeetTargetNilWhenOutOfRange() {
        let t = Flocking.nearestMeetTarget(center: CGPoint(x: 0, y: 0),
                                           neighbors: [neighbor(100, 0, engageable: true)], meetDistance: 48)
        XCTAssertNil(t)
    }

    func testSteerCapsToMaxSpeed() {
        let v = Flocking.steer(base: CGVector(dx: 10, dy: 0), forces: [], maxSpeed: 2)
        XCTAssertEqual((v.dx * v.dx + v.dy * v.dy).squareRoot(), 2, accuracy: 0.0001)
    }

    func testSteerAddsWeightedForces() {
        let v = Flocking.steer(base: CGVector(dx: 1, dy: 0), forces: [(CGVector(dx: 0, dy: 1), 2)], maxSpeed: 100)
        XCTAssertEqual(v.dx, 1, accuracy: 0.0001)
        XCTAssertEqual(v.dy, 2, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FlockingTests`
Expected: FAIL — `cannot find 'Flocking' in scope` / `cannot find type 'NeighborState' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Claudeer/Flocking.swift`:

```swift
import CoreGraphics

/// A snapshot of another mascot in global screen coordinates, used to compute
/// flocking forces. Pure data — no AppKit/UI dependency, so it is unit-testable.
struct NeighborState {
    let center: CGPoint
    let velocity: CGVector
    /// Idle and not paused/frozen/dragging/hidden/meeting — eligible to be greeted.
    let engageableForMeeting: Bool
}

/// Stateless steering-force math for the mascot flock. All vectors are in global
/// screen coordinates. Kept AppKit-free so it can be unit-tested directly.
enum Flocking {
    /// Steer away from neighbors closer than `minDistance`; strength grows as a
    /// neighbor gets closer. Returns a vector pointing away from the crowd.
    static func separation(center: CGPoint, neighbors: [NeighborState], minDistance: CGFloat) -> CGVector {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        for n in neighbors {
            let ox = center.x - n.center.x
            let oy = center.y - n.center.y
            let dist = (ox * ox + oy * oy).squareRoot()
            if dist > 0 && dist < minDistance {
                let falloff = (minDistance - dist) / minDistance
                dx += ox / dist * falloff
                dy += oy / dist * falloff
            }
        }
        return CGVector(dx: dx, dy: dy)
    }

    /// Steer toward the average position of neighbors within `perception`.
    /// Returns a unit vector (or zero when there are no neighbors in range).
    static func cohesion(center: CGPoint, neighbors: [NeighborState], perception: CGFloat) -> CGVector {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        for n in neighbors {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            if (dx * dx + dy * dy).squareRoot() < perception {
                sumX += n.center.x
                sumY += n.center.y
                count += 1
            }
        }
        guard count > 0 else { return .zero }
        return normalized(CGVector(dx: sumX / count - center.x, dy: sumY / count - center.y))
    }

    /// Steer toward the average velocity (heading) of neighbors within `perception`.
    /// Returns a unit vector (or zero when there are no neighbors in range).
    static func alignment(center: CGPoint, velocity: CGVector, neighbors: [NeighborState], perception: CGFloat) -> CGVector {
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var count: CGFloat = 0
        for n in neighbors {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            if (dx * dx + dy * dy).squareRoot() < perception {
                sumX += n.velocity.dx
                sumY += n.velocity.dy
                count += 1
            }
        }
        guard count > 0 else { return .zero }
        return normalized(CGVector(dx: sumX / count, dy: sumY / count))
    }

    /// Unit vector toward `cursor` when within `radius` of `center`; nil otherwise.
    static func cursorSeek(center: CGPoint, cursor: CGPoint, radius: CGFloat) -> CGVector? {
        let dx = cursor.x - center.x
        let dy = cursor.y - center.y
        let dist = (dx * dx + dy * dy).squareRoot()
        guard dist <= radius else { return nil }
        guard dist > 0 else { return .zero }
        return CGVector(dx: dx / dist, dy: dy / dist)
    }

    /// The center of the closest engageable neighbor within `meetDistance`, or nil.
    static func nearestMeetTarget(center: CGPoint, neighbors: [NeighborState], meetDistance: CGFloat) -> CGPoint? {
        var best: CGPoint?
        var bestDist = meetDistance
        for n in neighbors where n.engageableForMeeting {
            let dx = n.center.x - center.x
            let dy = n.center.y - center.y
            let dist = (dx * dx + dy * dy).squareRoot()
            if dist < bestDist {
                bestDist = dist
                best = n.center
            }
        }
        return best
    }

    /// Sum `base` with each weighted force, then clamp the result to `maxSpeed`.
    static func steer(base: CGVector, forces: [(CGVector, CGFloat)], maxSpeed: CGFloat) -> CGVector {
        var vx = base.dx
        var vy = base.dy
        for (f, w) in forces {
            vx += f.dx * w
            vy += f.dy * w
        }
        let mag = (vx * vx + vy * vy).squareRoot()
        if mag > maxSpeed && mag > 0 {
            vx = vx / mag * maxSpeed
            vy = vy / mag * maxSpeed
        }
        return CGVector(dx: vx, dy: vy)
    }

    /// A unit vector in the direction of `v`, or zero if `v` has zero magnitude.
    static func normalized(_ v: CGVector) -> CGVector {
        let mag = (v.dx * v.dx + v.dy * v.dy).squareRoot()
        guard mag > 0 else { return .zero }
        return CGVector(dx: v.dx / mag, dy: v.dy / mag)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FlockingTests`
Expected: PASS (all 13 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/Flocking.swift Tests/ClaudeerTests/FlockingTests.swift
git commit -m "feat: add pure flocking force math with tests"
```

---

### Task 3: Plumbing — controller state/API + manager wiring

Adds velocity, settings, a neighbor provider, and read-only snapshots to
`CharacterController`, and wires `MascotManager` to supply neighbors + push
settings. **No behavior change yet** — `tick()` still runs the legacy wander.

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift` (add properties near lines 5–18; add setters/accessors; reset velocity in `setMovement`/`setBeingDragged`/`setPaused`/`transitionTo`)
- Modify: `Sources/Claudeer/MascotManager.swift` (add `neighborStates`; wire provider + settings in `ensureMascot` lines 40–44 and `reloadAssets` lines 62–70)

**Interfaces:**
- Consumes: `FlockingSettings`, `CursorGatherSettings` (Task 1); `NeighborState` (Task 2).
- Produces (on `CharacterController`):
  - `var neighbors: () -> [NeighborState]` (settable; defaults to `{ [] }`)
  - `func setFlocking(_ settings: FlockingSettings)`, `func setCursorGather(_ settings: CursorGatherSettings)`
  - `var center: CGPoint`, `var currentVelocity: CGVector`, `var engageableForMeeting: Bool`
- Produces (on `MascotManager`): `func neighborStates(excluding id: String) -> [NeighborState]`

- [ ] **Step 1: Add controller state + settings**

In `Sources/Claudeer/CharacterController.swift`, add these stored properties inside the class, after `private var transitionWorkItem: DispatchWorkItem?` (line 18):

```swift
    private var velocity: CGVector = .zero
    private var flocking: FlockingSettings = .default
    private var cursorGather: CursorGatherSettings = .default
    private var isMeeting = false

    /// Supplies snapshots of the *other* eligible mascots. Defaults to none, so a
    /// solo controller behaves exactly as before. Injected by `MascotManager`.
    var neighbors: () -> [NeighborState] = { [] }
```

- [ ] **Step 2: Add settings setters + snapshot accessors**

In `Sources/Claudeer/CharacterController.swift`, add these methods right after `setSpeed(_:)` (line 39):

```swift
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
```

- [ ] **Step 3: Reset velocity/meeting on state changes**

In `Sources/Claudeer/CharacterController.swift`:

Replace `setMovement(_:)` (lines 30–35) with:

```swift
    func setMovement(_ settings: MovementSettings) {
        movements = settings
        if !movements.value(for: currentState) {
            isMoving = false
            velocity = .zero
        }
    }
```

Replace `setBeingDragged(_:)` (lines 41–48) with:

```swift
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
```

Replace `setPaused(_:)` (lines 50–55) with:

```swift
    func setPaused(_ paused: Bool) {
        isPaused = paused
        if paused {
            isMoving = false
            isMeeting = false
            velocity = .zero
        }
    }
```

In `transitionTo(_:)` (lines 177–189), add `isMeeting = false` and `velocity = .zero` right after the existing `isMoving = false` (line 181), so it reads:

```swift
        isMoving = false
        isMeeting = false
        velocity = .zero
        isFrozen = true
```

- [ ] **Step 4: Add `neighborStates` + wire the provider in `MascotManager`**

In `Sources/Claudeer/MascotManager.swift`, add this method inside the class (e.g. after `mascot(for:)` at line 56):

```swift
    /// Snapshots of every other mascot that is currently visible, for flocking.
    func neighborStates(excluding id: String) -> [NeighborState] {
        var result: [NeighborState] = []
        for (sid, mascot) in mascots where sid != id && !mascot.isHidden {
            result.append(NeighborState(
                center: mascot.characterController.center,
                velocity: mascot.characterController.currentVelocity,
                engageableForMeeting: mascot.characterController.engageableForMeeting
            ))
        }
        return result
    }
```

In `ensureMascot(sessionID:)`, after `mascot.characterController.setSpeed(...)` (line 42) and before `mascot.setLabelVisible(...)` (line 43), add:

```swift
        mascot.characterController.setFlocking(assetStore.config.flocking)
        mascot.characterController.setCursorGather(assetStore.config.cursorGather)
        mascot.characterController.neighbors = { [weak self, sessionID] in
            self?.neighborStates(excluding: sessionID) ?? []
        }
```

In `reloadAssets()`, after `mascot.characterController.setSpeed(...)` (line 67), add:

```swift
            mascot.characterController.setFlocking(assetStore.config.flocking)
            mascot.characterController.setCursorGather(assetStore.config.cursorGather)
```

- [ ] **Step 5: Build and run existing tests**

Run: `swift build`
Expected: Builds with no errors.

Run: `swift test`
Expected: PASS (all existing suites — no behavior changed).

- [ ] **Step 6: Smoke-test the app is unchanged**

Run: `.build/debug/Claudeer` and, in another terminal, spawn a session:

```bash
python3 -c "import socket,json; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock'); s.send(json.dumps({'state':'idle','session_id':'plumb','pid':99999,'cwd':'/tmp'}).encode()+b'\n'); print(s.recv(1024)); s.close()"
```

Expected: One mascot appears and wanders/rests as before (default config still runs the legacy path here because the steering engine is added in Task 4). Quit with the menu bar item.

- [ ] **Step 7: Commit**

```bash
git add Sources/Claudeer/CharacterController.swift Sources/Claudeer/MascotManager.swift
git commit -m "feat: plumb flocking settings + neighbor provider (no behavior change)"
```

---

### Task 4: Steering engine — wander + flock (mode: wander)

Introduces the velocity-based steering tick and the flock forces. `tick()` now
dispatches: legacy wander when both toggles are off; steering otherwise. With
`flocking` ON (the default), 2+ mascots loosely group and never overlap.

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift` (replace `tick()` lines 75–89; add `legacyWanderTick`, `steeringTick`, `handleWander`, `applySeparationNudge`, `advance`, tuning constants)

**Interfaces:**
- Consumes: `Flocking.*` (Task 2); `neighbors`, `flocking`, `velocity`, `center` (Task 3).
- Produces: private `handleWander(_:)`, `advance(by:clampToArea:)` used by Tasks 5–6.

- [ ] **Step 1: Add tuning constants**

In `Sources/Claudeer/CharacterController.swift`, add near the top of the class (after the `neighbors` property from Task 3):

```swift
    // Flock tuning (px unless noted). Refined during visual verification (Task 8).
    private static let perceptionRadius: CGFloat = 180
    private static let separationDistance: CGFloat = 50
    private static let separationWeight: CGFloat = 1.5
    private static let cohesionWeight: CGFloat = 0.6
    private static let alignmentWeight: CGFloat = 0.5
```

- [ ] **Step 2: Replace `tick()` and add the steering methods**

Replace `tick()` (lines 75–89) with:

```swift
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
        velocity = Flocking.steer(base: CGVector(dx: toTarget.dx * speed, dy: toTarget.dy * speed), forces: forces, maxSpeed: speed)
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
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 4: Run existing tests**

Run: `swift test`
Expected: PASS (nothing regressed; movement is not unit-tested — verified visually next).

- [ ] **Step 5: Visual check — loose flocking**

Run `.build/debug/Claudeer`, then spawn three mascots:

```bash
python3 - <<'PY'
import socket, json
for i in range(3):
    s = socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock')
    s.send(json.dumps({'state':'idle','session_id':f'flock{i}','pid':90000+i,'cwd':'/tmp'}).encode()+b'\n')
    s.recv(1024); s.close()
PY
sleep 6
screencapture -x /private/tmp/claude-501/-Users-jhseo-Programming-Side-Project-claudeer/71047a71-ec4a-4708-b225-487de5c956d1/scratchpad/flock.png
```

Expected: the three mascots drift toward a loose cluster and settle **near but not overlapping** each other (they don't stack on one spot). Inspect `flock.png`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Claudeer/CharacterController.swift
git commit -m "feat: velocity-based steering tick with flocking forces"
```

---

### Task 5: Cursor-seek mode

Mascots within `cursor_gather.radius` of the pointer steer toward it (still
separating), leaving their roaming area if needed; when the cursor leaves the
radius they fall back to wander and walk back into the band.

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift` (add `handleCursorSeek`; insert its dispatch line in `steeringTick`; add cursor constant)

**Interfaces:**
- Consumes: `Flocking.cursorSeek` (Task 2); `advance`, `handleWander` (Task 4); `cursorGather` (Task 3).

- [ ] **Step 1: Add the cursor-seek handler**

In `Sources/Claudeer/CharacterController.swift`, add near the other constants:

```swift
    private static let cursorSeekWeight: CGFloat = 1.0
```

Add this method next to `handleWander`:

```swift
    /// If cursor-gather is on and the cursor is within radius, steer toward it
    /// (still separating from neighbors) without clamping to the roaming area.
    /// Returns true when it handled this tick.
    private func handleCursorSeek(_ neighborList: [NeighborState]) -> Bool {
        guard cursorGather.enabled else { return false }
        let cursor = NSEvent.mouseLocation   // NSPoint == CGPoint, global screen coords
        guard let dir = Flocking.cursorSeek(center: center, cursor: cursor, radius: CGFloat(cursorGather.radius)) else {
            return false
        }
        // Reset wander so it resumes cleanly (and re-enters the band) once the
        // cursor leaves the radius.
        isMoving = false
        let sep = flocking.enabled
            ? Flocking.separation(center: center, neighbors: neighborList, minDistance: Self.separationDistance)
            : CGVector.zero
        velocity = Flocking.steer(
            base: CGVector(dx: dir.dx * speed * Self.cursorSeekWeight, dy: dir.dy * speed * Self.cursorSeekWeight),
            forces: [(sep, Self.separationWeight)],
            maxSpeed: speed
        )
        advance(by: velocity, clampToArea: false)
        return true
    }
```

- [ ] **Step 2: Dispatch to it in `steeringTick`**

Replace `steeringTick()` with:

```swift
    private func steeringTick() {
        let neighborList = neighbors()
        if handleCursorSeek(neighborList) { return }
        handleWander(neighborList)
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 4: Visual check — cursor gather**

Temporarily enable cursor-gather by editing the config file, then run:

```bash
python3 -c "import json,os; p=os.path.expanduser('~/Library/Application Support/Claudeer/config.json'); c=json.load(open(p)); c['cursor_gather']={'enabled':True,'radius':250}; json.dump(c,open(p,'w'))"
.build/debug/Claudeer &
sleep 1
python3 - <<'PY'
import socket, json
for i in range(3):
    s = socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock')
    s.send(json.dumps({'state':'idle','session_id':f'cur{i}','pid':91000+i,'cwd':'/tmp'}).encode()+b'\n')
    s.recv(1024); s.close()
PY
```

Move the mouse near the mascots. Expected: mascots within ~250 px come to the
cursor (leaving the bottom band if needed) and cluster around it without
overlapping; move the cursor far away and they wander back into the band.
Mascots outside the radius keep wandering.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/CharacterController.swift
git commit -m "feat: cursor-gather steering mode"
```

---

### Task 6: Meeting mode (face-and-pause greeting)

When two idle mascots come within `meetDistance`, both stop, face each other for
1–2 s, then part with a cooldown. No speech bubbles.

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift` (add meeting state + constants; add `handleMeeting`; insert its dispatch line in `steeringTick`)

**Interfaces:**
- Consumes: `Flocking.nearestMeetTarget` (Task 2); `isMeeting` (Task 3); `pickNewIdleDuration` (existing).

- [ ] **Step 1: Add meeting state + constants**

In `Sources/Claudeer/CharacterController.swift`, add stored properties near the other new state (`isMeeting` already exists from Task 3):

```swift
    private var meetTimer: TimeInterval = 0
    private var meetDuration: TimeInterval = 0
    private var meetCooldown: TimeInterval = 0
    private var meetTargetCenter: CGPoint?
```

Add constants near the others:

```swift
    private static let meetDistance: CGFloat = 48
    private static let meetDurationRange: ClosedRange<Double> = 1.0...2.0
    private static let meetCooldownDuration: TimeInterval = 6.0
```

- [ ] **Step 2: Add the meeting handler**

Add this method next to `handleWander`:

```swift
    /// Face-and-pause "greeting": when idle and a neighbor is within meetDistance
    /// (and off cooldown), stop and face them for meetDuration, then set cooldown.
    /// Returns true when it handled this tick.
    private func handleMeeting(_ neighborList: [NeighborState]) -> Bool {
        guard flocking.enabled else { return false }
        if meetCooldown > 0 { meetCooldown -= 1.0 / 30.0 }

        if isMeeting {
            meetTimer += 1.0 / 30.0
            if let t = meetTargetCenter, abs(t.x - center.x) > 0.01 {
                spriteEngine.setFacing(left: t.x < center.x)
            }
            velocity = .zero
            if meetTimer >= meetDuration {
                isMeeting = false
                meetTargetCenter = nil
                meetCooldown = Self.meetCooldownDuration
                pickNewIdleDuration()
            }
            return true
        }

        guard currentState == .idle, meetCooldown <= 0 else { return false }
        guard let targetCenter = Flocking.nearestMeetTarget(center: center, neighbors: neighborList, meetDistance: Self.meetDistance) else {
            return false
        }
        isMeeting = true
        meetTargetCenter = targetCenter
        meetTimer = 0
        meetDuration = Double.random(in: Self.meetDurationRange)
        velocity = .zero
        spriteEngine.setFacing(left: targetCenter.x < center.x)
        return true
    }
```

- [ ] **Step 3: Dispatch to it first in `steeringTick`**

Replace `steeringTick()` with:

```swift
    private func steeringTick() {
        let neighborList = neighbors()
        if handleMeeting(neighborList) { return }
        if handleCursorSeek(neighborList) { return }
        handleWander(neighborList)
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 5: Visual check — greeting**

Run `.build/debug/Claudeer` and spawn two mascots (default `flocking` ON pulls
them together):

```bash
python3 - <<'PY'
import socket, json
for i in range(2):
    s = socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock')
    s.send(json.dumps({'state':'idle','session_id':f'meet{i}','pid':92000+i,'cwd':'/tmp'}).encode()+b'\n')
    s.recv(1024); s.close()
PY
```

Expected: when the two drift together they occasionally **stop and face each
other for ~1–2 s**, then part and don't immediately re-trigger (6 s cooldown).

- [ ] **Step 6: Commit**

```bash
git add Sources/Claudeer/CharacterController.swift
git commit -m "feat: face-and-pause greeting when mascots meet"
```

---

### Task 7: Preferences — Movement toggles + radius slider

**Files:**
- Modify: `Sources/Claudeer/PreferencesView.swift` (extend `movementSection` at lines 76–106)

**Interfaces:**
- Consumes: `AssetStore.updateFlocking`, `AssetStore.updateCursorGather`, `CursorGatherSettings` (Task 1).

- [ ] **Step 1: Add the controls to `movementSection`**

In `Sources/Claudeer/PreferencesView.swift`, replace `movementSection` (lines 76–106) with:

```swift
    private var movementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement").font(.headline)
            ForEach(MascotState.allCases, id: \.self) { state in
                HStack {
                    Text(state.displayName)
                        .frame(width: 80, alignment: .leading)
                    Toggle("Move while \(state.rawValue)", isOn: Binding(
                        get: { assetStore.config.movements.value(for: state) },
                        set: { assetStore.updateMovement(for: state, to: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    Spacer()
                }
            }
            HStack {
                Text("Speed")
                    .frame(width: 80, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { assetStore.config.speed },
                        set: { assetStore.updateSpeed($0) }
                    ),
                    in: SpeakiConfig.speedRange,
                    minimumValueLabel: Text("Slow").font(.caption).foregroundColor(.secondary),
                    maximumValueLabel: Text("Fast").font(.caption).foregroundColor(.secondary),
                    label: { EmptyView() }
                )
            }

            Divider()

            Toggle("Flock together (gather, avoid overlap, greet when close)", isOn: Binding(
                get: { assetStore.config.flocking.enabled },
                set: { assetStore.updateFlocking($0) }
            ))
            .toggleStyle(.checkbox)

            Toggle("Gather to the mouse cursor", isOn: Binding(
                get: { assetStore.config.cursorGather.enabled },
                set: { assetStore.updateCursorGather(CursorGatherSettings(enabled: $0, radius: assetStore.config.cursorGather.radius)) }
            ))
            .toggleStyle(.checkbox)

            HStack {
                Text("Cursor range")
                    .frame(width: 80, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { assetStore.config.cursorGather.radius },
                        set: { assetStore.updateCursorGather(CursorGatherSettings(enabled: assetStore.config.cursorGather.enabled, radius: $0)) }
                    ),
                    in: CursorGatherSettings.radiusRange,
                    minimumValueLabel: Text("Near").font(.caption).foregroundColor(.secondary),
                    maximumValueLabel: Text("Far").font(.caption).foregroundColor(.secondary),
                    label: { EmptyView() }
                )
                .disabled(!assetStore.config.cursorGather.enabled)
            }
        }
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Builds with no errors.

- [ ] **Step 3: Manual check — live toggles (hot reload)**

Run `.build/debug/Claudeer`, spawn 2–3 mascots, open Preferences from the menu
bar, and toggle "Flock together" and "Gather to the mouse cursor" on/off.
Expected: behavior changes immediately (no restart) — flocking off + cursor off
returns them to independent wander; the cursor-range slider enables only when
"Gather to the mouse cursor" is on.

- [ ] **Step 4: Commit**

```bash
git add Sources/Claudeer/PreferencesView.swift
git commit -m "feat: Movement preferences for flocking and cursor-gather"
```

---

### Task 8: Full verification pass, tuning, docs, version bump

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift` (tune constants only, if needed)
- Modify: `CLAUDE.md` (document the new movement behaviors)
- Modify: `.claude-plugin/plugin.json` (version bump)
- Modify: `README.md` (mention flocking / cursor-gather under features/settings)

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: PASS (ConfigTests + FlockingTests + all existing suites).

- [ ] **Step 2: End-to-end visual verification**

Follow the app-verification workflow (spawn socket sessions, wait for the render
race, `screencapture -R` the roaming band). Confirm all acceptance criteria from
the spec:
- Both toggles off → wander/rest exactly as before.
- Flocking on, 3 mascots → loose cluster, no overlap, occasional face-to-face pauses.
- Cursor-gather on → nearby mascots come to the pointer (leaving the band) and return when it leaves; far mascots unaffected.
- `working`/dragged/hidden mascots excluded from flocking and greetings (mark one busy via a `state:"working"` event and confirm the others ignore it as a neighbor for greeting).

Tune the constants in `CharacterController` (`separationDistance`, weights,
`meetDistance`, `cursorSeekWeight`, etc.) if the motion looks too tight/loose or
jittery, then re-verify. Keep changes to constants only.

- [ ] **Step 3: Update docs**

- In `CLAUDE.md`, under **Key Conventions**, add a bullet describing the steering
  model: legacy wander when both toggles off; `Flocking.swift` pure force math;
  mode priority meeting → cursor-seek → wander+flock; neighbor snapshots injected
  by `MascotManager`; cursor read via `NSEvent.mouseLocation`; config keys
  `flocking` / `cursor_gather`, defaults ON/OFF; hot-reloaded via
  `setFlocking`/`setCursorGather`.
- In `README.md`, note the two new Movement settings.

- [ ] **Step 4: Bump plugin version**

In `.claude-plugin/plugin.json`, bump the version (e.g. `0.10.0` → `0.11.0`) per
the "bump version on functional changes" convention.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md .claude-plugin/plugin.json Sources/Claudeer/CharacterController.swift
git commit -m "docs: document flocking movement; bump plugin version"
```

---

## Self-Review

**Spec coverage:**
- Loose flock (separation/cohesion/alignment) → Tasks 2, 4. ✓
- Meeting face-and-pause, no bubbles → Task 6. ✓
- Cursor gather within radius, may leave band, returns after → Task 5. ✓
- Config `flocking`/`cursor_gather`, snake_case, backward-compat defaults → Task 1. ✓
- Defaults flocking ON / cursor OFF → Task 1 (`FlockingSettings.default`, `CursorGatherSettings.default`) + ConfigTests. ✓
- Both-off = today's behavior → Task 4 (`legacyWanderTick`). ✓
- Preferences Movement section + hot reload → Task 7 + Task 3 wiring in `reloadAssets`. ✓
- Exclude working/frozen/dragged/hidden from flocking & greeting → Task 3 (`engageableForMeeting`, `neighborStates` excludes hidden; `tick` guards paused/frozen/dragging) + Task 8 verification. ✓
- Pure testable seam → Task 2 (`Flocking`), Task 1 (config round-trip). ✓
- Coordinate space (centers, global, `NSEvent.mouseLocation`) → Task 5 + Global Constraints. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code; commands have expected output. ✓

**Type consistency:** `NeighborState` fields (`center`, `velocity`, `engageableForMeeting`) match across Tasks 2–4; `Flocking` method signatures match their call sites in Tasks 4–6; `setFlocking`/`setCursorGather`/`neighbors`/`center`/`currentVelocity`/`engageableForMeeting` defined in Task 3 and used in Tasks 4–6; `updateFlocking`/`updateCursorGather`/`CursorGatherSettings` defined in Task 1 and used in Task 7. ✓
