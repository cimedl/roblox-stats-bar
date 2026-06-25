import Foundation

struct TrackedGame: Codable, Equatable {
    var universeId: Int64
    var displayName: String?
    var enabled: Bool
    var addedAt: Date

    init(universeId: Int64, displayName: String? = nil, enabled: Bool = true, addedAt: Date = Date()) {
        self.universeId = universeId
        self.displayName = displayName
        self.enabled = enabled
        self.addedAt = addedAt
    }
}

struct AppConfig: Codable {
    var refreshIntervalSeconds: TimeInterval
    var games: [TrackedGame]

    init(refreshIntervalSeconds: TimeInterval = 60, games: [TrackedGame] = []) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.games = games
    }
}

final class ConfigStore {
    let configURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configURL = home
            .appendingPathComponent(".config")
            .appendingPathComponent("roblox-stats-bar")
            .appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return AppConfig()
        }

        do {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return AppConfig()
        }
    }

    func save(_ config: AppConfig) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(config)
        try data.write(to: configURL, options: [.atomic])
    }
}
