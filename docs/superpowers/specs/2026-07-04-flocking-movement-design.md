# Flocking Movement Design

**Date:** 2026-07-04
**Status:** Draft for review

## Goal

Make the per-session mascots feel like little social NPCs: they loosely gather
into a group, occasionally stop to "greet" each other, and — optionally — the
ones near the mouse cursor come over to it. The point is *charm*, not a rigorous
physics simulation; flocking is just the mechanism.

Two independent, config-gated behaviors:

1. **Flocking** — mascots loosely group (separation + cohesion + alignment) and,
   when two get close, briefly face each other and pause (a wordless "greeting").
2. **Cursor gather** — mascots within a radius of the mouse cursor are drawn to
   it (and may leave their roaming area to reach it); far ones are unaffected.

Flocking only produces visible behavior with 2+ mascots (2+ live Claude Code
sessions). With one mascot, or with both toggles off, movement is identical to
today's random wander.

## Non-goals (v1)

- No speech bubbles / text during greetings (movement + facing only).
- No new sprite assets or emotes — reuse existing state sprites, facing (mirror),
  and the stop-and-go rhythm.
- No change to the idle/working state machine, sounds, notifications, or the
  interaction (drag/click) system beyond reading the cursor position.
- Cohesion is deliberately weak: mascots must stay visually distinct (they
  represent different sessions), so they never collapse onto one point.

## Movement model

Today `CharacterController` is **target-based**: pick a random point in the
roaming area, walk straight toward it at `speed`, rest 2–6 s, repeat; facing is
set by the sign of `dx`.

We keep that target-based wander as the **core** and add steering forces *on top*
only when a behavior is enabled. This guarantees "both toggles off = today's code
path, zero regression," while still producing good group motion when on.

Each tick (30 fps), when the mascot is allowed to move (not paused / frozen /
dragging, and `movements.value(for: currentState)` is true), pick exactly one
**mode** by priority:

1. **Meeting** (only if flocking on) — a neighbor's center is within
   `meetDistance`, both mascots are idle, and neither is on greeting cooldown.
   Action: set velocity to 0, face toward that neighbor, hold for `meetDuration`
   (random 1.0–2.0 s), then set a `meetCooldown` (~6 s) and resume. Skips all
   other forces while meeting. Because each controller independently notices the
   other and faces it, the two naturally end up face-to-face — no central
   coordination needed.

2. **Cursor-seek** (only if cursor-gather on) — the cursor
   (`NSEvent.mouseLocation`) is within `cursorRadius` of the mascot's center.
   Action: steer toward the cursor, **plus separation** from neighbors (so a
   group clusters around the pointer instead of stacking on one pixel).
   Area clamping is **skipped** in this mode so the mascot may leave its band to
   reach the cursor. Rest is suppressed. When the cursor leaves the radius, the
   mascot falls back to wander; its next wander target is inside the roaming
   area, so it walks back into the band on its own.

3. **Wander** (default; adds flock forces if flocking on) — the existing
   pick-target / seek / rest-2–6 s behavior. If flocking is on, blend the
   separation + cohesion + alignment vector into the step direction so the group
   loosely coheres while each mascot still meanders to its own target. Clamp to
   the roaming area. **Separation applies even while resting** so a moving mascot
   that wanders into a resting one nudges it apart instead of overlapping.

Facing is set from the sign of the net horizontal movement each tick (unchanged
semantics: face left when moving left).

### Forces (the three flocking rules + cursor)

Computed from **neighbor snapshots** (other eligible mascots' centers and
velocities), all in global screen coordinates:

- **Separation** — steer away from neighbors closer than `separationDistance`;
  contribution scales up as they get closer. Prevents overlap.
- **Cohesion** — steer gently toward the average position of neighbors within
  `perceptionRadius`. Weak weight (loose grouping only).
- **Alignment** — steer gently toward the average velocity of neighbors within
  `perceptionRadius`. Weak weight (shared drift).
- **Cursor-seek** — steer toward the cursor when within `cursorRadius`; zero
  otherwise.

Only mascots that are visible and movement-enabled count as neighbors. A
`working`/frozen/dragged/hidden/paused mascot is excluded from others' neighbor
sets and does not itself apply forces.

## Configuration

Add two settings to `SpeakiConfig` (`Config.swift`), following the existing
`decodeIfPresent ?? default` pattern for backward compatibility with older
config files:

```swift
struct FlockingSettings: Codable {
    let enabled: Bool
    static let `default` = FlockingSettings(enabled: true)   // headline, on by default
}

struct CursorGatherSettings: Codable {
    let enabled: Bool
    let radius: Double
    static let `default` = CursorGatherSettings(enabled: false, radius: 250) // opt-in
}
```

- New JSON keys: `flocking`, `cursor_gather` (snake_case, matching existing keys).
- **Defaults:** flocking **ON** (subtle, safe — falls back to wander when alone),
  cursor-gather **OFF** (more dramatic; opt-in). *Flagged for confirmation — easy
  to flip.*
- Add a **"Movement"** section to `PreferencesView` alongside the existing speed /
  per-state movement controls: a "Flocking" toggle and a "Follow cursor" toggle
  (+ a radius slider, mirroring the existing speed slider). Reuse existing toggle
  and slider patterns.
- **Hot reload:** `AssetStore.onAssetsChanged` → `MascotManager.reloadAssets`
  pushes the new settings to every `CharacterController` (new
  `setFlocking(_:)` / `setCursorGather(_:)`, mirroring `setMovement` / `setSpeed`).

## Architecture

Least-invasive approach: keep the per-mascot `CharacterController` + its own
30 fps timer. Give each controller (a) a neighbor source and (b) the cursor, then
add the force math.

### New: `Flocking.swift` — pure, testable force math

Free functions / small structs with **no AppKit UI dependency** (matches the
project's pure-seam convention, e.g. `isLiveClaude`, `notificationTitle`):

```swift
struct NeighborState {
    let center: CGPoint
    let velocity: CGVector
    let engageableForMeeting: Bool   // idle & not paused/frozen/dragging/hidden
}

func separation(center: CGPoint, neighbors: [NeighborState], minDistance: CGFloat) -> CGVector
func cohesion(center: CGPoint, neighbors: [NeighborState], perception: CGFloat) -> CGVector
func alignment(velocity: CGVector, neighbors: [NeighborState], perception: CGFloat) -> CGVector
func cursorSeek(center: CGPoint, cursor: CGPoint, radius: CGFloat) -> CGVector?  // nil if outside
func nearestMeetTarget(center: CGPoint, neighbors: [NeighborState], meetDistance: CGFloat) -> CGPoint?
```

These are unit-tested directly (no window/timer needed).

### `CharacterController` changes

- Add `velocity: CGVector`, greeting state (`isMeeting`, `meetTimer`,
  `meetCooldownRemaining`), and settings (`flocking`, `cursorGather`).
- Expose a snapshot for the manager: `center`, `velocity`, `engageableForMeeting`.
- Inject a neighbor provider: `var neighbors: () -> [NeighborState]` (defaults to
  `{ [] }` so a solo controller behaves exactly as today).
- Read the cursor via `NSEvent.mouseLocation` inside `tick()` only when
  cursor-gather is on (no new polling infrastructure).
- Rework `tick()` into the mode-priority logic above. Existing guards
  (`isPaused` / `isFrozen` / `isDragging` / `movements` gating), `transitionTo`,
  `setAreas`, `setSpeed`, `clampToAreas`, and `randomPointInAreas` are retained.
- Keep `speed` as the max step magnitude (velocity is capped to it).

### `MascotManager` changes

- `func neighborStates(excluding id: String) -> [NeighborState]` — snapshot every
  other mascot that is not hidden/paused, built from its controller's exposed
  center/velocity/engageable flag.
- In `ensureMascot`, wire the provider:
  `mascot.characterController.neighbors = { [weak self, id] in self?.neighborStates(excluding: id) ?? [] }`
  (weak capture — no retain cycle).
- In `ensureMascot` + `reloadAssets`, call `setFlocking` / `setCursorGather` with
  `assetStore.config` values, next to the existing `setMovement` / `setSpeed`.

### Coordinate space

`spriteEngine.position` (sprite origin) and `NSEvent.mouseLocation` are both
AppKit global screen coordinates (y-up, primary-screen-relative), so they compose
directly. Distances are measured between **centers** (`position + size/2`). Verify
during implementation by logging cursor vs. sprite centers.

## Tuning parameters (starting points, refined during visual verification)

| Parameter | Start value |
|---|---|
| `perceptionRadius` | 180 px |
| `separationDistance` | 50 px |
| separation weight | 1.5 |
| cohesion weight | 0.6 |
| alignment weight | 0.5 |
| wander weight | 1.0 |
| `meetDistance` | 48 px |
| `meetDuration` | 1.0–2.0 s |
| `meetCooldown` | 6 s |
| `cursorRadius` (default) | 250 px |
| cursor-seek weight | 2.0 |
| max step | `config.speed` (0.5–6 px/frame) |

## Testing

- **Unit (`FlockingTests`)**: separation pushes away from a close neighbor;
  cohesion points toward the group centroid; alignment points toward mean
  velocity; `cursorSeek` returns nil outside the radius and a toward-cursor vector
  inside; `nearestMeetTarget` picks the closest in-range engageable neighbor and
  returns nil when none qualify.
- **Config**: `flocking` / `cursor_gather` round-trip encode/decode; a config
  file missing both keys decodes to the documented defaults.
- **Visual (manual, per the app-verification workflow)**: launch, spawn 3+
  sessions via the socket, screenshot. Confirm: loose grouping without overlap;
  occasional face-to-face pauses; with cursor-gather on, nearby mascots come to
  the pointer and drift back when it leaves; with both off, behavior matches
  today.

## Acceptance criteria

- Both toggles off → mascots roam their area with stop-and-go pauses exactly as
  before (no visible change).
- Flocking on, 3 mascots → they loosely cluster, never overlap, and occasionally
  stop and face each other for ~1–2 s, then part.
- Cursor-gather on → mascots within the radius move to the cursor (leaving the
  band if needed) and return to the band after the cursor leaves; mascots outside
  the radius keep doing their own thing.
- Settings toggle live via Preferences (hot reload), no app restart.
- `working` / frozen / dragged / hidden mascots are excluded from flocking and
  greetings.
- Old config files (without the new keys) load without error and get the defaults.

## Future (out of scope for v1)

- Greeting speech bubbles / emotes (the earlier idea, deferred).
- Per-behavior weight sliders in Preferences (v1 uses fixed tuned constants).
- Richer interactions (hearts, hops) requiring new sprite assets.
