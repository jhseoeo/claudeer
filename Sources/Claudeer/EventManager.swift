import AppKit

class EventManager {
    private let characterController: CharacterController
    private let soundPlayer: SoundPlayer
    private let speechBubble: SpeechBubbleView
    private let spriteEngine: SpriteEngine
    var config: SpeakiConfig

    private var currentState: MascotState = .idle
    private var activeSessions: [String: Int] = [:]
    private var pidCheckTimer: Timer?

    init(
        characterController: CharacterController,
        soundPlayer: SoundPlayer,
        speechBubble: SpeechBubbleView,
        spriteEngine: SpriteEngine,
        config: SpeakiConfig
    ) {
        self.characterController = characterController
        self.soundPlayer = soundPlayer
        self.speechBubble = speechBubble
        self.spriteEngine = spriteEngine
        self.config = config
    }

    func handleEvent(_ event: SpeakiEvent) {
        if let pid = event.pid {
            activeSessions[event.sessionId] = pid
        }
        applyTransition(to: event.state)
    }

    private func applyTransition(to newState: MascotState) {
        guard newState != currentState else { return }
        currentState = newState
        characterController.transitionTo(newState)
        soundPlayer.play(for: newState)

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
        for (sessionId, pid) in activeSessions {
            if kill(Int32(pid), 0) != 0 {
                activeSessions.removeValue(forKey: sessionId)
                applyTransition(to: .idle)
            }
        }
    }
}
