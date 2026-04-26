# Asset Registration via Preferences Window — Design

**Date:** 2026-04-26
**Status:** Approved
**Goal:** Replace build-time asset bundling with runtime registration through a native Preferences window. Users pick sprite/sound files via standard macOS file pickers; the app copies them into Application Support and reloads live without restart.

---

## Motivation

Current model requires users to drop sprite/sound files into `Sources/Claudeer/Resources/` and rebuild. This blocks distribution as a binary and forces a developer-style workflow on end users. The loading code (`SpriteEngine.loadSprites(from:)`, `SoundPlayer.loadSounds(from:)`) is already URL-parameterized, so the engine itself needs no changes — the work is purely a new persistence layer plus a settings UI.

## Scope

**In scope:**
- Sprite registration (idle, walk, alert) — 3 slots
- Sound registration (session_start, need_input, session_end) — 3 slots
- Speech text editing (3 messages) — moved out of bundled `config.json` into UI
- Native Preferences `NSWindow` opened from menu bar
- Hot reload on registration/clear/edit (no restart required)

**Out of scope:**
- Area preset and volume (remain in menu bar popover — they're "now-controls", not configuration)
- Sandboxing / App Store distribution (current model is unsigned developer build)
- Custom sprite sizes (continues to use fixed 64x64 frame)
- Animated WebP support

---

## Storage Layout

```
~/Library/Application Support/Claudeer/
  sprites/
    idle.{gif,png,apng,jpg}       # one extension per slot
    walk.{gif,png,apng,jpg}
    alert.{gif,png,apng,jpg}
  sounds/
    session_start.{wav,mp3,aiff,m4a}
    need_input.{wav,mp3,aiff,m4a}
    session_end.{wav,mp3,aiff,m4a}
  config.json
```

**Filename normalization:** When a user picks `mycharacter.gif` for the idle slot, the file is copied to `sprites/idle.gif`. The original filename is discarded. If the slot already has `idle.png` and the user registers a `.gif`, the old `idle.png` is deleted before the new file is copied. **Slot-to-file is always 1:1.**

**First-launch behavior:**
- App creates `~/Library/Application Support/Claudeer/` and subdirectories if missing.
- If `config.json` is absent or malformed, falls back to hardcoded `SpeakiConfig.default` and writes a fresh `config.json` to disk.
- No assets are bundled. Until the user registers a sprite, the character is not visible. This is the same end-state as the current "no idle.png" case.

**Removed from repo:**
- `Sources/Claudeer/Resources/` directory entirely
- `resources: [.copy("../Resources")]` in `Package.swift`

---

## Supported Formats

### Sprites

| Format | Decode | Animation (`NSImageView.animates = true`) |
|--------|--------|--------------------------------------------|
| PNG    | yes    | static                                     |
| JPG    | yes    | static                                     |
| GIF    | yes    | yes                                        |
| APNG   | yes    | yes                                        |

**WebP is intentionally excluded.** macOS ImageIO decodes WebP but `NSImageView` cannot animate it — the mascot would freeze on the first frame, defeating the purpose. Adding a third-party decoder would break the pure-stdlib convention.

**README guidance:** Include a short note that GIF supports only 1-bit alpha (jagged edges on transparent overlay). For smooth-edged animated mascots, prefer APNG. Suggest `ezgif.com` or `ffmpeg -i frame_%03d.png -plays 0 out.apng` for creating APNGs.

### Sounds

Unchanged from current: WAV, MP3, AIFF, M4A. AVFoundation handles all four natively.

---

## Architecture

### New components

**`AssetStore.swift`** — Owns the App Support directory. Single source of truth for asset paths and `config.json` contents. Exposes:
- `spritesDirectory: URL`, `soundsDirectory: URL`
- `currentSpriteURL(for: SpriteState) -> URL?`
- `currentSoundURL(for: EventType) -> URL?`
- `registerSprite(source: URL, for: SpriteState) throws`
- `registerSound(source: URL, for: EventType) throws`
- `clearSprite(for: SpriteState)`
- `clearSound(for: EventType)`
- `updateSpeech(for: EventType, text: String)`
- `var config: SpeakiConfig` (writes through to disk on mutation)
- `var onAssetsChanged: (() -> Void)?` — single callback fired after any mutation

Mutations are synchronous and disk-backed before the callback fires.

**`PreferencesWindow.swift`** — `NSWindow` subclass. Hosts a `NSHostingController` containing `PreferencesView`. Singleton owned by `MenuBarController`. Closing the window calls `orderOut(nil)` (hide, not deallocate). Repeat opens call `makeKeyAndOrderFront`.

**`PreferencesView.swift`** — SwiftUI. Single scrolling view with three sections: Sprites, Sounds, Speeches. Reads from and mutates `AssetStore`.

### Modified components

**`Config.swift`** — `SpeakiConfig.load(from:)` keeps its signature; `AssetStore` calls it with the App Support path instead of `Bundle.module`. New `save(to: URL)` method for write-through. The `default` static value remains as the fallback.

**`main.swift`** — Wiring order updated:
1. Build `AssetStore` first (creates directories, loads config)
2. Build the rest of the chain as before, but pass `assetStore.spritesDirectory` to `SpriteEngine.loadSprites`, `assetStore.soundsDirectory` to `SoundPlayer.loadSounds`, and `assetStore.config` to `EventManager`
3. Set `assetStore.onAssetsChanged` to a closure that calls `spriteEngine.loadSprites(from:)`, `soundPlayer.loadSounds(from:)`, and updates `eventManager.config`

**`MenuBarController.swift`** — Add a "Preferences..." button to the popover. Holds the `PreferencesWindow` singleton instance.

**`Package.swift`** — Remove `resources: [.copy("../Resources")]`.

### Unchanged

`SpriteEngine`, `SoundPlayer`, `CharacterController`, `EventManager`, `EventServer`, `MascotWindow`, `AreaPreset`. All consume URLs already.

### SwiftUI scope expansion

Current `CLAUDE.md` reads "SwiftUI is only used for the menu bar popover." This needs updating to allow SwiftUI for both popover and Preferences window. **Use the `/claude-md-improver` skill to make this update** rather than editing `CLAUDE.md` by hand.

---

## UI Design

Single scrolling view, no sidebar (9 slots fit comfortably).

### Sprite slot row

```
[Idle ]  ▢ idle.gif (registered)        [Choose...] [Clear]
[Walk ]  ▢ Not registered               [Choose...]
[Alert]  ▢ Not registered               [Choose...]
```

- "Choose..." opens `NSOpenPanel` with `allowedContentTypes` filtered to PNG/JPG/GIF/APNG.
- "Clear" appears only when the slot has a registered file. Clicking deletes the file from App Support.
- The shown filename reflects the current normalized filename (`idle.gif`), not the original source path.

### Sound slot row

Same layout as sprites. `allowedContentTypes` filtered to WAV/MP3/AIFF/M4A.

### Speech section

```
Session Start:  [Hello!_______________________]
Need Input:     [Hey, need your input!________]
Session End:    [Bye!_________________________]
```

`TextField` per message. Commits on focus loss or Enter. Each commit calls `assetStore.updateSpeech(...)` which writes `config.json` to disk and fires `onAssetsChanged`.

---

## Hot Reload Flow

1. User clicks "Choose..." → `NSOpenPanel` runs modally on Preferences window
2. User picks a file → `AssetStore.registerSprite(source:for:)` is called
3. `AssetStore` deletes any existing file in the slot, copies the source into App Support with the normalized name, and fires `onAssetsChanged`
4. The wired callback (set in `main.swift`) calls `SpriteEngine.loadSprites(from: assetStore.spritesDirectory)` and `SoundPlayer.loadSounds(from: assetStore.soundsDirectory)`. The `EventManager` config is also refreshed.
5. Character sprite swaps live; next event uses new sound; next speech bubble uses new text.

**Threading:** UI events occur on the main thread; `AssetStore` runs synchronously on the main thread for simplicity. File I/O is small (a few KB to a few MB at most), and the alternative — async with progress UI — adds complexity without user-visible benefit at these sizes.

---

## Error Handling

**File operations:**
- App Support directory creation failure → present an `NSAlert`, slot state unchanged
- Copy failure (disk full, permission denied, source unreadable) → `NSAlert`, slot state restored to whatever it was before the attempt
- User cancels `NSOpenPanel` → no-op

**Configuration:**
- `config.json` decode failure → log to console, fall back to `SpeakiConfig.default`, overwrite file with defaults on next mutation
- Speech text empty string → permitted (renders an empty bubble; user choice)

**Window lifecycle:**
- Preferences window already open → `makeKeyAndOrderFront(nil)` brings it forward
- Preferences window closed externally (cmd-W) → `orderOut`, instance retained
- App termination → window deallocated normally; no special teardown

**External file system changes:**
- App does not poll App Support. If the user manually deletes/edits files while Preferences is closed, the next "Choose..." workflow re-reads disk. While Preferences is open, the displayed state may be briefly stale; we accept this rather than adding `DispatchSourceFileSystemObject` complexity.

---

## Notification Mechanism

`AssetStore` fires its single `onAssetsChanged` callback synchronously after any mutation. `Combine` is intentionally avoided to keep the project on its pure-stdlib + AppKit convention. The callback is set once at startup in `main.swift`.

---

## Documentation Updates

- **`CLAUDE.md`** — update via `/claude-md-improver` skill. Changes: SwiftUI scope (popover + Preferences window), removal of bundled Resources convention, new asset directory location.
- **`README.md`** — replace the "Customize resources" build-time instructions with "Open Preferences from the menu bar and register your assets." Add the GIF vs APNG transparency note. Add the APNG creation tip.
- **`.claude-plugin/plugin.json`** — bump version (functional change).

---

## Testing

- `AssetStoreTests` — directory creation, register/clear roundtrip, slot-extension switching cleans up old file, config persistence, malformed config falls back to default
- Existing `ConfigTests`, `EventServerTests`, `AreaPresetTests` — should still pass; `Config` API surface is unchanged
- Manual: register each slot via Preferences, verify hot reload, verify Clear works, verify app survives a config.json corruption

---

## Out of Scope / Future

- Per-character sprite size auto-detection (currently fixed at 64x64)
- Multiple character profiles / theme switching
- Animated WebP via SDWebImage or similar
- iCloud sync of registered assets
