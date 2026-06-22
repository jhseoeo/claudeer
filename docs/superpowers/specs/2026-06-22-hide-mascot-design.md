# Per-Session Mascot Hide/Show — Design

**Date:** 2026-06-22
**Status:** Approved
**Goal:** Let the user hide an individual session's mascot from the screen — via a right-click context menu on the mascot, or a per-row eye toggle in the menu bar sessions list — and bring it back later.

---

## Motivation

Claudeer renders one mascot per active Claude Code session. With several sessions running, a user may want to dismiss a specific character (e.g. a noisy or distracting one) without quitting the app or losing the others. Today the only visibility control is the global auto-hide in `main.swift` (hide all overlay windows when there are zero sessions); there is no way to hide a single mascot.

## Scope

**In scope:**
- Hide a single session's mascot via **right-click → "Hide this character"**.
- Restore via a **per-row eye toggle** in the menu bar sessions list (`MenuBarPopoverView`).
- Sticky hide: a hidden session stays hidden across its own state-change events until explicitly shown.
- Hidden mascots are excluded from cursor hit-testing (not draggable/clickable) and suppress their speech bubble.

**Out of scope:**
- Global "hide all mascots" toggle (the empty-sessions auto-hide already covers the all-gone case; per-session is what was requested).
- Persisting hidden state across app restart — hidden state is **in-memory only** (sessions are re-discovered from hook events after a restart). Can be revisited if desired.
- Additional right-click menu items (Preferences/Quit) — the menu has the single Hide item for now; trivially extensible later.
- Suppressing per-state **sounds** for a hidden session (sound is global, driven by `EventManager`/`SoundPlayer`, not per-mascot).

---

## State Ownership — `SessionTracker`

The menu bar already observes `SessionTracker` as an `@ObservedObject`, so hidden state lives there to get reactive UI for free:

```swift
@Published private(set) var hiddenSessionIDs: Set<String> = []

func hide(_ id: String)          // insert
func show(_ id: String)          // remove
func toggleHidden(_ id: String)  // toggle membership
func isHidden(_ id: String) -> Bool
```

- `record(_:)` (incoming events) does **not** touch `hiddenSessionIDs` — this is what makes hide sticky across idle↔working transitions.
- `pruneDeadProcesses(...)` removes any pruned session id from `hiddenSessionIDs` as well, so the set doesn't leak entries for dead sessions.

Session ids are stable UUIDs per Claude session, so there is no id-reuse risk.

## Behavior

| Action | Result |
|--------|--------|
| Right-click a visible mascot → "Hide this character" | That session's mascot disappears; others unaffected. |
| Menu bar: click eye on a visible session row | Same as above (row dims, icon → `eye.slash`). |
| Menu bar: click eye on a hidden (dimmed) session row | Mascot reappears at its preserved position; icon → `eye`. |
| Hidden session sends a new idle/working event | Stays hidden; no speech bubble. |
| Hidden session's process dies (prune) | Row removed from menu bar; id dropped from `hiddenSessionIDs`. |
| New session appears | Not in the hidden set → shows normally. |
| App restart | Hidden state resets; all current sessions show. |

A hidden mascot's overlay windows are unaffected (they remain ordered-front, transparent, click-through). If every session is hidden while sessions is non-empty, the screen simply shows no mascots — consistent and harmless.

---

## Code Touch-Points

### 1. `Mascot`
- Add `private(set) var isHidden = false` and `func setHidden(_ hidden: Bool)`:
  - Toggles `spriteEngine.view.isHidden` and `nameLabel.isHidden` (respecting the existing label-visibility rule when showing).
  - Dismisses the speech bubble when hiding.
  - Pauses movement while hidden by stopping the character controller's timer, and resumes on show — reusing `characterController.stop()` / `start()` so an invisible mascot doesn't roam. Sprite position is preserved (no teardown/recreate). *Implementation note: verify `start()` is safe to call after `stop()` without resetting position or double-scheduling.*
- `applyTransition(to:speech:)` early-returns before showing the speech bubble when `isHidden` (still updates internal `state`/sprite state so it's correct when shown again).

### 2. `MascotManager`
- `func setHidden(_ ids: Set<String>)` — for each owned mascot, call `mascot.setHidden(ids.contains(mascot.sessionID))`.
- No change to `ensureMascot` (a brand-new session is never in the hidden set).

### 3. Right-click context menu
- `InteractionViewDelegate`: add `func interactionRightMouseDown(at:in:)`.
- `InteractionView`: override `rightMouseDown(with:)` → forward to delegate (mirrors existing `mouseDown`).
- `InteractionController`:
  - `interactionRightMouseDown` locates the mascot under the cursor (same global-point lookup as `interactionMouseDown`) and pops up an `NSMenu` with one item, "Hide this character", whose action invokes a new `onMascotHideRequested: ((Mascot) -> Void)?` callback (mirrors the existing `onMascotDoubleClicked`).
  - **Hit-test exclusion:** `updateCursorHover` and `interactionMouseDown` skip hidden mascots (`mascotManager.allMascots.first { !$0.isHidden && $0.globalFrame.contains(...) }`), so a hidden mascot is neither hoverable nor draggable.

### 4. Menu bar sessions list — `MenuBarPopoverView` / `SessionRow`
- `SessionRow` gains `isHidden: Bool` and an `onToggleHidden: () -> Void`; renders a trailing `eye` / `eye.slash` button and dims the row (reduced opacity / secondary color) when hidden.
- The enclosing list reads `sessionTracker.isHidden(session.id)` and calls `sessionTracker.toggleHidden(session.id)`. Because `hiddenSessionIDs` is `@Published`, the popover re-renders on toggle.

### 5. Wiring — `main.swift`
- After the existing `sessionTracker.$sessions` subscription, add a `sessionTracker.$hiddenSessionIDs` subscription that calls `mascotManager.setHidden(ids)` on the main thread.
- Set `interactionController.onMascotHideRequested = { mascot in sessionTracker.hide(mascot.sessionID) }`.

---

## Data Flow

```
Right-click "Hide this character"      Menu bar eye toggle
        │                                      │
        ▼                                      ▼
InteractionController.onMascotHideRequested   SessionTracker.toggleHidden(id)
        │                                      │
        └──────────► SessionTracker.hide(id) ◄─┘
                          │  (@Published hiddenSessionIDs changes)
            ┌─────────────┴─────────────┐
            ▼                           ▼
  main.swift subscription      MenuBarPopoverView re-renders
            │                  (row dims, icon flips)
            ▼
  MascotManager.setHidden(ids)
            ▼
  Mascot.setHidden(true/false)  → view.isHidden, label, bubble, movement timer
```

## Testing

- **`SessionTracker`** (unit): `hide`/`show`/`toggleHidden`/`isHidden` mutate the set correctly; `record` leaves `hiddenSessionIDs` untouched (sticky); `pruneDeadProcesses` drops pruned ids from `hiddenSessionIDs`.
- **`MascotManager.setHidden`** (unit, if feasible without a live window): maps ids → per-mascot `isHidden`.
- **Manual** (per the verification memory — socket-spawn sessions, `screencapture`):
  1. Spawn two sessions → two mascots visible.
  2. Right-click one → "Hide this character" → only that one disappears; the other roams.
  3. Hidden mascot is not draggable where it used to be.
  4. Menu bar: hidden row is dimmed with `eye.slash`; click it → mascot reappears at its old spot.
  5. Send a state event to the hidden session → stays hidden, no speech bubble.

---

## Risks / Notes

- `characterController.start()` after `stop()` must not reset position or schedule a duplicate timer — verify during implementation; if unsafe, fall back to gating `tick()` on an `isHidden` flag instead of stopping the timer.
- Keep `SpriteEngine.spriteExtensions` / `SoundPlayer` untouched — this feature adds no new asset slots.
- No `config.json` schema change (hidden state is not persisted), so no `Config.swift` migration needed.
