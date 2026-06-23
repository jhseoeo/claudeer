# Rename a Mascot's Session Label — Design

**Date:** 2026-06-23
**Status:** Approved
**Goal:** Let the user give an individual session's mascot a custom label via **right-click → "Rename…"**, overriding the auto-derived name (session title / folder), and revert to the auto name by clearing the field.

---

## Motivation

Each mascot shows a session name pill derived by `notify.py` (live transcript title → SessionStart title → cwd basename → short id) and sent on every hook event. With several sessions running, the auto names can be ambiguous (e.g. two sessions in sibling folders) or just unhelpful. The user wants to label a character themselves — "Frontend", "the flaky-test hunt" — so it's identifiable at a glance.

## Scope

**In scope:**
- Rename a single session's mascot via **right-click → "Rename…"** (sits above the existing "Hide this character").
- A native dialog (`NSAlert` + text field) pre-filled with the current label.
- Custom name takes precedence over incoming hook events (a later event does **not** clobber it).
- **Clearing the field reverts** to the auto name immediately (no waiting for the next event).
- The custom name is reflected wherever the session is named: the mascot pill, the menu bar sessions row, and the ntfy push title.

**Out of scope:**
- Persisting custom names across app restart — **in-memory only**, matching the existing per-session hide state (`hiddenSessionIDs`). Sessions are re-discovered from hook events after a restart.
- A rename affordance in the menu bar popover (right-click on the mascot is the only entry point; the popover only *reflects* the name).
- Inline editing of the pill in place.
- No `config.json` schema change, so no `Config.swift` migration.

---

## The Core Problem

`EventManager.handleEvent` calls `mascot.setName(event.name)` on **every** event. So a custom name must be stored and given precedence, or the next idle/working event overwrites it. Separately, to make "revert" instant, the last auto name must be remembered — otherwise clearing the custom name would leave the old text on screen until the next event happens to fire (which may be a long time for an idle session).

Solution: `SessionTracker` owns both the custom name and the last auto name, and exposes a single resolved `displayName(for:)`.

## State Ownership — `SessionTracker`

The menu bar already observes `SessionTracker` as an `@ObservedObject`, so custom names live there for reactive UI (mirrors how `hiddenSessionIDs` is handled):

```swift
@Published private(set) var customNames: [String: String] = [:]

func setCustomName(_ name: String?, for id: String)   // trim; empty/nil → remove (revert)
func customName(for id: String) -> String?
func displayName(for id: String) -> String?           // customNames[id] ?? sessionMap[id]?.name
```

- `SessionInfo` gains `var name: String?`, the last auto name. `record(_:)` sets `info.name = event.name` when the event carries one (keeps the last non-nil, so an event that omits the name doesn't blank it).
- `record(_:)` does **not** touch `customNames` — this is what makes a custom name sticky across idle↔working transitions.
- `pruneDeadProcesses(...)` removes pruned ids from `customNames` too (mirrors the existing `hiddenSessionIDs` cleanup), so the dict doesn't leak entries for dead sessions.

Session ids are stable UUIDs per Claude session, so there is no id-reuse risk.

## Behavior

| Action | Result |
|--------|--------|
| Right-click a mascot → "Rename…" | Dialog opens, pre-filled with the current label. |
| Type a name → OK | Mascot pill, menu bar row, and future ntfy titles use the custom name. |
| Clear the field → OK | Reverts to the auto name immediately. |
| Cancel | No change. |
| Renamed session sends a new idle/working event | Custom name persists (event name ignored while a custom name is set). |
| Renamed session's process dies (prune) | Row removed; id dropped from `customNames`. |
| App restart | Custom names reset; auto names return as events arrive. |

---

## Code Touch-Points

### 1. `SessionTracker`
- `SessionInfo` gains `var name: String?`.
- `record(_:)`: `if let name = event.name { info.name = name }`.
- Add `customNames` (`@Published`), `setCustomName(_:for:)`, `customName(for:)`, `displayName(for:)` as above.
- `pruneDeadProcesses`: in the existing pruned-ids loop, also `customNames.removeValue(forKey: info.id)`.

### 2. `EventManager`
- `handleEvent`: change `mascot.setName(event.name)` → `mascot.setName(sessionTracker.displayName(for: event.sessionId))` (called after `record`, so `SessionInfo.name` is fresh).
- `notificationTitle(for:)`: prefer the custom name — `sessionTracker.customName(for: event.sessionId) ?? event.name?.trimmed... ?? shortId`.

### 3. `Mascot`
- Add `var currentName: String { displayName }` so the dialog can pre-fill the visible label. (`displayName` already holds the short-id fallback when nothing else is set.)

### 4. Right-click context menu — `InteractionController`
- Add `var onMascotRenameRequested: ((Mascot) -> Void)?` (mirrors `onMascotHideRequested`).
- In `interactionRightMouseDown`, add a **"Rename…"** item *before* "Hide this character" (optionally a separator between). Its `@objc` action invokes `onMascotRenameRequested?(rightClickedMascot)`.
- No change to the hidden-mascot hit-test exclusion already in place.

### 5. Wiring — `main.swift`
- Set `interactionController.onMascotRenameRequested = { mascot in ... }`:
  - Build an `NSAlert` (informational) titled e.g. "Rename character" with OK / Cancel.
  - Accessory `NSTextField` (~220pt wide), `stringValue = mascot.currentName`, placeholder "Leave empty for the automatic name".
  - Make the alert key and the field first responder so the user can type immediately.
  - On OK: `sessionTracker.setCustomName(field.stringValue, for: mascot.sessionID)` then `mascot.setName(sessionTracker.displayName(for: mascot.sessionID))`.

### 6. Menu bar sessions list — `SessionRow`
- Pass `customName: sessionTracker.customName(for: session.id)` into the row (the enclosing `sessionsSection` has the tracker).
- `SessionRow.label`: `customName ?? <existing cwd-basename / short-id logic>`. Because `customNames` is `@Published`, the popover re-renders on rename.

---

## Data Flow

```
Right-click "Rename…"
        │
        ▼
InteractionController.onMascotRenameRequested(mascot)
        │
        ▼  (main.swift presents NSAlert)
SessionTracker.setCustomName(text, for: id)
        │  (@Published customNames changes)
        ├───────────────► mascot.setName(displayName(for: id))   // pill updates now
        └───────────────► MenuBarPopoverView re-renders          // row label updates

Later hook event ──► EventManager.handleEvent
                          │  record() refreshes SessionInfo.name
                          ▼
                     mascot.setName(displayName(for: id))  // customName wins; pill unchanged
```

## Testing

- **`SessionTrackerTests`** (unit, pure logic):
  - `setCustomName` sets and overrides; empty/whitespace input clears the entry (revert).
  - `displayName(for:)`: custom over auto; auto when no custom; `nil` when neither.
  - `record` stores `event.name` into `SessionInfo.name`; an event without a name keeps the previous one.
  - `pruneDeadProcesses` drops pruned ids from `customNames`.
- **`EventManagerTests`**: a recorded custom name survives a subsequent event (mascot name resolution prefers it); `notificationTitle` uses the custom name when set. (Use the existing test seams; expose `notificationTitle` for test if needed, or assert via the injected ntfy transport already used in `NtfyNotifierTests`.)
- **Manual** (per the verification memory — socket-spawn sessions, `screencapture`):
  1. Spawn a session → mascot shows the auto name.
  2. Right-click → "Rename…" → type "Frontend" → OK → pill reads "Frontend"; menu bar row reads "Frontend".
  3. Trigger an idle→working transition → name stays "Frontend".
  4. Right-click → "Rename…" → clear → OK → pill reverts to the auto name.

---

## Risks / Notes

- The dialog is modal (`runModal`); the 30 Hz cursor-hover polling and mascot animation timers keep running on the main run loop during a modal alert, which is fine (no interaction is expected mid-dialog).
- Keep `SpriteEngine.spriteExtensions` / `SoundPlayer` untouched — no new asset slots.
- `displayName(for:)` must be called **after** `record(_:)` in `handleEvent` so the freshly-stored auto name is available for sessions that have no custom name.
