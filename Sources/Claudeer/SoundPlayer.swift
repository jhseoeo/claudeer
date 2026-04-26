import AppKit

class SoundPlayer {
    private var sounds: [MascotState: NSSound] = [:]
    private var interactionSounds: [InteractionSound: NSSound] = [:]
    private var currentLoopState: MascotState?

    var volume: Float = 1.0 {
        didSet {
            if let state = currentLoopState, let sound = sounds[state] {
                sound.volume = volume
            }
        }
    }

    func loadSounds(from directory: URL) {
        stopLoop()
        sounds.removeAll()
        interactionSounds.removeAll()
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
        for key in InteractionSound.allCases {
            for ext in extensions {
                let url = directory.appendingPathComponent("\(key.rawValue).\(ext)")
                if let sound = NSSound(contentsOf: url, byReference: false) {
                    interactionSounds[key] = sound
                    break
                }
            }
        }
    }

    func play(for state: MascotState, loop: Bool) {
        stopLoop()
        guard let sound = sounds[state] else { return }
        sound.volume = volume
        sound.loops = loop
        sound.play()
        if loop {
            currentLoopState = state
        }
    }

    func playInteraction(_ key: InteractionSound) {
        guard let sound = interactionSounds[key] else { return }
        sound.volume = volume
        sound.loops = false
        sound.stop()
        sound.play()
    }

    func stopLoop() {
        if let state = currentLoopState, let sound = sounds[state] {
            sound.stop()
        }
        currentLoopState = nil
    }
}
