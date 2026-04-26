import Foundation

struct Speeches: Codable {
    let idle: String
    let working: String
}

struct SpeakiConfig: Codable {
    let defaultArea: String
    let speeches: Speeches

    enum CodingKeys: String, CodingKey {
        case defaultArea = "default_area"
        case speeches
    }

    static let `default` = SpeakiConfig(
        defaultArea: "bottom",
        speeches: Speeches(
            idle: "Need your input!",
            working: "On it!"
        )
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
