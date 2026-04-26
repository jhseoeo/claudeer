import AppKit

class SoundPlayer {
    private var sounds: [EventType: NSSound] = [:]
    var volume: Float = 1.0

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

    func play(for event: EventType) {
        guard let sound = sounds[event] else { return }
        sound.volume = volume
        sound.play()
    }
}
