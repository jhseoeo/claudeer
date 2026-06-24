import AppKit

class EventManager {
    private let mascotManager: MascotManager
    private let soundPlayer: SoundPlayer
    let sessionTracker: SessionTracker
    let notifier: NtfyNotifier
    var config: SpeakiConfig

    private var globalState: MascotState = .idle
    private var pidCheckTimer: Timer?

    init(
        mascotManager: MascotManager,
        soundPlayer: SoundPlayer,
        sessionTracker: SessionTracker,
        notifier: NtfyNotifier,
        config: SpeakiConfig
    ) {
        self.mascotManager = mascotManager
        self.soundPlayer = soundPlayer
        self.sessionTracker = sessionTracker
        self.notifier = notifier
        self.config = config
    }

    /// Whether an incoming event represents a real transition *into* idle for a
    /// session — the moment a speech bubble fires, and when we push to ntfy.
    static func shouldNotifyIdle(previousState: MascotState, eventState: MascotState) -> Bool {
        previousState != eventState && eventState == .idle
    }

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

    func handleEvent(_ event: SpeakiEvent) {
        // A new session_id on an existing pid means the old session on that pid
        // ended (/clear, resume, …); drop its now-orphaned mascot.
        for session in sessionTracker.record(event) {
            mascotManager.removeMascot(sessionID: session.id)
        }
        let mascot = mascotManager.ensureMascot(sessionID: event.sessionId)
        mascot.setName(sessionTracker.displayName(for: event.sessionId))
        let previousState = mascot.state
        mascot.applyTransition(to: event.state, speech: speech(for: event.state))
        if Self.shouldNotifyIdle(previousState: previousState, eventState: event.state) {
            notifier.notify(title: notificationTitle(for: event), body: config.speeches.idle)
        }
        updateGlobalState()
    }

    /// Push title for a session: custom name, else event name, else a short id
    /// (mirrors the on-screen label).
    private func notificationTitle(for event: SpeakiEvent) -> String {
        Self.notificationTitle(
            customName: sessionTracker.customName(for: event.sessionId),
            eventName: event.name,
            sessionId: event.sessionId
        )
    }

    /// Re-evaluate loop playback for the current global state. Call after app
    /// start and after config/asset hot reload, so toggling Loop or swapping
    /// a sound file takes effect without waiting for a state transition.
    func syncLoop() {
        if config.loops.value(for: globalState) {
            soundPlayer.play(for: globalState, loop: true)
        } else {
            soundPlayer.stopLoop()
        }
    }

    func startPIDMonitoring() {
        pidCheckTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.checkActiveSessions()
        }
    }

    func stopPIDMonitoring() {
        pidCheckTimer?.invalidate()
        pidCheckTimer = nil
    }

    private func checkActiveSessions() {
        let pruned = sessionTracker.pruneDeadProcesses()
        for session in pruned {
            mascotManager.removeMascot(sessionID: session.id)
        }
        if !pruned.isEmpty {
            updateGlobalState()
        }
    }

    private func speech(for state: MascotState) -> String {
        switch state {
        case .idle: return config.speeches.idle
        case .working: return config.speeches.working
        }
    }

    private func updateGlobalState() {
        let newState: MascotState = sessionTracker.anyWorking ? .working : .idle
        guard newState != globalState else { return }
        globalState = newState
        soundPlayer.play(for: newState, loop: config.loops.value(for: newState))
    }
}
