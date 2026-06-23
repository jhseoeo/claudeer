# Rename a Mascot's Session Label — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user set a custom label on a mascot via right-click → "Rename…", overriding the auto-derived name, revertible by clearing the field.

**Architecture:** `SessionTracker` owns an in-memory `customNames: [String:String]` (mirrors `hiddenSessionIDs`) plus the last auto name per session (`SessionInfo.name`), and exposes a single resolved `displayName(for:)`. `EventManager` resolves names through that. The right-click menu gains a "Rename…" item that fires a callback wired in `main.swift` to a native `NSAlert`.

**Tech Stack:** Swift, AppKit, SwiftUI (menu bar only), XCTest. Pure stdlib (no packages).

## Global Constraints

- Pure stdlib only — no external Swift packages.
- In-memory only — no `config.json` / `Config.swift` change.
- `MascotState` raw values map to wire/sprite/sound names — do not rename.
- Bump `.claude-plugin/plugin.json` version on functional change (currently 0.8.0 → 0.9.0).
- Match existing test style: `XCTest`, `@testable import Claudeer`, pure-logic units only (no live AppKit windows in tests).

---

### Task 1: `SessionInfo.name` — remember the last auto name

**Files:**
- Modify: `Sources/Claudeer/SessionTracker.swift`
- Test: `Tests/ClaudeerTests/SessionTrackerTests.swift`

**Interfaces:**
- Produces: `SessionInfo.name: String?`; `record(_:)` stores `event.name` (keeps last non-nil).

- [ ] **Step 1: Write failing tests**

```swift
func testRecordStoresEventName() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "My Session"))
    XCTAssertEqual(tracker.sessions[0].name, "My Session")
}

func testRecordPreservesNameWhenNotProvided() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "My Session"))
    tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 1, cwd: "/p", name: nil))
    XCTAssertEqual(tracker.sessions[0].name, "My Session")
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter SessionTrackerTests`
Expected: FAIL — `value of type 'SessionInfo' has no member 'name'`.

- [ ] **Step 3: Implement**

In `SessionInfo` add `var name: String?` (between `cwd` and `state`):

```swift
struct SessionInfo: Identifiable, Equatable {
    let id: String
    var pid: Int?
    var cwd: String?
    var name: String?
    var state: MascotState
    var lastSeen: Date
}
```

In `record(_:)`, update the fallback constructor to pass `name: nil`, and after the `cwd` block add:

```swift
        if let name = event.name {
            info.name = name
        }
```

(The fallback `SessionInfo(...)` initializer call gains `name: nil` to match the new memberwise signature.)

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter SessionTrackerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/SessionTracker.swift Tests/ClaudeerTests/SessionTrackerTests.swift
git commit -m "feat: track last auto session name in SessionInfo"
```

---

### Task 2: `customNames` + `displayName` resolution

**Files:**
- Modify: `Sources/Claudeer/SessionTracker.swift`
- Test: `Tests/ClaudeerTests/SessionTrackerTests.swift`

**Interfaces:**
- Consumes: `SessionInfo.name` (Task 1).
- Produces: `@Published customNames: [String:String]`; `setCustomName(_:for:)`, `customName(for:) -> String?`, `displayName(for:) -> String?`.

- [ ] **Step 1: Write failing tests**

```swift
func testSetCustomNameAndResolve() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
    tracker.setCustomName("Custom", for: "abc")
    XCTAssertEqual(tracker.customName(for: "abc"), "Custom")
    XCTAssertEqual(tracker.displayName(for: "abc"), "Custom")  // custom wins
}

func testDisplayNameFallsBackToAutoName() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
    XCTAssertEqual(tracker.displayName(for: "abc"), "Auto")
    XCTAssertNil(tracker.customName(for: "abc"))
}

func testEmptyCustomNameRevertsToAuto() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
    tracker.setCustomName("Custom", for: "abc")
    tracker.setCustomName("   ", for: "abc")          // whitespace clears
    XCTAssertNil(tracker.customName(for: "abc"))
    XCTAssertEqual(tracker.displayName(for: "abc"), "Auto")
}

func testCustomNameIsTrimmed() {
    let tracker = SessionTracker()
    tracker.setCustomName("  Custom  ", for: "abc")
    XCTAssertEqual(tracker.customName(for: "abc"), "Custom")
}

func testRecordDoesNotClearCustomName() {
    let tracker = SessionTracker()
    tracker.setCustomName("Custom", for: "abc")
    tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 1, cwd: "/p", name: "Auto"))
    XCTAssertEqual(tracker.displayName(for: "abc"), "Custom")  // event name ignored
}

func testDisplayNameNilWhenNothingKnown() {
    let tracker = SessionTracker()
    XCTAssertNil(tracker.displayName(for: "unknown"))
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter SessionTrackerTests`
Expected: FAIL — `value of type 'SessionTracker' has no member 'setCustomName'`.

- [ ] **Step 3: Implement**

After `@Published private(set) var hiddenSessionIDs`, add:

```swift
    @Published private(set) var customNames: [String: String] = [:]
```

Add methods (near `hide`/`show`):

```swift
    func setCustomName(_ name: String?, for id: String) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            customNames.removeValue(forKey: id)
        } else {
            customNames[id] = trimmed
        }
    }

    func customName(for id: String) -> String? {
        customNames[id]
    }

    /// The label to show for a session: custom name if set, else the last auto name.
    func displayName(for id: String) -> String? {
        customNames[id] ?? sessionMap[id]?.name
    }
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter SessionTrackerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/SessionTracker.swift Tests/ClaudeerTests/SessionTrackerTests.swift
git commit -m "feat: SessionTracker custom names with displayName resolution"
```

---

### Task 3: Prune clears custom names

**Files:**
- Modify: `Sources/Claudeer/SessionTracker.swift`
- Test: `Tests/ClaudeerTests/SessionTrackerTests.swift`

**Interfaces:**
- Consumes: `customNames` (Task 2), existing `pruneDeadProcesses`.

- [ ] **Step 1: Write failing test**

```swift
func testPruneRemovesCustomNameForDeadSession() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "dead", pid: 200, cwd: nil, name: "Auto"))
    tracker.setCustomName("Custom", for: "dead")

    _ = tracker.pruneDeadProcesses(isAlive: { _ in false })

    XCTAssertNil(tracker.customName(for: "dead"))
    XCTAssertTrue(tracker.customNames.isEmpty)
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter SessionTrackerTests`
Expected: FAIL — custom name still present after prune.

- [ ] **Step 3: Implement**

In `pruneDeadProcesses`, inside the existing `for info in pruned` loop, alongside `hiddenSessionIDs.remove(info.id)` add:

```swift
                customNames.removeValue(forKey: info.id)
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter SessionTrackerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/SessionTracker.swift Tests/ClaudeerTests/SessionTrackerTests.swift
git commit -m "feat: drop custom names for pruned dead sessions"
```

---

### Task 4: EventManager resolves names through the tracker

**Files:**
- Modify: `Sources/Claudeer/EventManager.swift`
- Test: `Tests/ClaudeerTests/EventManagerTests.swift`

**Interfaces:**
- Consumes: `SessionTracker.displayName(for:)`, `customName(for:)`.
- Produces: `static func notificationTitle(customName:eventName:sessionId:) -> String`.

- [ ] **Step 1: Write failing tests**

```swift
func testNotificationTitlePrefersCustomName() {
    XCTAssertEqual(
        EventManager.notificationTitle(customName: "Custom", eventName: "Auto", sessionId: "abcdef123"),
        "Custom")
}

func testNotificationTitleFallsBackToEventName() {
    XCTAssertEqual(
        EventManager.notificationTitle(customName: nil, eventName: "Auto", sessionId: "abcdef123"),
        "Auto")
}

func testNotificationTitleFallsBackToShortId() {
    XCTAssertEqual(
        EventManager.notificationTitle(customName: "   ", eventName: nil, sessionId: "abcdef123456"),
        "abcdef12")
}
```

- [ ] **Step 2: Run, verify fail**

Run: `swift test --filter EventManagerTests`
Expected: FAIL — no static `notificationTitle(customName:eventName:sessionId:)`.

- [ ] **Step 3: Implement**

Add the static pure helper near `shouldNotifyIdle`:

```swift
    /// Push/label title: custom name, else the event's auto name, else a short id.
    static func notificationTitle(customName: String?, eventName: String?, sessionId: String) -> String {
        if let c = customName?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
            return c
        }
        if let n = eventName?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        return String(sessionId.prefix(8))
    }
```

Replace the existing private `notificationTitle(for:)` body with:

```swift
    private func notificationTitle(for event: SpeakiEvent) -> String {
        Self.notificationTitle(
            customName: sessionTracker.customName(for: event.sessionId),
            eventName: event.name,
            sessionId: event.sessionId
        )
    }
```

In `handleEvent`, change the name line to resolve through the tracker (it runs *after* `record`):

```swift
        mascot.setName(sessionTracker.displayName(for: event.sessionId))
```

- [ ] **Step 4: Run, verify pass**

Run: `swift test --filter EventManagerTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/EventManager.swift Tests/ClaudeerTests/EventManagerTests.swift
git commit -m "feat: resolve mascot + push names through SessionTracker"
```

---

### Task 5: Right-click "Rename…" → native dialog

**Files:**
- Modify: `Sources/Claudeer/Mascot.swift` (add `currentName`)
- Modify: `Sources/Claudeer/InteractionController.swift` (menu item + callback)
- Modify: `Sources/Claudeer/main.swift` (NSAlert wiring)

**Interfaces:**
- Consumes: `SessionTracker.setCustomName`, `displayName` (Tasks 2); `Mascot.setName`.
- Produces: `Mascot.currentName: String`; `InteractionController.onMascotRenameRequested: ((Mascot) -> Void)?`.

This task is AppKit UI (modal dialog + menu), not unit-tested — consistent with the existing hide flow. Verified manually in Task 7.

- [ ] **Step 1: `Mascot.currentName`**

In `Mascot.swift`, after the `globalFrame` computed property:

```swift
    /// The label text currently shown (custom/auto/short-id), for pre-filling the rename dialog.
    var currentName: String { displayName }
```

- [ ] **Step 2: InteractionController — callback + menu item**

Add near `onMascotHideRequested`:

```swift
    /// Called when the user picks "Rename…" from a mascot's right-click menu.
    var onMascotRenameRequested: ((Mascot) -> Void)?
```

In `interactionRightMouseDown`, build the menu with Rename above Hide (replace the single-item construction):

```swift
        rightClickedMascot = target
        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: "Rename…",
            action: #selector(renameClickedMascot),
            keyEquivalent: ""
        )
        renameItem.target = self
        menu.addItem(renameItem)

        menu.addItem(.separator())

        let item = NSMenuItem(
            title: "Hide this character",
            action: #selector(hideClickedMascot),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)

        let viewPoint = view.convert(locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: view)
```

Add the action (near `hideClickedMascot`):

```swift
    @objc private func renameClickedMascot() {
        guard let mascot = rightClickedMascot else { return }
        onMascotRenameRequested?(mascot)
        rightClickedMascot = nil
    }
```

- [ ] **Step 3: main.swift — wire the NSAlert**

Where `interactionController.onMascotHideRequested` is set, add (use the same `sessionTracker` reference that wiring uses):

```swift
interactionController.onMascotRenameRequested = { [weak sessionTracker] mascot in
    let alert = NSAlert()
    alert.messageText = "Rename character"
    alert.informativeText = "Set a custom name for this session's label."
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")

    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    field.stringValue = mascot.currentName
    field.placeholderString = "Leave empty for the automatic name"
    alert.accessoryView = field
    alert.window.initialFirstResponder = field

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    sessionTracker?.setCustomName(field.stringValue, for: mascot.sessionID)
    mascot.setName(sessionTracker?.displayName(for: mascot.sessionID))
}
```

(If `main.swift` names the tracker differently, match the existing identifier; confirm by reading the `onMascotHideRequested` wiring.)

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Builds clean.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/Mascot.swift Sources/Claudeer/InteractionController.swift Sources/Claudeer/main.swift
git commit -m "feat: right-click Rename… opens a dialog to set a custom label"
```

---

### Task 6: Menu bar row reflects the custom name

**Files:**
- Modify: `Sources/Claudeer/MenuBarController.swift`

**Interfaces:**
- Consumes: `SessionTracker.customName(for:)` (`@Published customNames` drives the refresh).

- [ ] **Step 1: Pass the custom name into the row**

In `sessionsSection`'s `ForEach`, add the `customName` argument:

```swift
                ForEach(sessionTracker.sessions) { session in
                    SessionRow(
                        session: session,
                        customName: sessionTracker.customName(for: session.id),
                        isHidden: sessionTracker.isHidden(session.id),
                        onToggleHidden: { sessionTracker.toggleHidden(session.id) }
                    )
                }
```

- [ ] **Step 2: Prefer the custom name in `SessionRow`**

Add the stored property and update `label`:

```swift
private struct SessionRow: View {
    let session: SessionInfo
    let customName: String?
    let isHidden: Bool
    let onToggleHidden: () -> Void
```

```swift
    private var label: String {
        if let custom = customName, !custom.isEmpty { return custom }
        if let cwd = session.cwd, let last = cwd.split(separator: "/").last {
            return String(last)
        }
        return String(session.id.prefix(8))
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Builds clean.

- [ ] **Step 4: Commit**

```bash
git add Sources/Claudeer/MenuBarController.swift
git commit -m "feat: menu bar session row shows the custom name"
```

---

### Task 7: Full test, version bump, manual verify

**Files:**
- Modify: `.claude-plugin/plugin.json`

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all suites PASS.

- [ ] **Step 2: Bump plugin version**

In `.claude-plugin/plugin.json`, `version` `0.8.0` → `0.9.0`.

- [ ] **Step 3: Manual verify** (per the verifying-claudeer-app memory)

1. Launch the release build; socket-spawn a session → mascot shows the auto name.
2. Right-click → "Rename…" → type "Frontend" → OK → `screencapture` shows pill = "Frontend"; menu bar row = "Frontend".
3. Send an idle→working event to that session → name stays "Frontend".
4. Right-click → "Rename…" → clear the field → OK → pill reverts to the auto name.

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "chore: bump plugin version to 0.9.0 for label rename"
```

---

## Self-Review

- **Spec coverage:** custom-name precedence (Task 2/4), instant revert via stored auto name (Task 1/2), prune cleanup (Task 3), right-click dialog (Task 5), ntfy title (Task 4), popover consistency (Task 6), in-memory/no-config (no Config task), version bump (Task 7). All spec sections mapped.
- **Placeholder scan:** none — every code step has concrete code; the one conditional ("if main.swift names the tracker differently") instructs matching an existing identifier confirmed at edit time.
- **Type consistency:** `customNames` / `setCustomName(_:for:)` / `customName(for:)` / `displayName(for:)` / `SessionInfo.name` / `Mascot.currentName` / `onMascotRenameRequested` / static `notificationTitle(customName:eventName:sessionId:)` used identically across tasks.
