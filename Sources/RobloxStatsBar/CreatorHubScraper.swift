import Foundation

struct CreatorHubScrapeStatus {
    let fetchedCount: Int
    let skippedReason: String?
}

enum CreatorHubScraperError: LocalizedError {
    case invalidCookie
    case invalidResponse
    case robloxStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCookie:
            return "No local Roblox cookie is configured."
        case .invalidResponse:
            return "Creator Hub returned an unexpected response."
        case .robloxStatus(let status):
            return "Creator Hub returned HTTP \(status)."
        }
    }
}

final class CreatorHubScraper {
    private let session: URLSession
    private let metricsStore: DashboardMetricsStore
    private let calendar = Calendar(identifier: .gregorian)
    private let analyticsGatewayBaseURL = URL(string: "https://apis.roblox.com/analytics-query-gateway")!
    private let chromeCookieImporter = ChromeCookieImporter()
    private let cookieURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config")
        .appendingPathComponent("roblox-stats-bar")
        .appendingPathComponent("roblox-cookie.txt")

    init(session: URLSession = .shared, metricsStore: DashboardMetricsStore) {
        self.session = session
        self.metricsStore = metricsStore
    }

    func hasLocalCookie() -> Bool {
        loadSession().session != nil
    }

    func saveCookie(_ rawCookie: String) throws {
        guard let cookie = normalize(cookie: rawCookie) else {
            throw CreatorHubScraperError.invalidCookie
        }

        let directory = cookieURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try cookie.write(to: cookieURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cookieURL.path)
    }

    func clearCookie() throws {
        guard FileManager.default.fileExists(atPath: cookieURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: cookieURL)
    }

    func refresh(universeIds: [Int64], completion: @escaping (Result<CreatorHubScrapeStatus, Error>) -> Void) {
        let uniqueIds = Array(Set(universeIds)).sorted()
        guard !uniqueIds.isEmpty else {
            completion(.success(CreatorHubScrapeStatus(fetchedCount: 0, skippedReason: "No games enabled")))
            return
        }

        let sessionResult = loadSession()
        guard let creatorSession = sessionResult.session else {
            completion(.success(CreatorHubScrapeStatus(fetchedCount: 0, skippedReason: sessionResult.skippedReason)))
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var savedCount = 0
        var firstError: Error?

        for universeId in uniqueIds {
            group.enter()
            fetchMetrics(universeId: universeId, cookie: creatorSession.cookie) { result in
                lock.lock()
                switch result {
                case .success(let record):
                    if let record {
                        do {
                            try self.metricsStore.save(record)
                            savedCount += 1
                        } catch {
                            if firstError == nil {
                                firstError = error
                            }
                        }
                    }
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
            } else {
                completion(.success(CreatorHubScrapeStatus(fetchedCount: savedCount, skippedReason: nil)))
            }
        }
    }

    private func fetchMetrics(universeId: Int64, cookie: String, completion: @escaping (Result<DashboardMetricsRecord?, Error>) -> Void) {
        let end = Date()
        let start72Hours = calendar.date(byAdding: .hour, value: -72, to: end) ?? end
        let start30Days = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let start365Days = calendar.date(byAdding: .day, value: -365, to: end) ?? end

        let group = DispatchGroup()
        let lock = NSLock()
        var values: [CreatorHubMetricSlot: Double] = [:]
        var sawSuccessfulMetric = false
        var firstError: Error?

        for request in [
            MetricRequest(slot: .robuxSales72h, metric: .dailyRevenue, startTime: start72Hours, endTime: end, granularity: "METRIC_GRANULARITY_ONE_DAY", reduce: .sum),
            MetricRequest(slot: .totalSales, metric: .dailyRevenue, startTime: start365Days, endTime: end, granularity: "METRIC_GRANULARITY_ONE_DAY", reduce: .sum),
            MetricRequest(slot: .d1Retention, metric: .d1Retention, startTime: start30Days, endTime: end, granularity: "METRIC_GRANULARITY_ONE_DAY", reduce: .latest),
            MetricRequest(slot: .d7Retention, metric: .d7Retention, startTime: start30Days, endTime: end, granularity: "METRIC_GRANULARITY_ONE_DAY", reduce: .latest),
            MetricRequest(slot: .performanceErrors, metric: .performanceErrors, startTime: start72Hours, endTime: end, granularity: "METRIC_GRANULARITY_ONE_DAY", reduce: .sum),
        ] {
            group.enter()
            queryMetric(request, universeId: universeId, cookie: cookie) { result in
                lock.lock()
                switch result {
                case .success(let value):
                    sawSuccessfulMetric = true
                    if let value {
                        values[request.slot] = value
                    }
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
            if sawSuccessfulMetric, !values.isEmpty {
                let existing = self.metricsStore.record(for: universeId)
                completion(.success(DashboardMetricsRecord(
                    universeId: universeId,
                    d1Retention: self.percentText(values[.d1Retention]) ?? existing?.d1Retention,
                    d7Retention: self.percentText(values[.d7Retention]) ?? existing?.d7Retention,
                    robuxSales72h: self.robuxText(values[.robuxSales72h]) ?? existing?.robuxSales72h,
                    totalSales: self.robuxText(values[.totalSales]) ?? existing?.totalSales,
                    performanceErrors: self.integerText(values[.performanceErrors]) ?? existing?.performanceErrors,
                    playthroughRate: self.percentText(values[.playthroughRate]) ?? existing?.playthroughRate,
                    updatedAt: Date()
                )))
            } else if let firstError {
                completion(.failure(firstError))
            } else {
                completion(.success(nil))
            }
        }
    }

    private func queryMetric(_ metricRequest: MetricRequest, universeId: Int64, cookie: String, completion: @escaping (Result<Double?, Error>) -> Void) {
        let url = analyticsGatewayBaseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("metrics")
            .appendingPathComponent("resource")
            .appendingPathComponent("RESOURCE_TYPE_UNIVERSE")
            .appendingPathComponent("id")
            .appendingPathComponent(String(universeId))

        let query = CreatorHubAnalyticsQuery(
            resourceType: "RESOURCE_TYPE_UNIVERSE",
            resourceId: String(universeId),
            metric: metricRequest.metric.rawValue,
            granularity: metricRequest.granularity,
            breakdown: [],
            startTime: iso8601.string(from: metricRequest.startTime),
            endTime: iso8601.string(from: metricRequest.endTime)
        )

        let body = CreatorHubAnalyticsRequest(
            resourceType: "RESOURCE_TYPE_UNIVERSE",
            resourceId: String(universeId),
            query: query
        )

        request(url: url, cookie: cookie, body: body, contentType: "application/json", ignoreBadRequest: true) { (result: Result<CreatorHubAnalyticsResponse, Error>) in
            completion(result.map { response in
                self.aggregate(response.operation?.queryResult?.values, reduce: metricRequest.reduce)
            })
        }
    }

    private func request<T: Decodable, Body: Encodable>(
        url: URL,
        cookie: String,
        csrfToken: String? = nil,
        body: Body,
        contentType: String,
        ignoreBadRequest: Bool = false,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        requestData(url: url, cookie: cookie, csrfToken: csrfToken, body: body, contentType: contentType, ignoreBadRequest: ignoreBadRequest) { result in
            completion(result.flatMap { data in
                do {
                    return .success(try JSONDecoder().decode(T.self, from: data))
                } catch {
                    return .failure(error)
                }
            })
        }
    }

    private func requestData<Body: Encodable>(
        url: URL,
        cookie: String,
        csrfToken: String? = nil,
        body: Body,
        contentType: String,
        ignoreBadRequest: Bool = false,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://create.roblox.com", forHTTPHeaderField: "Origin")
        request.setValue("https://create.roblox.com/", forHTTPHeaderField: "Referer")
        request.setValue("RobloxStatsBar/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(".ROBLOSECURITY=\(cookie)", forHTTPHeaderField: "Cookie")
        if let csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        }

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403,
                   csrfToken == nil,
                   let retryToken = httpResponse.value(forHTTPHeaderField: "x-csrf-token") {
                    self.requestData(url: url, cookie: cookie, csrfToken: retryToken, body: body, contentType: contentType, ignoreBadRequest: ignoreBadRequest, completion: completion)
                    return
                }

                if httpResponse.statusCode == 400, ignoreBadRequest {
                    let emptyResponse = #"{"operation":{"done":true,"queryResult":{"values":[]}}}"#
                    completion(.success(Data(emptyResponse.utf8)))
                    return
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    completion(.failure(CreatorHubScraperError.robloxStatus(httpResponse.statusCode)))
                    return
                }
            }

            guard let data else {
                completion(.failure(CreatorHubScraperError.invalidResponse))
                return
            }

            completion(.success(data))
        }.resume()
    }

    private func aggregate(_ series: [CreatorHubMetricSeries]?, reduce: CreatorHubMetricReduce) -> Double? {
        let allValues = (series ?? [])
            .flatMap { $0.datapoints ?? [] }
            .compactMap(\.value)

        guard !allValues.isEmpty else {
            return nil
        }

        switch reduce {
        case .sum:
            return allValues.reduce(0, +)
        case .latest:
            return allValues.last
        }
    }

    private func loadSession() -> CreatorHubSessionLoadResult {
        if let envCookie = ProcessInfo.processInfo.environment["ROBLOSECURITY"],
           let normalized = normalize(cookie: envCookie) {
            return CreatorHubSessionLoadResult(
                session: CreatorHubSession(cookie: normalized, source: "environment"),
                skippedReason: ""
            )
        }

        let chromeResult = chromeCookieImporter.roblosecurityCookie()
        if let cookie = chromeResult.cookie,
           let normalized = normalize(cookie: cookie) {
            return CreatorHubSessionLoadResult(
                session: CreatorHubSession(cookie: normalized, source: "Chrome"),
                skippedReason: ""
            )
        }

        if let raw = try? String(contentsOf: cookieURL, encoding: .utf8),
           let normalized = normalize(cookie: raw) {
            return CreatorHubSessionLoadResult(
                session: CreatorHubSession(cookie: normalized, source: "saved session"),
                skippedReason: ""
            )
        }

        return CreatorHubSessionLoadResult(
            session: nil,
            skippedReason: chromeResult.failureReason ?? "No readable Roblox session found"
        )
    }

    private func normalize(cookie: String) -> String? {
        var trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ".ROBLOSECURITY=") {
            trimmed = String(trimmed[range.upperBound...])
        }
        if let semicolon = trimmed.firstIndex(of: ";") {
            trimmed = String(trimmed[..<semicolon])
        }

        return trimmed.isEmpty ? nil : trimmed
    }

    private func robuxText(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        return integerText(value)
    }

    private func integerText(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        return numberFormatter.string(from: NSNumber(value: value.rounded()))
    }

    private func percentText(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }

        let normalized = value <= 1 ? value * 100 : value
        return percentFormatter.string(from: NSNumber(value: normalized / 100))
    }

    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private let percentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter
    }()

}

private struct CreatorHubSession {
    let cookie: String
    let source: String
}

private struct CreatorHubSessionLoadResult {
    let session: CreatorHubSession?
    let skippedReason: String
}

private struct MetricRequest {
    let slot: CreatorHubMetricSlot
    let metric: CreatorHubMetric
    let startTime: Date
    let endTime: Date
    let granularity: String
    let reduce: CreatorHubMetricReduce
}

private enum CreatorHubMetricSlot {
    case d1Retention
    case d7Retention
    case robuxSales72h
    case totalSales
    case performanceErrors
    case playthroughRate
}

private enum CreatorHubMetric: String {
    case dailyRevenue = "DailyRevenue"
    case d1Retention = "AttributionD1RetentionRatio"
    case d7Retention = "AttributionD7RetentionRatio"
    case performanceErrors = "ErrorCount"
    case playthroughRate = "FunnelStepOverallCompletionRate"
}

private enum CreatorHubMetricReduce {
    case sum
    case latest
}

private struct CreatorHubAnalyticsRequest: Encodable {
    let resourceType: String
    let resourceId: String
    let query: CreatorHubAnalyticsQuery
}

private struct CreatorHubAnalyticsQuery: Encodable {
    let resourceType: String
    let resourceId: String
    let metric: String
    let granularity: String
    let breakdown: [String]
    let startTime: String
    let endTime: String
}

private struct CreatorHubAnalyticsResponse: Decodable {
    let operation: CreatorHubAnalyticsOperation?
}

private struct CreatorHubAnalyticsOperation: Decodable {
    let done: Bool?
    let queryResult: CreatorHubAnalyticsQueryResult?
}

private struct CreatorHubAnalyticsQueryResult: Decodable {
    let values: [CreatorHubMetricSeries]?
}

private struct CreatorHubMetricSeries: Decodable {
    let breakdownValue: [String]?
    let dataPoints: [CreatorHubMetricDataPoint]?

    var datapoints: [CreatorHubMetricDataPoint]? {
        dataPoints
    }
}

private struct CreatorHubMetricDataPoint: Decodable {
    let timestamp: String?
    let value: Double?
}
