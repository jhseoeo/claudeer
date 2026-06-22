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

    func handleEvent(_ event: SpeakiEvent) {
        sessionTracker.record(event)
        let mascot = mascotManager.ensureMascot(sessionID: event.sessionId)
        mascot.setName(event.name)
        let previousState = mascot.state
        mascot.applyTransition(to: event.state, speech: speech(for: event.state))
        if Self.shouldNotifyIdle(previousState: previousState, eventState: event.state) {
            notifier.notify(title: notificationTitle(for: event), body: config.speeches.idle)
        }
        updateGlobalState()
    }

    /// Push title for a session: its name, else a short id (mirrors the label).
    private func notificationTitle(for event: SpeakiEvent) -> String {
        if let name = event.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return String(event.sessionId.prefix(8))
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
