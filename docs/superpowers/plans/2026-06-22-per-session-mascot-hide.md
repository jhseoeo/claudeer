# Per-Session Mascot Hide/Show Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user hide an individual session's mascot (right-click → "Hide this character") and restore it from a per-row eye toggle in the menu bar sessions list.

**Architecture:** Hidden state is a `@Published Set<String>` of session ids owned by `SessionTracker` (already observed by the menu bar). `main.swift` subscribes to it and pushes the set into `MascotManager.setHidden`, which flips each `Mascot`'s view visibility and pauses its movement. Right-click hide and the menu bar toggle are two entry points that both mutate the same set.

**Tech Stack:** Swift, AppKit (overlay/sprite/menu), SwiftUI (menu bar popover), Combine (`@Published` → `sink`), XCTest.

## Global Constraints

- Pure Swift stdlib + Apple frameworks only — **no new external packages** (AppKit, SwiftUI, Combine, Foundation are already in use).
- All UI/state mutations happen on the **main thread** (events already dispatch to main before touching UI).
- Hidden state is **in-memory only** — no `config.json` / `Config.swift` change, no persistence across restart.
- Follow existing patterns: closure callbacks for interaction events (mirror `onMascotDoubleClicked`); `@Published` on `SessionTracker` for menu bar reactivity.
- UI strings are English to match the existing menu ("Preferences...", "Quit"): menu item is exactly `"Hide this character"`.
- Socket path `/tmp/claudeer.sock` is unchanged.

---

### Task 1: Hidden-state model on `SessionTracker`

**Files:**
- Modify: `Sources/Claudeer/SessionTracker.swift`
- Test: `Tests/ClaudeerTests/SessionTrackerTests.swift`

**Interfaces:**
- Consumes: existing `SessionTracker.record(_:)`, `pruneDeadProcesses(isAlive:)`, `SpeakiEvent(state:sessionId:pid:cwd:)`.
- Produces: `@Published private(set) var hiddenSessionIDs: Set<String>`; `func hide(_ id: String)`, `func show(_ id: String)`, `func toggleHidden(_ id: String)`, `func isHidden(_ id: String) -> Bool`. `record(_:)` leaves `hiddenSessionIDs` untouched (sticky). `pruneDeadProcesses` removes pruned ids from `hiddenSessionIDs`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeerTests/SessionTrackerTests.swift`, inside the `SessionTrackerTests` class:

```swift
func testHideShowToggleAndIsHidden() {
    let tracker = SessionTracker()
    XCTAssertFalse(tracker.isHidden("a"))

    tracker.hide("a")
    XCTAssertTrue(tracker.isHidden("a"))
    XCTAssertEqual(tracker.hiddenSessionIDs, ["a"])

    tracker.show("a")
    XCTAssertFalse(tracker.isHidden("a"))

    tracker.toggleHidden("a")
    XCTAssertTrue(tracker.isHidden("a"))
    tracker.toggleHidden("a")
    XCTAssertFalse(tracker.isHidden("a"))
}

func testRecordDoesNotClearHiddenState() {
    let tracker = SessionTracker()
    tracker.hide("abc")
    // A new event for a hidden session must NOT un-hide it (sticky).
    tracker.record(SpeakiEvent(state: .working, sessionId: "abc", pid: 100, cwd: "/p"))
    XCTAssertTrue(tracker.isHidden("abc"))
}

func testPruneRemovesHiddenStateForDeadSession() {
    let tracker = SessionTracker()
    tracker.record(SpeakiEvent(state: .idle, sessionId: "dead", pid: 200, cwd: nil))
    tracker.hide("dead")

    _ = tracker.pruneDeadProcesses(isAlive: { _ in false })

    XCTAssertFalse(tracker.isHidden("dead"))
    XCTAssertTrue(tracker.hiddenSessionIDs.isEmpty)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTrackerTests 2>&1 | tail -20`
Expected: compile failure — `value of type 'SessionTracker' has no member 'hide'` / `hiddenSessionIDs`.

- [ ] **Step 3: Add the hidden-state API**

In `Sources/Claudeer/SessionTracker.swift`, add the published property next to the existing `@Published private(set) var sessions`:

```swift
@Published private(set) var hiddenSessionIDs: Set<String> = []
```

Add these methods inside the `SessionTracker` class (e.g. after `cwd(for:)`):

```swift
func hide(_ id: String) {
    hiddenSessionIDs.insert(id)
}

func show(_ id: String) {
    hiddenSessionIDs.remove(id)
}

func toggleHidden(_ id: String) {
    if hiddenSessionIDs.contains(id) {
        hiddenSessionIDs.remove(id)
    } else {
        hiddenSessionIDs.insert(id)
    }
}

func isHidden(_ id: String) -> Bool {
    hiddenSessionIDs.contains(id)
}
```

- [ ] **Step 4: Drop hidden ids on prune**

In `pruneDeadProcesses(isAlive:)`, replace the existing `if !pruned.isEmpty { publishSessions() }` block with:

```swift
if !pruned.isEmpty {
    for info in pruned {
        hiddenSessionIDs.remove(info.id)
    }
    publishSessions()
}
```

(`record(_:)` is intentionally left unchanged — that is what keeps hide sticky.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionTrackerTests 2>&1 | tail -20`
Expected: all `SessionTrackerTests` pass (existing + 3 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/Claudeer/SessionTracker.swift Tests/ClaudeerTests/SessionTrackerTests.swift
git commit -m "feat: track per-session hidden state in SessionTracker"
```

---

### Task 2: `Mascot.setHidden` + `CharacterController` pause

**Files:**
- Modify: `Sources/Claudeer/CharacterController.swift`
- Modify: `Sources/Claudeer/Mascot.swift`

**Interfaces:**
- Consumes: `SpriteEngine.view` (`NSView`), `SpeechBubbleView.dismiss()`, `Mascot.updateLabelVisibility()`, `Mascot.layoutNameLabel()` (existing private methods).
- Produces: `CharacterController.setPaused(_ paused: Bool)`; `Mascot.isHidden` (`private(set) var`), `Mascot.setHidden(_ hidden: Bool)`. A hidden mascot's `applyTransition` updates internal state but shows no speech bubble.

- [ ] **Step 1: Add a pause gate to `CharacterController`**

In `Sources/Claudeer/CharacterController.swift`, add the flag next to the other state flags (after `private var isDragging = false`):

```swift
private var isPaused = false
```

Add the setter (e.g. after `setBeingDragged`):

```swift
func setPaused(_ paused: Bool) {
    isPaused = paused
    if paused {
        isMoving = false
    }
}
```

Update the guard at the top of `tick()` from `if isFrozen || isDragging { return }` to:

```swift
if isPaused || isFrozen || isDragging { return }
```

- [ ] **Step 2: Add `isHidden` + `setHidden` to `Mascot`**

In `Sources/Claudeer/Mascot.swift`, add the property near the other stored properties (after `private var showLabel = true`):

```swift
private(set) var isHidden = false
```

Add the method (e.g. after `setLabelVisible`):

```swift
func setHidden(_ hidden: Bool) {
    guard hidden != isHidden else { return }
    isHidden = hidden
    spriteEngine.view.isHidden = hidden
    if hidden {
        speechBubble.dismiss()
        nameLabel.isHidden = true
        characterController.setPaused(true)
    } else {
        characterController.setPaused(false)
        updateLabelVisibility()
        layoutNameLabel()
    }
}
```

- [ ] **Step 3: Suppress the speech bubble while hidden**

In `Mascot.applyTransition(to:speech:)`, after the line `characterController.transitionTo(newState)` and before the `let pos = spriteEngine.position` line, insert:

```swift
        guard !isHidden else { return }
```

So a hidden mascot still updates its sprite/state but renders no bubble.

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Compiling` … `Build complete!` with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/CharacterController.swift Sources/Claudeer/Mascot.swift
git commit -m "feat: Mascot.setHidden hides sprite/label and pauses movement"
```

---

### Task 3: `MascotManager.setHidden` + reactive wiring

**Files:**
- Modify: `Sources/Claudeer/MascotManager.swift`
- Modify: `Sources/Claudeer/main.swift`

**Interfaces:**
- Consumes: `Mascot.setHidden(_:)` (Task 2), `SessionTracker.$hiddenSessionIDs` (Task 1), existing `cancellables` set in `AppDelegate`.
- Produces: `MascotManager.setHidden(_ ids: Set<String>)`. After this task, mutating `sessionTracker.hiddenSessionIDs` hides/shows the matching mascot live.

- [ ] **Step 1: Add `setHidden` to `MascotManager`**

In `Sources/Claudeer/MascotManager.swift`, add (e.g. after `setAreas`):

```swift
func setHidden(_ ids: Set<String>) {
    for mascot in mascots.values {
        mascot.setHidden(ids.contains(mascot.sessionID))
    }
}
```

- [ ] **Step 2: Subscribe to hidden-state changes in `main.swift`**

In `Sources/Claudeer/main.swift`, immediately after the existing `sessionTracker.$sessions.sink { … }.store(in: &cancellables)` block, add:

```swift
        sessionTracker.$hiddenSessionIDs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.mascotManager?.setHidden(ids)
            }
            .store(in: &cancellables)
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/Claudeer/MascotManager.swift Sources/Claudeer/main.swift
git commit -m "feat: apply hidden session set to mascots reactively"
```

---

### Task 4: Right-click "Hide this character" context menu

**Files:**
- Modify: `Sources/Claudeer/InteractionView.swift`
- Modify: `Sources/Claudeer/InteractionController.swift`
- Modify: `Sources/Claudeer/main.swift`

**Interfaces:**
- Consumes: `Mascot.isHidden` (Task 2), `SessionTracker.hide(_:)` (Task 1), existing `mascotManager.allMascots`, `globalPoint(_:in:)`.
- Produces: `InteractionViewDelegate.interactionRightMouseDown(at:in:)`; `InteractionController.onMascotHideRequested: ((Mascot) -> Void)?`. Hidden mascots are excluded from hover/drag/right-click hit-testing.

- [ ] **Step 1: Forward right-clicks from `InteractionView`**

In `Sources/Claudeer/InteractionView.swift`, add to the `InteractionViewDelegate` protocol:

```swift
    func interactionRightMouseDown(at locationInWindow: NSPoint, in view: InteractionView)
```

Add the override in `InteractionView` (after `mouseUp`):

```swift
    override func rightMouseDown(with event: NSEvent) {
        delegate?.interactionRightMouseDown(at: event.locationInWindow, in: self)
    }
```

- [ ] **Step 2: Make `InteractionController` an `NSObject` (needed for menu target/action)**

In `Sources/Claudeer/InteractionController.swift`, change the class declaration:

```swift
class InteractionController: NSObject, InteractionViewDelegate {
```

In `init(overlay:mascotManager:soundPlayer:)`, call `super.init()` before assigning the delegate. The body becomes:

```swift
    init(
        overlay: OverlayWindowController,
        mascotManager: MascotManager,
        soundPlayer: SoundPlayer
    ) {
        self.overlay = overlay
        self.mascotManager = mascotManager
        self.soundPlayer = soundPlayer
        super.init()
        overlay.interactionDelegate = self
    }
```

- [ ] **Step 3: Exclude hidden mascots from hit-testing**

In `Sources/Claudeer/InteractionController.swift`, in `updateCursorHover()`, change the host lookup to skip hidden mascots:

```swift
        let host = mascotManager.allMascots
            .first { !$0.isHidden && $0.globalFrame.contains(mouse) }?
            .spriteEngine.view.window
```

In `interactionMouseDown(at:in:)`, change the target lookup:

```swift
        let target = mascotManager.allMascots.first { !$0.isHidden && $0.globalFrame.contains(global) }
```

- [ ] **Step 4: Add the right-click handler + callback**

In `Sources/Claudeer/InteractionController.swift`, add the callback property near `onMascotDoubleClicked`:

```swift
    /// Called when the user picks "Hide this character" from a mascot's right-click menu.
    var onMascotHideRequested: ((Mascot) -> Void)?
```

Add a stored target for the menu action near the other private vars (after `private weak var activeWindow: NSWindow?`):

```swift
    private weak var rightClickedMascot: Mascot?
```

Add the delegate method and action (e.g. after `interactionMouseUp`):

```swift
    func interactionRightMouseDown(at locationInWindow: NSPoint, in view: InteractionView) {
        guard let global = globalPoint(locationInWindow, in: view) else { return }
        guard let target = mascotManager.allMascots.first(where: {
            !$0.isHidden && $0.globalFrame.contains(global)
        }) else { return }

        rightClickedMascot = target
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Hide this character",
            action: #selector(hideClickedMascot),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        let viewPoint = view.convert(locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: view)
    }

    @objc private func hideClickedMascot() {
        guard let mascot = rightClickedMascot else { return }
        onMascotHideRequested?(mascot)
        rightClickedMascot = nil
    }
```

- [ ] **Step 5: Wire the callback in `main.swift`**

In `Sources/Claudeer/main.swift`, immediately after the existing `interactionController?.onMascotDoubleClicked = { … }` assignment, add:

```swift
        interactionController?.onMascotHideRequested = { mascot in
            sessionTracker.hide(mascot.sessionID)
        }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no errors.

- [ ] **Step 7: Manual verification (right-click hides)**

Reference the `verifying-claudeer-app` memory for the spawn/screencapture procedure. Concretely:

```bash
# 1. Run the app
.build/debug/Claudeer &

# 2. Spawn two sessions with REAL, long-lived pids (so prune won't remove them)
sleep 600 & P1=$!
sleep 600 & P2=$!
for P in $P1 $P2; do
  python3 -c "import socket,json,sys; s=socket.socket(socket.AF_UNIX); s.connect('/tmp/claudeer.sock'); s.send(json.dumps({'state':'idle','session_id':'sess-'+sys.argv[1],'pid':int(sys.argv[1])}).encode()+b'\n'); s.close()" $P
done
```

Then visually confirm (allow a moment for the render race per the memory, then `screencapture -R<rect> /tmp/shot.png` and Read it):
- Two mascots are visible.
- Right-click one mascot → a menu with "Hide this character" appears → click it → that mascot disappears, the other keeps roaming.
- The hidden mascot's former spot is no longer draggable (cursor doesn't grab it).

Clean up: `kill $P1 $P2; kill %1` (the app), or quit via the menu bar.

- [ ] **Step 8: Commit**

```bash
git add Sources/Claudeer/InteractionView.swift Sources/Claudeer/InteractionController.swift Sources/Claudeer/main.swift
git commit -m "feat: right-click mascot to hide it"
```

---

### Task 5: Menu bar per-row eye toggle (restore)

**Files:**
- Modify: `Sources/Claudeer/MenuBarController.swift`

**Interfaces:**
- Consumes: `SessionTracker.isHidden(_:)` / `toggleHidden(_:)` (Task 1); the menu bar already holds `sessionTracker` as `@ObservedObject`.
- Produces: per-row eye/eye.slash toggle button in `MenuBarPopoverView`; hidden rows render dimmed.

- [ ] **Step 1: Pass hidden state + toggle into each row**

In `Sources/Claudeer/MenuBarController.swift`, in `MenuBarPopoverView.sessionsSection`, replace the `ForEach` body:

```swift
                ForEach(sessionTracker.sessions) { session in
                    SessionRow(
                        session: session,
                        isHidden: sessionTracker.isHidden(session.id),
                        onToggleHidden: { sessionTracker.toggleHidden(session.id) }
                    )
                }
```

- [ ] **Step 2: Render the eye toggle + dim in `SessionRow`**

In `Sources/Claudeer/MenuBarController.swift`, replace the `private struct SessionRow` definition with:

```swift
private struct SessionRow: View {
    let session: SessionInfo
    let isHidden: Bool
    let onToggleHidden: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: session.state == .working ? "bolt.fill" : "pause.circle")
                .foregroundColor(session.state == .working ? .accentColor : .secondary)
                .frame(width: 12)
            Text(label)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: onToggleHidden) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isHidden ? "Show mascot" : "Hide mascot")
        }
        .opacity(isHidden ? 0.5 : 1.0)
        .help(tooltip)
    }

    private var label: String {
        if let cwd = session.cwd, let last = cwd.split(separator: "/").last {
            return String(last)
        }
        return String(session.id.prefix(8))
    }

    private var tooltip: String {
        var parts: [String] = []
        if let cwd = session.cwd { parts.append("cwd: \(cwd)") }
        if let pid = session.pid { parts.append("pid: \(pid)") }
        parts.append("session: \(session.id)")
        parts.append("state: \(session.state.rawValue)")
        return parts.joined(separator: "\n")
    }
}
```

(Only the three new members — `isHidden`, `onToggleHidden`, and the trailing `Button` + `.opacity` — are additions; `label` and `tooltip` are unchanged from the original.)

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!` with no errors.

- [ ] **Step 4: Manual verification (full hide ↔ show loop)**

Run the app and spawn two sessions as in Task 4 Step 7. Then:
- Open the menu bar popover (🐾). Each session row shows an `eye` icon.
- Click the eye on one row → icon becomes `eye.slash`, row dims, and that mascot disappears from screen.
- Click it again → icon back to `eye`, row un-dims, mascot reappears at its preserved position.
- Right-click the other mascot → "Hide this character" → confirm its menu bar row also dims to `eye.slash` (both entry points drive the same state).
- Send a `working` event to a hidden session (re-run the python one-liner with `'state':'working'` for that pid) → it stays hidden, no speech bubble appears.

Clean up the spawned `sleep` pids and quit the app.

- [ ] **Step 5: Commit**

```bash
git add Sources/Claudeer/MenuBarController.swift
git commit -m "feat: menu bar eye toggle to show/hide each session's mascot"
```

---

## Notes for the Implementer

- **Do not** add persistence — `hiddenSessionIDs` lives only in memory by design.
- **Do not** change `SpriteEngine.spriteExtensions` / `SoundPlayer` — no new asset slots.
- `swift test` requires a full Xcode install (not just Command Line Tools). If `swift test` can't run, still complete Task 1's code; flag that the unit tests are unverified.
- After all tasks, the version bump + final commit/push is the user's call (their convention: bump `.claude-plugin/plugin.json` and push on request) — do not push unprompted.
