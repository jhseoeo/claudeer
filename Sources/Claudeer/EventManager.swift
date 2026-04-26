import AppKit

class EventManager {
    private let characterController: CharacterController
    private let soundPlayer: SoundPlayer
    private let speechBubble: SpeechBubbleView
    private let spriteEngine: SpriteEngine
    let sessionTracker: SessionTracker
    var config: SpeakiConfig

    private var currentState: MascotState = .idle
    private var pidCheckTimer: Timer?

    init(
        characterController: CharacterController,
        soundPlayer: SoundPlayer,
        speechBubble: SpeechBubbleView,
        spriteEngine: SpriteEngine,
        sessionTracker: SessionTracker,
        config: SpeakiConfig
    ) {
        self.characterController = characterController
        self.soundPlayer = soundPlayer
        self.speechBubble = speechBubble
        self.spriteEngine = spriteEngine
        self.sessionTracker = sessionTracker
        self.config = config
    }

    func handleEvent(_ event: SpeakiEvent) {
        sessionTracker.record(event)
        applyTransition(to: event.state)
    }

    /// Re-evaluate loop playback for the current state. Call after app start
    /// and after config/asset hot reload, so toggling Loop or swapping a sound
    /// file takes effect without waiting for a state transition.
    func syncLoop() {
        if config.loops.value(for: currentState) {
            soundPlayer.play(for: currentState, loop: true)
        } else {
            soundPlayer.stopLoop()
        }
    }

    private func applyTransition(to newState: MascotState) {
        guard newState != currentState else { return }
        currentState = newState
        characterController.transitionTo(newState)
        soundPlayer.play(for: newState, loop: config.loops.value(for: newState))

        let speech: String
        switch newState {
        case .idle: speech = config.speeches.idle
        case .working: speech = config.speeches.working
        }

        let spritePos = spriteEngine.position
        let aboveSprite = NSPoint(
            x: spritePos.x + spriteEngine.size.width / 2,
            y: spritePos.y + spriteEngine.size.height
        )
        speechBubble.show(text: speech, above: aboveSprite)
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
        if !pruned.isEmpty && currentState == .working && !sessionTracker.anyWorking {
            applyTransition(to: .idle)
        }
    }
}
