import Foundation

struct Speeches: Codable {
    let idle: String
    let working: String
}

struct LoopSettings: Codable {
    let idle: Bool
    let working: Bool

    func value(for state: MascotState) -> Bool {
        switch state {
        case .idle: return idle
        case .working: return working
        }
    }

    static let off = LoopSettings(idle: false, working: false)
}

struct MovementSettings: Codable {
    let idle: Bool
    let working: Bool

    func value(for state: MascotState) -> Bool {
        switch state {
        case .idle: return idle
        case .working: return working
        }
    }

    static let allOn = MovementSettings(idle: true, working: true)
}

struct FlipSettings: Codable {
    let directional: Bool
    let mirrored: Bool

    static let off = FlipSettings(directional: false, mirrored: false)
}

struct SpeakiConfig: Codable {
    let defaultArea: String
    let speeches: Speeches
    let loops: LoopSettings
    let movements: MovementSettings
    let speed: Double
    let flips: FlipSettings

    static let defaultSpeed: Double = 2.0
    static let speedRange: ClosedRange<Double> = 0.5...6.0

    enum CodingKeys: String, CodingKey {
        case defaultArea = "default_area"
        case speeches
        case loops
        case movements
        case speed
        case flips
    }

    init(defaultArea: String, speeches: Speeches, loops: LoopSettings, movements: MovementSettings, speed: Double, flips: FlipSettings) {
        self.defaultArea = defaultArea
        self.speeches = speeches
        self.loops = loops
        self.movements = movements
        self.speed = speed
        self.flips = flips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultArea = try container.decode(String.self, forKey: .defaultArea)
        self.speeches = try container.decode(Speeches.self, forKey: .speeches)
        self.loops = try container.decodeIfPresent(LoopSettings.self, forKey: .loops) ?? .off
        self.movements = try container.decodeIfPresent(MovementSettings.self, forKey: .movements) ?? .allOn
        self.speed = try container.decodeIfPresent(Double.self, forKey: .speed) ?? Self.defaultSpeed
        self.flips = try container.decodeIfPresent(FlipSettings.self, forKey: .flips) ?? .off
    }

    static let `default` = SpeakiConfig(
        defaultArea: "bottom",
        speeches: Speeches(
            idle: "Need your input!",
            working: "On it!"
        ),
        loops: .off,
        movements: .allOn,
        speed: defaultSpeed,
        flips: .off
    )

    static func load(from url: URL) -> SpeakiConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(SpeakiConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url)
    }
}
