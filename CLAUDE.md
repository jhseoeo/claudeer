# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Claude Speaki** is a macOS desktop mascot app + Claude Code plugin. A user-customized sprite character roams the screen and reacts to Claude Code session events (start, need input, end) with animations, speech bubbles, and sounds.

## Build & Test

```bash
swift build                     # Debug build
swift build -c release          # Release build
swift test                      # Run all tests (requires Xcode, not just CLT)
swift test --filter ConfigTests # Run a single test suite
.build/debug/ClaudeSpeaki       # Run debug build
```

Manual socket test (while app is running):
```bash
python3 -c "import socket,json; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claude-speaki.sock'); s.send(json.dumps({'event':'need_input','session_id':'test'}).encode()+b'\n'); print(s.recv(1024)); s.close()"
```

Test as Claude Code plugin:
```bash
claude plugin add /path/to/claude-speaki
```

## Architecture

The app acts as its own daemon — no separate server process.

```
Claude Code Hooks (Python) ──(Unix Socket)──> Swift App
    notify.py                                    │
    SessionStart/Stop/Notification          EventServer (POSIX socket on /tmp/claude-speaki.sock)
                                                 │
                                           EventManager
                                            │    │    │
                              CharacterController │  SoundPlayer
                                    │         SpeechBubbleView
                              SpriteEngine
                                    │
                              MascotWindow (transparent NSWindow, click-through)
```

**Startup wiring** (`main.swift`): Config → MascotWindow → SpriteEngine → SpeechBubble → SoundPlayer → CharacterController → EventManager → EventServer → MenuBarController. Order matters.

**Thread model**: EventServer accept loop runs on a background GCD queue. All events are dispatched to main thread via `DispatchQueue.main.async` before touching UI. `serverFD` and `running` are protected by NSLock.

**Hook flow**: Claude Code fires hook → `notify.py` reads stdin JSON, sends event to Unix socket, prints `{"continue": true}`. Fails silently if app isn't running.

## Key Conventions

- **Pure stdlib** on both sides — no external Swift packages, no Python pip dependencies
- SwiftUI is only used for the menu bar popover (`MenuBarController`); everything else is AppKit
- Sprite states map directly to filenames: `idle.gif`, `walk.gif`, `alert.gif`
- `EventType` raw values match JSON event names and sound filenames: `session_start`, `need_input`, `session_end`
- Resources live in `Sources/ClaudeSpeaki/Resources/` and are accessed via `Bundle.module`

## Plugin Structure

```
.claude-plugin/plugin.json     # Plugin manifest — bump version on functional changes
hooks/hooks.json               # Registers SessionStart, Stop, Notification hooks
hooks/scripts/notify.py        # Hook script — uses ${CLAUDE_PLUGIN_ROOT} for path resolution
```

## Gotchas

- `main.swift` must keep that filename — SPM requires it for top-level code
- `swift test` requires full Xcode.app installation, not just Command Line Tools
- Socket path is hardcoded to `/tmp/claude-speaki.sock` in both `EventServer.swift` and `notify.py` — change both if modifying
- `MascotWindow.ignoresMouseEvents = true` makes the entire overlay click-through; partial hit-testing would require overriding `NSView.hitTest(_:)`
- `CharacterController` freezes movement during alert state (`isAlerted` flag) so speech bubbles stay aligned with the character
- `Sources/ClaudeSpeaki/Resources/sounds/` directory doesn't exist by default — users must create it and add their own sound files
