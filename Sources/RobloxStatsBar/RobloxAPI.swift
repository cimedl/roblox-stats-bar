import Foundation

struct RobloxGameStat: Decodable {
    let id: Int64
    let rootPlaceId: Int64?
    let name: String
    let creator: RobloxCreator?
    let playing: Int?
    let visits: Int?
    let favoritedCount: Int?
    let price: Int?
    let created: String?
    let updated: String?
}

struct RobloxCreator: Decodable {
    let id: Int64?
    let name: String?
    let type: String?
}

struct RobloxStatsSnapshot {
    let capturedAt: Date
    let games: [RobloxGameStat]
    let dashboardMetrics: [MetricSourceStatus]

    var totalCCU: Int {
        games.reduce(0) { $0 + ($1.playing ?? 0) }
    }

    var totalVisits: Int {
        games.reduce(0) { $0 + ($1.visits ?? 0) }
    }

    var totalFavorites: Int {
        games.reduce(0) { $0 + ($1.favoritedCount ?? 0) }
    }
}

struct MetricSourceStatus {
    let title: String
    let status: String
    let source: String
    let detail: String
    let value: String?
    let series: [Double]

    init(title: String, status: String, source: String, detail: String, value: String? = nil, series: [Double] = []) {
        self.title = title
        self.status = status
        self.source = source
        self.detail = detail
        self.value = value
        self.series = series
    }
}

enum RobloxAPIError: LocalizedError {
    case invalidInput
    case invalidResponse
    case noUniverseForPlace(Int64)
    case robloxStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Enter a universe ID or a Roblox game URL."
        case .invalidResponse:
            return "Roblox returned an unexpected response."
        case .noUniverseForPlace(let placeId):
            return "Could not resolve place \(placeId) to a universe."
        case .robloxStatus(let status):
            return "Roblox API returned HTTP \(status)."
        }
    }
}

final class RobloxAPI {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func loadSnapshot(universeIds: [Int64], completion: @escaping (Result<RobloxStatsSnapshot, Error>) -> Void) {
        let uniqueIds = Array(Set(universeIds)).sorted()
        guard !uniqueIds.isEmpty else {
            completion(.success(RobloxStatsSnapshot(
                capturedAt: Date(),
                games: [],
                dashboardMetrics: RobloxAPI.dashboardMetricStatuses()
            )))
            return
        }

        let chunks = stride(from: 0, to: uniqueIds.count, by: 50).map {
            Array(uniqueIds[$0..<min($0 + 50, uniqueIds.count)])
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loadedGames: [RobloxGameStat] = []
        var firstError: Error?

        for chunk in chunks {
            group.enter()
            fetchGameDetails(universeIds: chunk) { result in
                lock.lock()
                switch result {
                case .success(let games):
                    loadedGames.append(contentsOf: games)
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if let firstError {
                completion(.failure(firstError))
                return
            }

            let sortedGames = loadedGames.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            completion(.success(RobloxStatsSnapshot(
                capturedAt: Date(),
                games: sortedGames,
                dashboardMetrics: RobloxAPI.dashboardMetricStatuses()
            )))
        }
    }

    func resolveUniverseId(from input: String, completion: @escaping (Result<Int64, Error>) -> Void) {
        switch parse(input: input) {
        case .universeId(let universeId):
            completion(.success(universeId))
        case .placeId(let placeId):
            resolveUniverseId(placeId: placeId, completion: completion)
        case .none:
            completion(.failure(RobloxAPIError.invalidInput))
        }
    }

    private func fetchGameDetails(universeIds: [Int64], completion: @escaping (Result<[RobloxGameStat], Error>) -> Void) {
        let joinedIds = universeIds.map(String.init).joined(separator: ",")
        guard let url = URL(string: "https://games.roblox.com/v1/games?universeIds=\(joinedIds)") else {
            completion(.failure(RobloxAPIError.invalidInput))
            return
        }

        request(url: url) { (result: Result<GameDetailsResponse, Error>) in
            completion(result.map(\.data))
        }
    }

    private func resolveUniverseId(placeId: Int64, completion: @escaping (Result<Int64, Error>) -> Void) {
        guard let url = URL(string: "https://apis.roblox.com/universes/v1/places/\(placeId)/universe") else {
            completion(.failure(RobloxAPIError.invalidInput))
            return
        }

        request(url: url) { (result: Result<PlaceUniverseResponse, Error>) in
            switch result {
            case .success(let response):
                completion(.success(response.universeId))
            case .failure:
                completion(.failure(RobloxAPIError.noUniverseForPlace(placeId)))
            }
        }
    }

    private func request<T: Decodable>(url: URL, completion: @escaping (Result<T, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("RobloxStatsBar/0.1", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                completion(.failure(RobloxAPIError.robloxStatus(httpResponse.statusCode)))
                return
            }

            guard let data else {
                completion(.failure(RobloxAPIError.invalidResponse))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func parse(input: String) -> ParsedGameInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let directId = Int64(trimmed), directId > 0 {
            return .universeId(directId)
        }

        if let components = URLComponents(string: trimmed) {
            if let universe = components.queryItems?.first(where: { $0.name.lowercased() == "universeid" })?.value,
               let universeId = Int64(universe), universeId > 0 {
                return .universeId(universeId)
            }

            let pathParts = components.path
                .split(separator: "/")
                .map(String.init)

            if let experiencesIndex = pathParts.firstIndex(where: { $0.lowercased() == "experiences" }),
               pathParts.indices.contains(experiencesIndex + 1),
               let universeId = Int64(pathParts[experiencesIndex + 1]),
               universeId > 0 {
                return .universeId(universeId)
            }

            if let gamesIndex = pathParts.firstIndex(where: { $0.lowercased() == "games" }),
               pathParts.indices.contains(gamesIndex + 1),
               let placeId = Int64(pathParts[gamesIndex + 1]),
               placeId > 0 {
                return .placeId(placeId)
            }
        }

        let digits = trimmed.filter(\.isNumber)
        if trimmed.contains("roblox.com/games"), let placeId = Int64(digits), placeId > 0 {
            return .placeId(placeId)
        }

        return nil
    }

    private static func dashboardMetricStatuses() -> [MetricSourceStatus] {
        DashboardMetricKey.allCases.map {
            MetricSourceStatus(title: $0.title, status: "Pending", source: "Creator Hub", detail: "Analytics source needed")
        }
    }
}

private enum ParsedGameInput {
    case universeId(Int64)
    case placeId(Int64)
}

private struct GameDetailsResponse: Decodable {
    let data: [RobloxGameStat]
}

private struct PlaceUniverseResponse: Decodable {
    let universeId: Int64
}
