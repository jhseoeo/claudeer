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

struct SpeakiConfig: Codable {
    let defaultArea: String
    let speeches: Speeches
    let loops: LoopSettings

    enum CodingKeys: String, CodingKey {
        case defaultArea = "default_area"
        case speeches
        case loops
    }

    init(defaultArea: String, speeches: Speeches, loops: LoopSettings) {
        self.defaultArea = defaultArea
        self.speeches = speeches
        self.loops = loops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.defaultArea = try container.decode(String.self, forKey: .defaultArea)
        self.speeches = try container.decode(Speeches.self, forKey: .speeches)
        self.loops = try container.decodeIfPresent(LoopSettings.self, forKey: .loops) ?? .off
    }

    static let `default` = SpeakiConfig(
        defaultArea: "bottom",
        speeches: Speeches(
            idle: "Need your input!",
            working: "On it!"
        ),
        loops: .off
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
