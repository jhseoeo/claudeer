# Asset Registration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace build-time asset bundling with runtime registration through a native Preferences window. Users pick sprite/sound files via file pickers; the app copies them into Application Support and reloads live without restart.

**Architecture:** New `AssetStore` owns the App Support directory and is the single source of truth for asset paths and config. New `PreferencesWindow` (NSWindow + SwiftUI via `NSHostingController`) edits `AssetStore` directly. Existing engines (`SpriteEngine`, `SoundPlayer`) are unchanged — they already accept URLs. Hot reload happens via a single `onAssetsChanged` callback wired in `main.swift`. Reference spec: `docs/superpowers/specs/2026-04-26-asset-registration-design.md`.

**Tech Stack:** Swift 5.9+, AppKit, SwiftUI (`NSHostingController`, `ObservableObject`), Foundation (`FileManager`), XCTest, UniformTypeIdentifiers (`UTType`)

> **Note on testing:** `swift test` requires full Xcode.app installation, not just Command Line Tools (per `CLAUDE.md`). Tests use temporary directories — do not depend on user's actual `~/Library/Application Support/`.

---

## File Structure

**New:**
- `Sources/Claudeer/AssetStore.swift` — App Support dir manager, single source of truth for asset paths and config; emits `onAssetsChanged` callback
- `Sources/Claudeer/PreferencesWindow.swift` — `NSWindow` subclass hosting `PreferencesView` via `NSHostingController`
- `Sources/Claudeer/PreferencesView.swift` — SwiftUI view with Sprites/Sounds/Speeches sections; reads/mutates `AssetStore`
- `Tests/ClaudeerTests/AssetStoreTests.swift` — unit tests for asset registration, clearing, speech updates, config persistence

**Modified:**
- `Sources/Claudeer/Config.swift` — add `save(to:)` method
- `Sources/Claudeer/EventManager.swift` — change `private let config` to internal var so it can be updated at runtime
- `Sources/Claudeer/SpriteEngine.swift` — clear sprite dictionary at start of `loadSprites` (idempotent reload); add `"jpg"` to extensions
- `Sources/Claudeer/SoundPlayer.swift` — clear sound dictionary at start of `loadSounds` (idempotent reload)
- `Sources/Claudeer/main.swift` — instantiate `AssetStore`, replace `Bundle.module` resource lookups with App Support paths, wire `onAssetsChanged` callback for hot reload
- `Sources/Claudeer/MenuBarController.swift` — add "Preferences..." button to popover; own a `PreferencesWindow` singleton
- `Package.swift` — remove `resources: [.copy("Resources")]` directive
- `README.md` — replace "Customize resources" build-time instructions with Preferences-window flow; add GIF vs APNG transparency note
- `.claude-plugin/plugin.json` — bump version to `0.2.0`

**Deleted:**
- `Sources/Claudeer/Resources/` — entire directory (only contains `config.json` placeholder; sprites/sounds were always user-supplied)

**Documentation (separate skill invocation):**
- `CLAUDE.md` — updated via `/claude-md-improver` skill in Task 15. Changes: SwiftUI scope expanded (popover + Preferences window), removal of bundled Resources convention, new asset directory location.

---

### Task 1: SpriteEngine + SoundPlayer Reload Safety

Existing engines accumulate state across `loadSprites`/`loadSounds` calls. With hot reload, we need them to clear before re-loading. Also add `jpg` to sprite extensions per spec.

**Files:**
- Modify: `Sources/Claudeer/SpriteEngine.swift`
- Modify: `Sources/Claudeer/SoundPlayer.swift`

- [ ] **Step 1: Update SpriteEngine.loadSprites — clear + add jpg**

Replace the body of `loadSprites(from:)` in `Sources/Claudeer/SpriteEngine.swift`:

```swift
func loadSprites(from directory: URL) {
    sprites.removeAll()
    let extensions = ["gif", "apng", "png", "jpg"]
    for state in SpriteState.allCases {
        for ext in extensions {
            let url = directory.appendingPathComponent("\(state.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path),
               let image = NSImage(contentsOf: url) {
                sprites[state] = image
                break
            }
        }
    }
    if sprites[.idle] == nil, let first = sprites.values.first {
        sprites[.idle] = first
    }
    setState(.idle)
}
```

- [ ] **Step 2: Update SoundPlayer.loadSounds — clear before loading**

Replace the body of `loadSounds(from:)` in `Sources/Claudeer/SoundPlayer.swift`:

```swift
func loadSounds(from directory: URL) {
    sounds.removeAll()
    let extensions = ["wav", "mp3", "aiff", "m4a"]
    for eventType in EventType.allCases {
        for ext in extensions {
            let url = directory.appendingPathComponent("\(eventType.rawValue).\(ext)")
            if let sound = NSSound(contentsOf: url, byReference: false) {
                sounds[eventType] = sound
                break
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/Claudeer/SpriteEngine.swift Sources/Claudeer/SoundPlayer.swift
git commit -m "refactor: make sprite/sound loaders idempotent for hot reload"
```

---

### Task 2: SpeakiConfig.save Method

`AssetStore` will need to write `config.json` back to disk after speech edits. Add a save method.

**Files:**
- Modify: `Sources/Claudeer/Config.swift`
- Modify: `Tests/ClaudeerTests/ConfigTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `Tests/ClaudeerTests/ConfigTests.swift` (inside the existing `final class ConfigTests: XCTestCase`):

```swift
func testSaveAndReload() throws {
    let original = SpeakiConfig(
        defaultArea: "top",
        speeches: Speeches(sessionStart: "Yo", needInput: "Halp", sessionEnd: "Cya")
    )
    let tmpURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("claudeer-test-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: tmpURL) }

    try original.save(to: tmpURL)
    let reloaded = SpeakiConfig.load(from: tmpURL)

    XCTAssertEqual(reloaded.defaultArea, "top")
    XCTAssertEqual(reloaded.speeches.sessionStart, "Yo")
    XCTAssertEqual(reloaded.speeches.needInput, "Halp")
    XCTAssertEqual(reloaded.speeches.sessionEnd, "Cya")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigTests/testSaveAndReload`
Expected: FAIL — `save(to:)` not found

- [ ] **Step 3: Implement save method**

Add to `Sources/Claudeer/Config.swift` inside the `SpeakiConfig` struct (after the `load` method):

```swift
func save(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(self)
    try data.write(to: url)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigTests/testSaveAndReload`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/Config.swift Tests/ClaudeerTests/ConfigTests.swift
git commit -m "feat: add SpeakiConfig.save method for runtime persistence"
```

---

### Task 3: AssetStore — Directory Setup

Create `AssetStore` with directory creation and path computation. Inject `baseDirectory` for testability.

**Files:**
- Create: `Sources/Claudeer/AssetStore.swift`
- Create: `Tests/ClaudeerTests/AssetStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeerTests/AssetStoreTests.swift`:

```swift
import XCTest
@testable import Claudeer

final class AssetStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeer-test-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testInitCreatesDirectories() {
        _ = AssetStore(baseDirectory: tempDir)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("sprites").path,
            isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempDir.appendingPathComponent("sounds").path,
            isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testPathGetters() {
        let store = AssetStore(baseDirectory: tempDir)
        XCTAssertEqual(store.spritesDirectory, tempDir.appendingPathComponent("sprites"))
        XCTAssertEqual(store.soundsDirectory, tempDir.appendingPathComponent("sounds"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AssetStoreTests`
Expected: FAIL — `AssetStore` not found

- [ ] **Step 3: Implement AssetStore (init only)**

Create `Sources/Claudeer/AssetStore.swift`:

```swift
import Foundation

class AssetStore {
    let baseDirectory: URL

    var spritesDirectory: URL { baseDirectory.appendingPathComponent("sprites") }
    var soundsDirectory: URL { baseDirectory.appendingPathComponent("sounds") }
    var configURL: URL { baseDirectory.appendingPathComponent("config.json") }

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(
            at: spritesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: soundsDirectory, withIntermediateDirectories: true)
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Claudeer")
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AssetStoreTests`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/AssetStore.swift Tests/ClaudeerTests/AssetStoreTests.swift
git commit -m "feat: add AssetStore foundation with directory creation"
```

---

### Task 4: AssetStore — Asset URL Discovery

`AssetStore` needs to report which sprite/sound is currently registered for each slot.

**Files:**
- Modify: `Sources/Claudeer/AssetStore.swift`
- Modify: `Tests/ClaudeerTests/AssetStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `AssetStoreTests`:

```swift
func testCurrentSpriteURLReturnsNilWhenMissing() {
    let store = AssetStore(baseDirectory: tempDir)
    XCTAssertNil(store.currentSpriteURL(for: .idle))
}

func testCurrentSpriteURLFindsExistingFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let spriteFile = store.spritesDirectory.appendingPathComponent("idle.gif")
    try Data("fake".utf8).write(to: spriteFile)
    XCTAssertEqual(store.currentSpriteURL(for: .idle), spriteFile)
}

func testCurrentSpriteURLPicksFirstMatchingExtension() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let pngFile = store.spritesDirectory.appendingPathComponent("walk.png")
    try Data("fake".utf8).write(to: pngFile)
    XCTAssertEqual(store.currentSpriteURL(for: .walk), pngFile)
}

func testCurrentSoundURLReturnsNilWhenMissing() {
    let store = AssetStore(baseDirectory: tempDir)
    XCTAssertNil(store.currentSoundURL(for: .needInput))
}

func testCurrentSoundURLFindsExistingFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let soundFile = store.soundsDirectory.appendingPathComponent("session_start.wav")
    try Data("fake".utf8).write(to: soundFile)
    XCTAssertEqual(store.currentSoundURL(for: .sessionStart), soundFile)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AssetStoreTests`
Expected: FAIL — `currentSpriteURL` and `currentSoundURL` not found

- [ ] **Step 3: Implement URL discovery methods**

Add to `Sources/Claudeer/AssetStore.swift` (inside the `AssetStore` class):

```swift
static let spriteExtensions = ["gif", "apng", "png", "jpg"]
static let soundExtensions = ["wav", "mp3", "aiff", "m4a"]

func currentSpriteURL(for state: SpriteState) -> URL? {
    for ext in Self.spriteExtensions {
        let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    return nil
}

func currentSoundURL(for event: EventType) -> URL? {
    for ext in Self.soundExtensions {
        let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
    }
    return nil
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AssetStoreTests`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/AssetStore.swift Tests/ClaudeerTests/AssetStoreTests.swift
git commit -m "feat: add asset URL discovery to AssetStore"
```

---

### Task 5: AssetStore — Register and Clear

Copy a source file into the slot, deleting any existing file in that slot first (handles extension switching). Clear deletes any file in the slot.

**Files:**
- Modify: `Sources/Claudeer/AssetStore.swift`
- Modify: `Tests/ClaudeerTests/AssetStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `AssetStoreTests`:

```swift
func testRegisterSpriteCopiesFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let source = tempDir.appendingPathComponent("source.gif")
    try Data("data".utf8).write(to: source)

    try store.registerSprite(source: source, for: .idle)

    let dest = store.spritesDirectory.appendingPathComponent("idle.gif")
    XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    XCTAssertEqual(try Data(contentsOf: dest), Data("data".utf8))
}

func testRegisterSpriteReplacesDifferentExtension() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let oldFile = store.spritesDirectory.appendingPathComponent("idle.png")
    try Data("old".utf8).write(to: oldFile)

    let source = tempDir.appendingPathComponent("source.gif")
    try Data("new".utf8).write(to: source)
    try store.registerSprite(source: source, for: .idle)

    XCTAssertFalse(FileManager.default.fileExists(atPath: oldFile.path))
    let newFile = store.spritesDirectory.appendingPathComponent("idle.gif")
    XCTAssertTrue(FileManager.default.fileExists(atPath: newFile.path))
}

func testRegisterSoundCopiesFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let source = tempDir.appendingPathComponent("ding.wav")
    try Data("audio".utf8).write(to: source)

    try store.registerSound(source: source, for: .needInput)

    let dest = store.soundsDirectory.appendingPathComponent("need_input.wav")
    XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
}

func testClearSpriteRemovesFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let file = store.spritesDirectory.appendingPathComponent("idle.gif")
    try Data("data".utf8).write(to: file)

    store.clearSprite(for: .idle)

    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertNil(store.currentSpriteURL(for: .idle))
}

func testClearSpriteWhenAbsentIsNoOp() {
    let store = AssetStore(baseDirectory: tempDir)
    store.clearSprite(for: .alert)  // no file exists; should not throw
    XCTAssertNil(store.currentSpriteURL(for: .alert))
}

func testClearSoundRemovesFile() throws {
    let store = AssetStore(baseDirectory: tempDir)
    let file = store.soundsDirectory.appendingPathComponent("session_end.mp3")
    try Data("data".utf8).write(to: file)

    store.clearSound(for: .sessionEnd)

    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AssetStoreTests`
Expected: FAIL — `registerSprite`, `clearSprite`, `registerSound`, `clearSound` not found

- [ ] **Step 3: Implement register and clear**

Add to `Sources/Claudeer/AssetStore.swift` (inside the `AssetStore` class):

```swift
func registerSprite(source: URL, for state: SpriteState) throws {
    clearSprite(for: state)
    let ext = source.pathExtension.lowercased()
    let dest = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
    try FileManager.default.copyItem(at: source, to: dest)
}

func registerSound(source: URL, for event: EventType) throws {
    clearSound(for: event)
    let ext = source.pathExtension.lowercased()
    let dest = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
    try FileManager.default.copyItem(at: source, to: dest)
}

func clearSprite(for state: SpriteState) {
    for ext in Self.spriteExtensions {
        let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try? FileManager.default.removeItem(at: url)
    }
}

func clearSound(for event: EventType) {
    for ext in Self.soundExtensions {
        let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AssetStoreTests`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/AssetStore.swift Tests/ClaudeerTests/AssetStoreTests.swift
git commit -m "feat: add register/clear operations to AssetStore"
```

---

### Task 6: AssetStore — Config Loading, Speech Updates, Change Notification

Hold the `SpeakiConfig`, persist speech edits to disk, fire `onAssetsChanged` callback after every mutation.

**Files:**
- Modify: `Sources/Claudeer/AssetStore.swift`
- Modify: `Tests/ClaudeerTests/AssetStoreTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `AssetStoreTests`:

```swift
func testInitLoadsDefaultConfigWhenAbsent() {
    let store = AssetStore(baseDirectory: tempDir)
    XCTAssertEqual(store.config.defaultArea, SpeakiConfig.default.defaultArea)
    XCTAssertEqual(store.config.speeches.sessionStart, SpeakiConfig.default.speeches.sessionStart)
}

func testInitLoadsExistingConfig() throws {
    let custom = SpeakiConfig(
        defaultArea: "top",
        speeches: Speeches(sessionStart: "A", needInput: "B", sessionEnd: "C")
    )
    let configURL = tempDir.appendingPathComponent("config.json")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    try custom.save(to: configURL)

    let store = AssetStore(baseDirectory: tempDir)
    XCTAssertEqual(store.config.defaultArea, "top")
    XCTAssertEqual(store.config.speeches.sessionStart, "A")
}

func testUpdateSpeechPersistsToDisk() throws {
    let store = AssetStore(baseDirectory: tempDir)
    store.updateSpeech(for: .needInput, text: "Custom message")

    let reloaded = SpeakiConfig.load(from: store.configURL)
    XCTAssertEqual(reloaded.speeches.needInput, "Custom message")
    XCTAssertEqual(reloaded.speeches.sessionStart, SpeakiConfig.default.speeches.sessionStart)
}

func testOnAssetsChangedFiresAfterRegister() throws {
    let store = AssetStore(baseDirectory: tempDir)
    var fired = 0
    store.onAssetsChanged = { fired += 1 }

    let source = tempDir.appendingPathComponent("s.gif")
    try Data("d".utf8).write(to: source)
    try store.registerSprite(source: source, for: .idle)

    XCTAssertEqual(fired, 1)
}

func testOnAssetsChangedFiresAfterClear() {
    let store = AssetStore(baseDirectory: tempDir)
    var fired = 0
    store.onAssetsChanged = { fired += 1 }

    store.clearSprite(for: .idle)
    XCTAssertEqual(fired, 1)
}

func testOnAssetsChangedFiresAfterUpdateSpeech() {
    let store = AssetStore(baseDirectory: tempDir)
    var fired = 0
    store.onAssetsChanged = { fired += 1 }

    store.updateSpeech(for: .sessionStart, text: "Hi")
    XCTAssertEqual(fired, 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AssetStoreTests`
Expected: FAIL — `config`, `updateSpeech`, `onAssetsChanged` not found

- [ ] **Step 3: Add config loading and speech updates**

Modify `Sources/Claudeer/AssetStore.swift`. Add the `config` property, callback, and `updateSpeech`. Also fire `onAssetsChanged` from existing `registerSprite`/`registerSound`/`clearSprite`/`clearSound` methods.

Replace the file with:

```swift
import Foundation

class AssetStore {
    let baseDirectory: URL
    private(set) var config: SpeakiConfig
    var onAssetsChanged: (() -> Void)?

    var spritesDirectory: URL { baseDirectory.appendingPathComponent("sprites") }
    var soundsDirectory: URL { baseDirectory.appendingPathComponent("sounds") }
    var configURL: URL { baseDirectory.appendingPathComponent("config.json") }

    static let spriteExtensions = ["gif", "apng", "png", "jpg"]
    static let soundExtensions = ["wav", "mp3", "aiff", "m4a"]

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        try? FileManager.default.createDirectory(
            at: baseDirectory.appendingPathComponent("sprites"),
            withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: baseDirectory.appendingPathComponent("sounds"),
            withIntermediateDirectories: true)
        self.config = SpeakiConfig.load(
            from: baseDirectory.appendingPathComponent("config.json"))
    }

    static var defaultBaseDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Claudeer")
    }

    func currentSpriteURL(for state: SpriteState) -> URL? {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func currentSoundURL(for event: EventType) -> URL? {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    func registerSprite(source: URL, for state: SpriteState) throws {
        clearSpriteFiles(for: state)
        let ext = source.pathExtension.lowercased()
        let dest = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        onAssetsChanged?()
    }

    func registerSound(source: URL, for event: EventType) throws {
        clearSoundFiles(for: event)
        let ext = source.pathExtension.lowercased()
        let dest = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
        try FileManager.default.copyItem(at: source, to: dest)
        onAssetsChanged?()
    }

    func clearSprite(for state: SpriteState) {
        clearSpriteFiles(for: state)
        onAssetsChanged?()
    }

    func clearSound(for event: EventType) {
        clearSoundFiles(for: event)
        onAssetsChanged?()
    }

    func updateSpeech(for event: EventType, text: String) {
        let s = config.speeches
        let updated: Speeches
        switch event {
        case .sessionStart:
            updated = Speeches(sessionStart: text, needInput: s.needInput, sessionEnd: s.sessionEnd)
        case .needInput:
            updated = Speeches(sessionStart: s.sessionStart, needInput: text, sessionEnd: s.sessionEnd)
        case .sessionEnd:
            updated = Speeches(sessionStart: s.sessionStart, needInput: s.needInput, sessionEnd: text)
        }
        config = SpeakiConfig(defaultArea: config.defaultArea, speeches: updated)
        try? config.save(to: configURL)
        onAssetsChanged?()
    }

    private func clearSpriteFiles(for state: SpriteState) {
        for ext in Self.spriteExtensions {
            let url = spritesDirectory.appendingPathComponent("\(state.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func clearSoundFiles(for event: EventType) {
        for ext in Self.soundExtensions {
            let url = soundsDirectory.appendingPathComponent("\(event.rawValue).\(ext)")
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Run all AssetStore tests**

Run: `swift test --filter AssetStoreTests`
Expected: PASS (all tests, including the earlier register/clear tests now exercising the public methods that fire callbacks)

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/AssetStore.swift Tests/ClaudeerTests/AssetStoreTests.swift
git commit -m "feat: add config persistence and change callback to AssetStore"
```

---

### Task 7: AssetStore — ObservableObject Conformance

`PreferencesView` (SwiftUI) needs to refresh when `AssetStore` mutates. Add `ObservableObject` conformance with a `@Published` change counter. The existing `onAssetsChanged` callback remains for non-UI consumers (engines).

**Files:**
- Modify: `Sources/Claudeer/AssetStore.swift`

- [ ] **Step 1: Add ObservableObject conformance**

In `Sources/Claudeer/AssetStore.swift`:

1. Add `import Combine` at the top of the file (just below `import Foundation`).
2. Change the class declaration:

```swift
class AssetStore: ObservableObject {
```

3. Add a published change counter just below the existing properties:

```swift
@Published private(set) var changeVersion: Int = 0
```

4. Replace every `onAssetsChanged?()` call in the class body with a call to a new private `notify()` method:

```swift
private func notify() {
    changeVersion += 1
    onAssetsChanged?()
}
```

So `registerSprite`, `registerSound`, `clearSprite`, `clearSound`, `updateSpeech` all call `notify()` instead of `onAssetsChanged?()` directly.

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run AssetStore tests to confirm callback still works**

Run: `swift test --filter AssetStoreTests`
Expected: PASS (callback tests still pass — `onAssetsChanged` still fires from `notify()`)

- [ ] **Step 4: Commit**

```bash
git add Sources/Claudeer/AssetStore.swift
git commit -m "feat: make AssetStore observable for SwiftUI binding"
```

---

### Task 8: EventManager — Mutable Config

`EventManager` currently holds `private let config`. Hot reload needs to swap the config at runtime. Make it an internal `var`.

**Files:**
- Modify: `Sources/Claudeer/EventManager.swift`

- [ ] **Step 1: Change config to var**

In `Sources/Claudeer/EventManager.swift`, change line 8 from:

```swift
private let config: SpeakiConfig
```

to:

```swift
var config: SpeakiConfig
```

(Removing `private` so `main.swift` can update it; removing `let` so it can be reassigned.)

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/Claudeer/EventManager.swift
git commit -m "refactor: make EventManager.config mutable for runtime updates"
```

---

### Task 9: Wire AssetStore into main.swift, Remove Bundled Resources

Replace `Bundle.module` resource lookups with `AssetStore` paths. Wire `onAssetsChanged` to reload engines and update event manager config. Delete bundled `Resources/` directory and remove the `resources` directive from `Package.swift`.

**Files:**
- Modify: `Sources/Claudeer/main.swift`
- Modify: `Package.swift`
- Delete: `Sources/Claudeer/Resources/` (entire directory)

- [ ] **Step 1: Replace main.swift with AssetStore-based wiring**

Replace the entire contents of `Sources/Claudeer/main.swift`:

```swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mascotWindow: MascotWindow?
    var spriteEngine: SpriteEngine?
    var characterController: CharacterController?
    var eventServer: EventServer?
    var eventManager: EventManager?
    var soundPlayer: SoundPlayer?
    var speechBubble: SpeechBubbleView?
    var menuBarController: MenuBarController?
    var assetStore: AssetStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // AssetStore — single source of truth for assets and config
        let store = AssetStore(baseDirectory: AssetStore.defaultBaseDirectory)
        assetStore = store

        // Setup window
        mascotWindow = MascotWindow()

        let contentView = NSView(frame: mascotWindow!.frame)
        contentView.wantsLayer = true

        // Setup sprite
        let spriteSize = NSRect(x: 100, y: 100, width: 64, height: 64)
        spriteEngine = SpriteEngine(frame: spriteSize)
        contentView.addSubview(spriteEngine!.view)

        // Setup speech bubble
        speechBubble = SpeechBubbleView()
        speechBubble?.isHidden = true
        contentView.addSubview(speechBubble!)

        mascotWindow?.contentView = contentView

        // Load assets from App Support
        spriteEngine?.loadSprites(from: store.spritesDirectory)
        soundPlayer = SoundPlayer()
        soundPlayer?.loadSounds(from: store.soundsDirectory)

        // Setup movement
        characterController = CharacterController(spriteEngine: spriteEngine!)
        if let screen = NSScreen.main {
            let preset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
            characterController?.setArea(preset, screenSize: screen.frame.size)
        }
        characterController?.start()

        // Setup event manager
        eventManager = EventManager(
            characterController: characterController!,
            soundPlayer: soundPlayer!,
            speechBubble: speechBubble!,
            spriteEngine: spriteEngine!,
            config: store.config
        )
        eventManager?.startPIDMonitoring()

        // Hot reload — fired by AssetStore on any mutation
        store.onAssetsChanged = { [weak self] in
            guard let self = self, let store = self.assetStore else { return }
            self.spriteEngine?.loadSprites(from: store.spritesDirectory)
            self.soundPlayer?.loadSounds(from: store.soundsDirectory)
            self.eventManager?.config = store.config
        }

        // Start socket server
        eventServer = EventServer()
        eventServer?.onEvent = { [weak self] event in
            self?.eventManager?.handleEvent(event)
        }
        eventServer?.start()

        // Setup menu bar
        menuBarController = MenuBarController()
        menuBarController?.assetStore = store
        menuBarController?.currentPreset = AreaPreset(rawValue: store.config.defaultArea) ?? .bottom
        menuBarController?.onAreaChanged = { [weak self] preset in
            if let screen = NSScreen.main {
                self?.characterController?.setArea(preset, screenSize: screen.frame.size)
            }
        }
        menuBarController?.onVolumeChanged = { [weak self] volume in
            self?.soundPlayer?.volume = volume
        }
        menuBarController?.setup()

        mascotWindow?.makeKeyAndOrderFront(nil)
        print("Claudeer started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        characterController?.stop()
        eventServer?.stop()
        eventManager?.stopPIDMonitoring()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

> **Note:** `menuBarController?.assetStore = store` references a property added in Task 13. The build will fail until Task 13 is done. That's intentional — these tasks ship together. If you need to verify intermediate state, comment out the `assetStore = store` line and re-add it in Task 13.

- [ ] **Step 2: Remove resources directive from Package.swift**

Replace the entire contents of `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Claudeer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Claudeer",
            path: "Sources/Claudeer",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .testTarget(
            name: "ClaudeerTests",
            dependencies: ["Claudeer"],
            path: "Tests/ClaudeerTests"
        ),
    ]
)
```

- [ ] **Step 3: Delete bundled Resources directory and stage deletion**

Run:
```bash
git rm -r Sources/Claudeer/Resources
```

This removes the directory from the working tree AND stages the deletion in one step.

- [ ] **Step 4: Defer build verification and commit**

`swift build` will fail at this point because `main.swift` references `menuBarController?.assetStore` which doesn't exist yet (added in Task 13). Do not attempt to commit yet — Tasks 10, 11, and 13 will land together with this work.

---

### Task 10: PreferencesWindow Class

`NSWindow` subclass that hosts a SwiftUI `PreferencesView` via `NSHostingController`. Singleton owned by `MenuBarController`.

**Files:**
- Create: `Sources/Claudeer/PreferencesWindow.swift`

- [ ] **Step 1: Create PreferencesWindow**

Create `Sources/Claudeer/PreferencesWindow.swift`:

```swift
import AppKit
import SwiftUI

class PreferencesWindow: NSWindow {
    init(assetStore: AssetStore) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        title = "Claudeer Preferences"
        isReleasedWhenClosed = false  // hide on close, do not deallocate
        center()

        let view = PreferencesView(assetStore: assetStore)
        contentViewController = NSHostingController(rootView: view)
    }

    func showAndFocus() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Defer build verification**

This file references `PreferencesView`, which will be created in Task 11. Build will fail. Continue to Task 11.

---

### Task 11: PreferencesView — Sections, Slot Rows, File Pickers, Speech Fields

Single SwiftUI view containing the full Preferences form: Sprites section (3 slots), Sounds section (3 slots), Speeches section (3 text fields). Each asset slot row has a "Choose..." button (opens `NSOpenPanel`) and a "Clear" button (visible only when registered).

**Files:**
- Create: `Sources/Claudeer/PreferencesView.swift`

- [ ] **Step 1: Create PreferencesView**

Create `Sources/Claudeer/PreferencesView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject var assetStore: AssetStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                spritesSection
                Divider()
                soundsSection
                Divider()
                speechesSection
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private var spritesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sprites").font(.headline)
            ForEach(SpriteState.allCases, id: \.self) { state in
                AssetSlotRow(
                    label: state.rawValue.capitalized,
                    currentURL: assetStore.currentSpriteURL(for: state),
                    onChoose: { chooseSprite(for: state) },
                    onClear: { assetStore.clearSprite(for: state) }
                )
                .id(assetStore.changeVersion)
            }
        }
    }

    private var soundsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sounds").font(.headline)
            ForEach(EventType.allCases, id: \.self) { event in
                AssetSlotRow(
                    label: eventLabel(event),
                    currentURL: assetStore.currentSoundURL(for: event),
                    onChoose: { chooseSound(for: event) },
                    onClear: { assetStore.clearSound(for: event) }
                )
                .id(assetStore.changeVersion)
            }
        }
    }

    private var speechesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Speeches").font(.headline)
            SpeechRow(assetStore: assetStore, event: .sessionStart, label: "Session Start")
            SpeechRow(assetStore: assetStore, event: .needInput, label: "Need Input")
            SpeechRow(assetStore: assetStore, event: .sessionEnd, label: "Session End")
        }
    }

    private func eventLabel(_ event: EventType) -> String {
        switch event {
        case .sessionStart: return "Session Start"
        case .needInput: return "Need Input"
        case .sessionEnd: return "Session End"
        }
    }

    private func chooseSprite(for state: SpriteState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // APNG has no system-defined UTType; users can rename .apng → .png (PNG-compatible).
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try assetStore.registerSprite(source: url, for: state)
        } catch {
            presentError(error)
        }
    }

    private func chooseSound(for event: EventType) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .mpeg4Audio]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try assetStore.registerSound(source: url, for: event)
        } catch {
            presentError(error)
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not register file"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct AssetSlotRow: View {
    let label: String
    let currentURL: URL?
    let onChoose: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)
            Text(currentURL?.lastPathComponent ?? "Not registered")
                .foregroundColor(currentURL == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose...", action: onChoose)
            if currentURL != nil {
                Button("Clear", action: onClear)
            }
        }
    }
}

private struct SpeechRow: View {
    @ObservedObject var assetStore: AssetStore
    let event: EventType
    let label: String
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 100, alignment: .leading)
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onAppear { draft = currentText }
                .onChange(of: isFocused) { focused in
                    if !focused { commit() }
                }
                .onSubmit { commit() }
        }
    }

    private var currentText: String {
        switch event {
        case .sessionStart: return assetStore.config.speeches.sessionStart
        case .needInput: return assetStore.config.speeches.needInput
        case .sessionEnd: return assetStore.config.speeches.sessionEnd
        }
    }

    private func commit() {
        if draft != currentText {
            assetStore.updateSpeech(for: event, text: draft)
        }
    }
}
```

> **Note on UTType for sprites:** APNG has no system-defined UTType, so we cannot list it in `allowedContentTypes`. Since APNG files are PNG-compatible at the byte level, users with `.apng` files should rename them to `.png` — they will animate correctly via `NSImageView.animates = true`. This is documented in the README update (Task 14).
>
> **Note on focus-commit pattern:** The `SpeechRow` uses `@FocusState` with `.onChange(of: isFocused)` to commit only when focus leaves the field (or Enter is pressed via `.onSubmit`). This avoids per-keystroke disk writes and matches the spec.

- [ ] **Step 2: Defer build verification**

Continue to Task 12 — `EventType` needs `CaseIterable` and the menubar integration is in Task 13.

---

### Task 12: EventType CaseIterable

`PreferencesView` uses `ForEach(EventType.allCases, ...)`. Verify that `EventType` already conforms to `CaseIterable` (it should, per existing `SoundPlayer` usage). If not, add the conformance.

**Files:**
- Verify: `Sources/Claudeer/EventServer.swift`

- [ ] **Step 1: Inspect EventType declaration**

Open `Sources/Claudeer/EventServer.swift` and find the `EventType` enum. It should read:

```swift
enum EventType: String, Codable, CaseIterable {
```

If it does not include `CaseIterable`, add it. (Per the original spec it was added in plan task 8 of the original implementation; verify it's there.)

- [ ] **Step 2: No commit needed if no change**

If you had to add `CaseIterable`, commit:

```bash
git add Sources/Claudeer/EventServer.swift
git commit -m "refactor: ensure EventType conforms to CaseIterable"
```

Otherwise skip the commit.

---

### Task 13: MenuBarController — Preferences Button + Window Singleton

Add a `PreferencesWindow` singleton owned by `MenuBarController`. Add "Preferences..." button to the popover.

**Files:**
- Modify: `Sources/Claudeer/MenuBarController.swift`

- [ ] **Step 1: Replace MenuBarController**

Replace `Sources/Claudeer/MenuBarController.swift` with:

```swift
import AppKit
import SwiftUI

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var preferencesWindow: PreferencesWindow?

    var assetStore: AssetStore?
    var onAreaChanged: ((AreaPreset) -> Void)?
    var onVolumeChanged: ((Float) -> Void)?
    var currentPreset: AreaPreset = .bottom

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.title = "🐾"
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        let view = MenuBarPopoverView(controller: self)
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 220, height: 320)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: view)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func openPreferences() {
        guard let store = assetStore else { return }
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindow(assetStore: store)
        }
        popover?.performClose(nil)
        preferencesWindow?.showAndFocus()
    }
}

struct MenuBarPopoverView: View {
    let controller: MenuBarController
    @State private var selectedPreset: AreaPreset = .bottom
    @State private var volume: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claudeer")
                .font(.headline)

            Divider()

            Text("Area").font(.subheadline.bold())
            ForEach(AreaPreset.allCases, id: \.self) { preset in
                Button(action: {
                    selectedPreset = preset
                    controller.onAreaChanged?(preset)
                }) {
                    HStack {
                        Image(systemName: selectedPreset == preset ? "checkmark.circle.fill" : "circle")
                        Text(preset.displayName)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                Text("Volume")
                Slider(value: $volume, in: 0...1) { _ in
                    controller.onVolumeChanged?(Float(volume))
                }
            }

            Divider()

            Button("Preferences...") {
                controller.openPreferences()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding()
        .onAppear {
            selectedPreset = controller.currentPreset
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED. (If not, the `assetStore` reference from Task 9's `main.swift` and the new MenuBarController property should now line up.)

- [ ] **Step 3: Run all tests to confirm nothing regressed**

Run: `swift test`
Expected: PASS — all tests still pass

- [ ] **Step 4: Commit (combined with Tasks 9, 10, 11)**

```bash
git add Sources/Claudeer/main.swift Package.swift \
        Sources/Claudeer/PreferencesWindow.swift \
        Sources/Claudeer/PreferencesView.swift \
        Sources/Claudeer/MenuBarController.swift
git commit -m "feat: add Preferences window with asset registration UI"
```

The deletion of `Sources/Claudeer/Resources/` was already staged in Task 9 step 3 via `git rm -r`, so it gets included in this commit automatically.

---

### Task 14: README + plugin.json Updates

Replace build-time customization instructions with the Preferences-window flow. Add the GIF vs APNG transparency note. Bump plugin version.

**Files:**
- Modify: `README.md`
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Replace Customize section in README**

In `README.md`, replace the entire `### 1. Customize resources` section (lines 16-55) with:

```markdown
### 1. Build the app

\`\`\`bash
swift build -c release
\`\`\`

### 2. Install as Claude Code plugin

\`\`\`bash
claude plugin add /path/to/claudeer
\`\`\`

### 3. Run the app

\`\`\`bash
.build/release/Claudeer
\`\`\`

### 4. Customize via Preferences

메뉴바의 🐾 아이콘 클릭 → "Preferences..." 클릭하면 설정 윈도우가 열립니다.

**Sprites** — Idle / Walk / Alert 슬롯에 각각 파일 등록. 형식: PNG, JPG, GIF, APNG.

> **GIF vs APNG**: GIF는 1비트 알파(켜짐/꺼짐)만 지원해서 외곽선이 들쑥날쑥할 수 있어요.
> 부드러운 외곽선이 필요하면 **APNG**를 쓰세요. 변환은 `ezgif.com` 또는
> `ffmpeg -i frame_%03d.png -plays 0 out.apng`.

> **APNG 등록 팁**: APNG는 macOS에 시스템 UTType이 없어서 파일 피커에서 `.apng` 확장자가 안 보일 수 있어요. APNG는 PNG와 호환되니까 `mv myanim.apng myanim.png` 으로 이름만 바꿔서 등록하면 됩니다 (애니메이션 정상 재생).

**Sounds** — Session Start / Need Input / Session End. 형식: WAV, MP3, AIFF, M4A.

**Speeches** — 각 이벤트의 말풍선 텍스트.

등록한 파일은 `~/Library/Application Support/Claudeer/`에 복사되며, 변경 즉시 반영됩니다 (재시작 불필요).
```

Then remove the now-redundant section `### 2. Build` through `### 4. Run the app` from the original (lines 57-78), since the new section already covers them.

> **Result:** README has Setup with steps 1–4, where step 1 builds, step 2 installs, step 3 runs, step 4 customizes via Preferences. Confirm by reading the file after edits.

- [ ] **Step 2: Bump plugin version**

In `.claude-plugin/plugin.json`, change the `version` field from `0.1.0` to `0.2.0`.

- [ ] **Step 3: Commit**

```bash
git add README.md .claude-plugin/plugin.json
git commit -m "docs: update README for Preferences-based asset registration"
```

---

### Task 15: Update CLAUDE.md via /claude-md-improver

`CLAUDE.md` describes the project for future agentic workers. The asset registration change invalidates several items: SwiftUI scope, Resources directory, and convention notes. Use the dedicated skill rather than hand-editing.

- [ ] **Step 1: Invoke the skill**

Run the slash command `/claude-md-improver` (or invoke the `claude-md-management:claude-md-improver` skill). Provide it the following context to update:

> Key changes that invalidate the current CLAUDE.md:
> - SwiftUI is now used in two places: the menu bar popover AND the new `PreferencesWindow` (`PreferencesView.swift`). Update the line that says "SwiftUI is only used for the menu bar popover".
> - `Sources/Claudeer/Resources/` no longer exists. The "Resources live in `Sources/Claudeer/Resources/`..." line is obsolete.
> - User assets now live in `~/Library/Application Support/Claudeer/{sprites,sounds,config.json}` and are managed by `AssetStore`.
> - Startup wiring order in `main.swift` now begins with `AssetStore`. Update the "Startup wiring" line.
> - The `AssetStore` is the single source of truth for asset paths and emits `onAssetsChanged` for hot reload.
> - Spec for this change: `docs/superpowers/specs/2026-04-26-asset-registration-design.md`.
> - "Gotchas" section: the `Sources/Claudeer/Resources/sounds/` line about users needing to create the directory is now obsolete (handled by AssetStore on first launch).

- [ ] **Step 2: Verify the resulting changes**

After the skill makes its edits, open `CLAUDE.md` and confirm:
- SwiftUI scope mentions both popover and Preferences window
- No references to `Sources/Claudeer/Resources/` as a live directory
- Startup wiring section shows `AssetStore` first
- App Support directory location is documented

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for asset registration architecture"
```

---

### Task 16: End-to-End Manual Verification

Confirm the feature works in practice. This step has no automated test — drive the app by hand.

- [ ] **Step 1: Clean state**

Remove any prior App Support directory and rebuild from scratch:

```bash
rm -rf ~/Library/Application\ Support/Claudeer
swift build
```

Expected: BUILD SUCCEEDED, no App Support dir exists.

- [ ] **Step 2: Run the app**

```bash
.build/debug/Claudeer &
```

Expected: Menu bar shows 🐾 icon. No mascot character visible (no sprite registered). `~/Library/Application Support/Claudeer/sprites/`, `sounds/`, and `config.json` exist.

```bash
ls -la ~/Library/Application\ Support/Claudeer/
```

- [ ] **Step 3: Open Preferences**

Click 🐾 → "Preferences...". Verify:
- Window titled "Claudeer Preferences" appears
- Three sections visible: Sprites, Sounds, Speeches
- All sprite/sound slots show "Not registered"
- Speech fields show defaults: "Hello!", "Need your input!", "Goodbye!"

- [ ] **Step 4: Register an idle sprite**

Place any test PNG/GIF/APNG at `/tmp/test-idle.gif` (or use a real mascot file). In Preferences:
- Click "Choose..." next to Idle
- Pick the file
- Confirm: row text changes from "Not registered" to `idle.gif` (or `.png`/etc)
- Confirm: "Clear" button appears
- Confirm: Mascot character appears on screen immediately

- [ ] **Step 5: Verify Clear**

Click "Clear" next to Idle. Confirm:
- Row text reverts to "Not registered"
- "Clear" button disappears
- Mascot character disappears (no idle sprite to render)

- [ ] **Step 6: Verify hot reload of speeches**

Edit "Need Input" field to "TEST_SPEECH". From a separate terminal, send a need_input event:

```bash
python3 -c "import socket,json; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock'); s.send(json.dumps({'event':'need_input','session_id':'test'}).encode()+b'\n'); print(s.recv(1024)); s.close()"
```

Expected: Speech bubble shows "TEST_SPEECH" (after re-registering an idle sprite so the character is visible).

- [ ] **Step 7: Verify config persists**

Quit the app, restart, open Preferences. Confirm:
- "Need Input" field still shows "TEST_SPEECH"
- Any registered sprite/sound files are still listed

- [ ] **Step 8: Final commit**

```bash
git add -A
git commit --allow-empty -m "chore: end-to-end verification of asset registration"
```

(Empty commit acknowledges manual verification was performed.)
