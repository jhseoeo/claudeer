import AppKit

class SoundPlayer {
    private var sounds: [MascotState: NSSound] = [:]
    var volume: Float = 1.0

    func loadSounds(from directory: URL) {
        sounds.removeAll()
        let extensions = ["wav", "mp3", "aiff", "m4a"]
        for state in MascotState.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(state.rawValue).\(ext)")
                if let sound = NSSound(contentsOf: url, byReference: false) {
                    sounds[state] = sound
                    break
                }
            }
        }
    }

    func play(for state: MascotState) {
        guard let sound = sounds[state] else { return }
        sound.volume = volume
        sound.play()
    }
}
