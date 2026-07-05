# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Claudeer** is a macOS desktop mascot app + Claude Code plugin. A user-customized sprite character roams the screen and tracks two states — `idle` (waiting for user input) and `working` (Claude is processing) — with animations, speech bubbles, and sounds firing at each transition.

## Build & Test

```bash
swift build                     # Debug build
swift build -c release          # Release build
swift test                      # Run all tests (requires Xcode, not just CLT)
swift test --filter ConfigTests # Run a single test suite
.build/debug/Claudeer       # Run debug build
```

Manual socket test (while app is running):
```bash
python3 -c "import socket,json; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock'); s.send(json.dumps({'state':'working','session_id':'test'}).encode()+b'\n'); print(s.recv(1024)); s.close()"
```

Test as Claude Code plugin:
```bash
claude plugin add /path/to/claudeer
```

## Architecture

The app acts as its own daemon — no separate server process.

```
Claude Code Hooks (Python) ──(Unix Socket)──> Swift App
    notify.py                                    │
    SessionStart / UserPromptSubmit /       EventServer (POSIX socket on /tmp/claudeer.sock)
    Stop / Notification                          │
                                           EventManager (tracks currentState; fires only on change)
                                            │    │    │ ─── owns SessionTracker (per-session info)
                              CharacterController │  SoundPlayer       │
                                    │         SpeechBubbleView         └── observed by MenuBar popover

                              SpriteEngine (idle/working + interaction sprite override)
                                    │
                              MascotWindow (transparent NSWindow, click-through except over sprite)
                                    ▲
                                    │
                              InteractionController (cursor polling, drag/click state machine)
                              InteractionView (NSView; forwards mouseDown/Dragged/Up to controller)

AssetStore (~/Library/Application Support/Claudeer/)
  ├── feeds: SpriteEngine.loadSprites(...) / SoundPlayer.loadSounds(...) / EventManager.config / CharacterController.setMovement+setSpeed
  └── edited via: PreferencesWindow → PreferencesView (SwiftUI)
```

**Startup wiring** (`main.swift`): AssetStore → MascotWindow → SpriteEngine → SpeechBubble → SoundPlayer → CharacterController → EventManager → EventServer → MenuBarController (with assetStore reference). Order matters. AssetStore is built first because it owns the App Support directory and config.

**Hot reload**: `AssetStore.onAssetsChanged` is set in `main.swift` to call `SpriteEngine.loadSprites`, `SoundPlayer.loadSounds`, update `EventManager.config`, and re-apply `CharacterController.setMovement` + `setSpeed` whenever the user registers/clears/edits via Preferences. No app restart needed.

**Thread model**: EventServer accept loop runs on a background GCD queue. All events are dispatched to main thread via `DispatchQueue.main.async` before touching UI. `serverFD` and `running` are protected by NSLock.

**Hook flow**: Claude Code fires hook → `notify.py` reads stdin JSON, sends `{state, session_id, pid, cwd?, name?}` to Unix socket, prints `{"continue": true}`. Fails silently if app isn't running. Hook → state mapping: `SessionStart`/`Stop`/`Notification`→`idle`, `UserPromptSubmit`/`PreToolUse`/`PostToolUse`→`working` (the tool hooks use `"matcher": ""` = all tools). `Notification`→`idle` is intentional — Claude is blocked waiting for the user (e.g. a permission prompt). Since there is no dedicated "work resumed" hook, `PreToolUse`/`PostToolUse`→`working` is what flips the mascot back to `working` when the tool runs after the user responds, and keeps `working` asserted across long tool sequences. `pid` is `os.getppid()` (the Claude Code process — verified: the command hook is exec'd, so getppid is the long-lived `claude`, not a transient shell) and is sent on every event so SessionTracker can keep info fresh and prune dead processes. `cwd` is from the hook input JSON. EventManager dedupes — sound + bubble only fire when state actually changes.

**Sessions tracking**: `SessionTracker` (in `EventManager.sessionTracker`) is a small ObservableObject that records per-session `SessionInfo { id, pid, cwd, name, state, lastSeen }` on every incoming event (`name` is the last auto name from the hook). Sorted by `lastSeen` desc and exposed as `@Published var sessions` for the menu bar popover. **One Claude process hosts one session at a time** (a `/clear` or resume starts a new session_id on the same pid), so `record` evicts any prior session sharing the incoming event's pid and returns the evicted `SessionInfo`s — `EventManager.handleEvent` drops their now-orphaned mascots. Without this, pid-liveness never reaps the old session (its pid stays alive under the new one) → ghost mascots. `pruneDeadProcesses` runs every 10s and removes sessions whose pid is no longer a *live Claude process*: `SessionTracker.isLiveClaudeProcess` requires `kill(pid, 0) == 0` **and** the pid's `proc_pidpath` to contain "claude" (guards pid reuse by an unrelated process). The pure `isLiveClaude(alive:identity:)` is the testable seam; an unreadable path is treated as still-Claude so a session is never reaped on uncertainty. If the global state was `working` and no session remains in `working` after a prune, EventManager forces an `idle` transition (so the mascot doesn't get stuck working when Claude Code crashes).

**Label rename**: right-click a mascot → "Rename…" (above "Hide this character") opens an `NSAlert` to set a custom label. `SessionTracker.customNames` (in-memory, `@Published`, mirrors `hiddenSessionIDs` — cleared on prune) holds the override; `displayName(for:)` resolves `customName ?? SessionInfo.name`, so a custom name wins over later hook events. Clearing the field reverts to the auto name. `EventManager.handleEvent` and the ntfy title both resolve names through `SessionTracker`, and the menu bar `SessionRow` prefers the custom name. `EventManager.notificationTitle(customName:eventName:sessionId:)` is the pure, testable resolver.

**Mascot visibility**: `main.swift` subscribes to `sessionTracker.$sessions`. The window is `orderOut(nil)` when sessions is empty, `orderFront(nil)` when at least one session exists. App start with no sessions = no mascot visible (only the menu bar icon). Implication: if the mascot app launches AFTER an existing Claude Code session, that session is invisible to the tracker until the next hook event fires (since SessionStart already happened).

## Key Conventions

- **Pure stdlib** on both sides — no external Swift packages, no Python pip dependencies
- SwiftUI is used for two surfaces: the menu bar popover (`MenuBarController`) and the Preferences window (`PreferencesView`). Everything else (overlay, sprite, speech bubble) is AppKit. Combine appears only via SwiftUI's `ObservableObject` for view refresh — engine notifications use a plain callback (`AssetStore.onAssetsChanged`)
- `MascotState` raw values map directly to sprite/sound filenames AND to the `state` field on the wire: `idle.{gif,png,jpg,apng}`, `working.{gif,png,jpg,apng}` (sprites), `idle.{wav,mp3,...}` / `working.{wav,mp3,...}` (sounds)
- A speech bubble only fires on actual state transitions (idle↔working). Repeated events at the same state are deduped in `EventManager.applyTransition`
- **ntfy.sh push**: when `config.ntfy.enabled`, `EventManager.handleEvent` fires `NtfyNotifier.notify` on a per-session transition *into* `idle` — the same moment the speech bubble appears. The decision is the pure `EventManager.shouldNotifyIdle(previousState:eventState:)` (captures `mascot.state` before `applyTransition`). Title = session name, body = `speeches.idle`. `NtfyNotifier` uses ntfy's JSON publishing mode (POST `{topic,title,message}` to the server *root*) so non-ASCII titles/bodies survive (HTTP headers are latin-1); fire-and-forget via an injectable `transport` (real path = `URLSession`, tests inject a capturing closure). Settings (`server`/`topic`/`token`) live in `config.ntfy`, edited via the Preferences "Notifications" section, hot-reloaded by assigning `notifier.settings` in `onAssetsChanged`
- Sounds default to one-shot at transition. Per-state `loops` flag in config (set via Preferences checkbox) makes the sound loop while in that state; transitioning out stops it. `EventManager.syncLoop()` re-evaluates the current state's loop after startup and after hot reload, so toggling the checkbox or swapping the file takes effect immediately
- Movement is gated per-state via `movements: { idle, working }` in config (default both `true`). `CharacterController.tick()` short-circuits when `movements.value(for: currentState)` is false. Global `speed` is a Double in config (range 0.5–6.0 px/frame at 30fps, default 2.0). Both apply on hot reload via `setMovement` / `setSpeed`
- **Social movement (episodic encounters)**: `flocking` (config key, default **on**; Preferences "Social encounters") makes mascots **wander independently** (`CharacterController.handleWander` = random target-seek + separation only — no constant cohesion) and *occasionally* socialize. `EncounterController` — a 30 fps coordinator created in `AppDelegate`, reading `MascotManager.encounterParticipants()` — groups nearby `availableForEncounter` mascots that haven't met recently and drives each encounter through **gather → cuddle (~3 s: stop, face the centroid, bob in a little hop with a ❤️ emote) → disperse**, pushing an `InteractionDirective` (`.gather`/`.cuddle`/`.disperse` + focus point) onto every member's `CharacterController` each tick (`setInteraction`/`clearInteraction`; obeyed by `handleInteraction`, which overrides wander). The hop is a `|sin|` y-offset in the `.cuddle` branch; the ❤️ is a `SpeechBubbleView` shown per-member via `Mascot.showHeart()`/`hideHeart()`, reconciled in `drive()` so only members actually close to the centroid show one. On completion each member goes on a per-mascot `socialCooldown` (60 s, `lastEncountered`) during which it won't join *any* new encounter — it just resumes wandering. **Groups snowball**: a free wanderer within `joinRadius` of a live encounter joins it, and two encounters that drift within `joinRadius` of each other merge, so small gatherings coalesce (up to `maxGroup`); per-member directives let a late joiner keep gathering, then cuddle, after the group already started. `working`/frozen/dragged/hidden mascots are excluded. Movement runs through a momentum low-pass (`velocityDamping`) so dense clusters never vibrate, and facing turns on a low-passed horizontal velocity (`facingFlipThreshold`) so brief jitter doesn't mirror the sprite. `cursor_gather` (default **off**, `radius`) is unchanged — mascots within `radius` of `NSEvent.mouseLocation` steer to the cursor, leaving the band. Force math (`separation`/`cursorSeek`/`steer`/`normalized`) is pure/tested in `Flocking.swift`. With both `flocking` and `cursor_gather` off, `CharacterController` runs the unchanged legacy wander. Hot-reloaded via `setFlocking`/`setCursorGather` + `encounterController.enabled`
- Interaction assets (`InteractionSprite`: `drag`, `click`; `InteractionSound`: `drag_press`, `drag_release`, `click`) live alongside state assets in the same `sprites/` and `sounds/` directories — distinguished only by filename. SpriteEngine has a separate override layer for interaction sprites that is shown on top of the base state sprite and cleared explicitly. SoundPlayer.playInteraction is a one-shot that does not disturb loop state
- `InteractionController` polls the cursor position at 30Hz and toggles `MascotWindow.ignoresMouseEvents` based on whether the cursor is over the sprite frame. While `isMouseDown`, the toggle is forced to `false` so dragging events keep flowing. Drag is recognized when mouseDragged distance ≥ 4px from the mouseDown location; below that threshold mouseUp is treated as a click. Click sprite auto-clears after 1 second; drag sprite clears on mouseUp. `CharacterController.isDragging` flag (separate from `isFrozen`) gates movement during drag
- User assets live in `~/Library/Application Support/Claudeer/{sprites,sounds,config.json}` and are managed by `AssetStore` (the single source of truth for asset paths and config). Nothing is bundled in `Sources/Claudeer/Resources/` — that directory has been removed

## Plugin Structure

```
.claude-plugin/plugin.json     # Plugin manifest — bump version on functional changes
hooks/hooks.json               # Registers SessionStart, UserPromptSubmit, Stop, Notification, PreToolUse, PostToolUse hooks
hooks/scripts/notify.py        # Hook script — uses ${CLAUDE_PLUGIN_ROOT} for path resolution
```

## Gotchas

- `main.swift` must keep that filename — SPM requires it for top-level code
- `swift test` requires full Xcode.app installation, not just Command Line Tools
- Socket path is hardcoded to `/tmp/claudeer.sock` in both `EventServer.swift` and `notify.py` — change both if modifying
- `MascotWindow.ignoresMouseEvents` is dynamically toggled by `InteractionController` based on cursor proximity to the sprite — `true` (click-through) when away, `false` when over the sprite or while a drag is in progress. The `InteractionView` content view overrides `hitTest(_:)` to always return `self` so mouse events go to the interaction layer instead of the inner `NSImageView`
- `CharacterController` freezes movement for 3s during a state transition (`isFrozen` flag) so speech bubbles stay aligned with the character
- `AssetStore` creates the App Support directories on init — first launch is silent, no manual `mkdir` needed
- APNG has no system-defined `UTType` on macOS, so `.apng` files are not selectable in the Preferences file picker. Users should rename `.apng` → `.png` (PNG-compatible). Documented in README
- When changing `AssetStore` slot semantics, remember `SpriteEngine.spriteExtensions` and `SoundPlayer` extension lists must match — both are searched in the same order at load time

## Reference Docs

- Asset registration design: `docs/superpowers/specs/2026-04-26-asset-registration-design.md`
- Asset registration plan: `docs/superpowers/plans/2026-04-26-asset-registration.md`
