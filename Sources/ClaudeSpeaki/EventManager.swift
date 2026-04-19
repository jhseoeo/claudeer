import AppKit

class EventManager {
    private let characterController: CharacterController
    private let soundPlayer: SoundPlayer
    private let speechBubble: SpeechBubbleView
    private let spriteEngine: SpriteEngine
    private let config: SpeakiConfig

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
        switch event.event {
        case .sessionStart:
            if let pid = event.pid {
                activeSessions[event.sessionId] = pid
            }
            react(to: event.event)

        case .needInput:
            react(to: event.event)

        case .sessionEnd:
            activeSessions.removeValue(forKey: event.sessionId)
            react(to: event.event)
        }
    }

    private func react(to eventType: EventType) {
        characterController.triggerAlert()
        soundPlayer.play(for: eventType)

        let speech: String
        switch eventType {
        case .sessionStart: speech = config.speeches.sessionStart
        case .needInput: speech = config.speeches.needInput
        case .sessionEnd: speech = config.speeches.sessionEnd
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
                react(to: .sessionEnd)
            }
        }
    }
}
