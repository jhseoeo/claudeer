# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Claudeer** is a macOS desktop mascot app + Claude Code plugin. A user-customized sprite character roams the screen and reacts to Claude Code session events (start, need input, end) with animations, speech bubbles, and sounds.

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
python3 -c "import socket,json; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock'); s.send(json.dumps({'event':'need_input','session_id':'test'}).encode()+b'\n'); print(s.recv(1024)); s.close()"
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
    SessionStart/Stop/Notification          EventServer (POSIX socket on /tmp/claudeer.sock)
                                                 │
                                           EventManager
                                            │    │    │
                              CharacterController │  SoundPlayer
                                    │         SpeechBubbleView
                              SpriteEngine
                                    │
                              MascotWindow (transparent NSWindow, click-through)

AssetStore (~/Library/Application Support/Claudeer/)
  ├── feeds: SpriteEngine.loadSprites(...) / SoundPlayer.loadSounds(...) / EventManager.config
  └── edited via: PreferencesWindow → PreferencesView (SwiftUI)
```

**Startup wiring** (`main.swift`): AssetStore → MascotWindow → SpriteEngine → SpeechBubble → SoundPlayer → CharacterController → EventManager → EventServer → MenuBarController (with assetStore reference). Order matters. AssetStore is built first because it owns the App Support directory and config.

**Hot reload**: `AssetStore.onAssetsChanged` is set in `main.swift` to call `SpriteEngine.loadSprites`, `SoundPlayer.loadSounds`, and update `EventManager.config` whenever the user registers/clears/edits via Preferences. No app restart needed.

**Thread model**: EventServer accept loop runs on a background GCD queue. All events are dispatched to main thread via `DispatchQueue.main.async` before touching UI. `serverFD` and `running` are protected by NSLock.

**Hook flow**: Claude Code fires hook → `notify.py` reads stdin JSON, sends event to Unix socket, prints `{"continue": true}`. Fails silently if app isn't running.

## Key Conventions

- **Pure stdlib** on both sides — no external Swift packages, no Python pip dependencies
- SwiftUI is used for two surfaces: the menu bar popover (`MenuBarController`) and the Preferences window (`PreferencesView`). Everything else (overlay, sprite, speech bubble) is AppKit. Combine appears only via SwiftUI's `ObservableObject` for view refresh — engine notifications use a plain callback (`AssetStore.onAssetsChanged`)
- Sprite states map directly to filenames: `idle.gif`, `walk.gif`, `alert.gif` (also `.png`/`.jpg`/`.apng`)
- `EventType` raw values match JSON event names and sound filenames: `session_start`, `need_input`, `session_end`
- User assets live in `~/Library/Application Support/Claudeer/{sprites,sounds,config.json}` and are managed by `AssetStore` (the single source of truth for asset paths and config). Nothing is bundled in `Sources/Claudeer/Resources/` — that directory has been removed

## Plugin Structure

```
.claude-plugin/plugin.json     # Plugin manifest — bump version on functional changes
hooks/hooks.json               # Registers SessionStart, Stop, Notification hooks
hooks/scripts/notify.py        # Hook script — uses ${CLAUDE_PLUGIN_ROOT} for path resolution
```

## Gotchas

- `main.swift` must keep that filename — SPM requires it for top-level code
- `swift test` requires full Xcode.app installation, not just Command Line Tools
- Socket path is hardcoded to `/tmp/claudeer.sock` in both `EventServer.swift` and `notify.py` — change both if modifying
- `MascotWindow.ignoresMouseEvents = true` makes the entire overlay click-through; partial hit-testing would require overriding `NSView.hitTest(_:)`
- `CharacterController` freezes movement during alert state (`isAlerted` flag) so speech bubbles stay aligned with the character
- `AssetStore` creates the App Support directories on init — first launch is silent, no manual `mkdir` needed
- APNG has no system-defined `UTType` on macOS, so `.apng` files are not selectable in the Preferences file picker. Users should rename `.apng` → `.png` (PNG-compatible). Documented in README
- When changing `AssetStore` slot semantics, remember `SpriteEngine.spriteExtensions` and `SoundPlayer` extension lists must match — both are searched in the same order at load time

## Reference Docs

- Asset registration design: `docs/superpowers/specs/2026-04-26-asset-registration-design.md`
- Asset registration plan: `docs/superpowers/plans/2026-04-26-asset-registration.md`
