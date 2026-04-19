# Claude Speaki

Desktop mascot app for macOS that reacts to Claude Code session events.

A sprite character roams your screen and alerts you with animations,
speech bubbles, and sounds when Claude Code needs your attention.

## Requirements

- macOS 13+
- Swift 5.9+ / Xcode 15+
- Claude Code with plugin support

## Setup

### 1. Build the app

```bash
swift build -c release
```

### 2. Install as Claude Code plugin

```bash
claude plugin add /path/to/claude-speaki
```

### 3. Run the app

```bash
.build/release/ClaudeSpeaki
```

The mascot will appear on your screen and start listening for events.

## Customization

### Sprites

Place your sprite files in `Sources/ClaudeSpeaki/Resources/sprites/`:

| File | Purpose | Formats |
|------|---------|---------|
| `idle.gif` | Default idle animation | GIF, APNG, PNG |
| `walk.gif` | Walking animation | GIF, APNG, PNG |
| `alert.gif` | Alert/notification reaction | GIF, APNG, PNG |

Only `idle` is required. Missing sprites fall back to `idle`.

### Sounds

Place sound files in `Sources/ClaudeSpeaki/Resources/sounds/`:

| File | Trigger | Formats |
|------|---------|---------|
| `session_start.wav` | Claude Code session starts | WAV, MP3, AIFF, M4A |
| `need_input.wav` | Claude needs your input | WAV, MP3, AIFF, M4A |
| `session_end.wav` | Session ends | WAV, MP3, AIFF, M4A |

All sounds are optional.

### Speech Bubbles

Edit `Sources/ClaudeSpeaki/Resources/config.json`:

```json
{
  "default_area": "bottom",
  "speeches": {
    "session_start": "Let's go!",
    "need_input": "Hey! Need your input!",
    "session_end": "See you later!"
  }
}
```

### Area Presets

Choose where the mascot roams via the menu bar icon:

- **Full Screen** — entire screen
- **Bottom** — bottom edge
- **Top** — top edge
- **Menu Bar** — near the menu bar
- **Right 1/4** — right quarter
- **Left 1/4** — left quarter

## How It Works

1. The app opens a Unix socket at `/tmp/claude-speaki.sock`
2. Claude Code hooks (installed via plugin) send JSON events to this socket
3. The app reacts with character animations, speech bubbles, and sounds
4. If the app isn't running, hooks silently fail (no impact on Claude Code)
