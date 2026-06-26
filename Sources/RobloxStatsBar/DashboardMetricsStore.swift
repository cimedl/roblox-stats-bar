import Foundation

struct DashboardMetricPoint: Codable {
    let timestamp: String?
    let value: Double
}

enum DashboardMetricKey: String, CaseIterable, Codable {
    case d1Retention
    case d7Retention
    case robuxSales72h
    case totalSales
    case performanceErrors
    case playthroughRate

    var title: String {
        switch self {
        case .d1Retention:
            return "D1 retention"
        case .d7Retention:
            return "D7 retention"
        case .robuxSales72h:
            return "72h Robux sales"
        case .totalSales:
            return "Total sales"
        case .performanceErrors:
            return "Performance errors"
        case .playthroughRate:
            return "Playthrough rate"
        }
    }

    var placeholder: String {
        switch self {
        case .d1Retention, .d7Retention, .playthroughRate:
            return "18.4%"
        case .robuxSales72h, .totalSales:
            return "12,340"
        case .performanceErrors:
            return "3"
        }
    }

    var averagesMultiGameSeries: Bool {
        switch self {
        case .d1Retention, .d7Retention, .playthroughRate:
            return true
        case .robuxSales72h, .totalSales, .performanceErrors:
            return false
        }
    }
}

struct DashboardMetricsRecord: Codable {
    let universeId: Int64
    var d1Retention: String?
    var d7Retention: String?
    var robuxSales72h: String?
    var totalSales: String?
    var performanceErrors: String?
    var playthroughRate: String?
    var metricSeries: [String: [DashboardMetricPoint]]?
    var updatedAt: Date?
}

extension DashboardMetricsRecord {
    func textValue(for key: DashboardMetricKey) -> String? {
        switch key {
        case .d1Retention:
            return d1Retention
        case .d7Retention:
            return d7Retention
        case .robuxSales72h:
            return robuxSales72h
        case .totalSales:
            return totalSales
        case .performanceErrors:
            return performanceErrors
        case .playthroughRate:
            return playthroughRate
        }
    }

    mutating func setTextValue(_ value: String?, for key: DashboardMetricKey) {
        switch key {
        case .d1Retention:
            d1Retention = value
        case .d7Retention:
            d7Retention = value
        case .robuxSales72h:
            robuxSales72h = value
        case .totalSales:
            totalSales = value
        case .performanceErrors:
            performanceErrors = value
        case .playthroughRate:
            playthroughRate = value
        }
    }

    func series(for key: DashboardMetricKey) -> [DashboardMetricPoint] {
        metricSeries?[key.rawValue] ?? []
    }

    mutating func setSeries(_ points: [DashboardMetricPoint], for key: DashboardMetricKey) {
        guard !points.isEmpty else {
            return
        }

        var updatedSeries = metricSeries ?? [:]
        updatedSeries[key.rawValue] = points
        metricSeries = updatedSeries
    }
}

private struct DashboardMetricsFile: Codable {
    var metrics: [DashboardMetricsRecord]
}

final class DashboardMetricsStore {
    private let metricsURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        metricsURL = home
            .appendingPathComponent(".config")
            .appendingPathComponent("roblox-stats-bar")
            .appendingPathComponent("dashboard-metrics.json")
    }

    func metricStatuses(for universeIds: [Int64]) -> [MetricSourceStatus] {
        let records = loadRecords(for: universeIds)
        return DashboardMetricKey.allCases.map {
            status(metric: $0, source: "Creator Hub cache", records: records)
        }
    }

    func record(for universeId: Int64) -> DashboardMetricsRecord? {
        loadAllRecords().first { $0.universeId == universeId }
    }

    func save(_ record: DashboardMetricsRecord) throws {
        var records = loadAllRecords()

        if let index = records.firstIndex(where: { $0.universeId == record.universeId }) {
            records[index] = record
        } else {
            records.append(record)
        }

        try saveAllRecords(records)
    }

    func deleteRecord(for universeId: Int64) throws {
        let records = loadAllRecords().filter { $0.universeId != universeId }
        try saveAllRecords(records)
    }

    static func waitingStatuses() -> [MetricSourceStatus] {
        DashboardMetricKey.allCases.map {
            MetricSourceStatus(title: $0.title, status: "Waiting", source: "Config", detail: "Add games first")
        }
    }

    private func loadRecords(for universeIds: [Int64]) -> [DashboardMetricsRecord] {
        let selectedIds = Set(universeIds)
        return loadAllRecords().filter { selectedIds.contains($0.universeId) }
    }

    private func loadAllRecords() -> [DashboardMetricsRecord] {
        guard FileManager.default.fileExists(atPath: metricsURL.path),
              let data = try? Data(contentsOf: metricsURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let file = try? decoder.decode(DashboardMetricsFile.self, from: data) else {
            return []
        }

        return file.metrics
    }

    private func saveAllRecords(_ records: [DashboardMetricsRecord]) throws {
        let directory = metricsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let sortedRecords = records.sorted { $0.universeId < $1.universeId }
        let data = try encoder.encode(DashboardMetricsFile(metrics: sortedRecords))
        try data.write(to: metricsURL, options: [.atomic])
    }

    private func status(metric: DashboardMetricKey, source: String, records: [DashboardMetricsRecord]) -> MetricSourceStatus {
        let values = records.compactMap { $0.textValue(for: metric) }.filter { !$0.isEmpty }
        let series = seriesValues(for: metric, records: records)

        guard !values.isEmpty else {
            return MetricSourceStatus(
                title: metric.title,
                status: "Pending",
                source: "Creator Hub",
                detail: "No local dashboard metric cached"
            )
        }

        if values.count == 1 {
            return MetricSourceStatus(
                title: metric.title,
                status: "Live",
                source: source,
                detail: updatedText(records: records),
                value: values[0],
                series: series
            )
        }

        return MetricSourceStatus(
            title: metric.title,
            status: "Cached",
            source: source,
            detail: "\(values.count) games have cached values",
            value: "\(values.count) games",
            series: series
        )
    }

    private func seriesValues(for metric: DashboardMetricKey, records: [DashboardMetricsRecord]) -> [Double] {
        let seriesByRecord = records
            .map { $0.series(for: metric) }
            .filter { !$0.isEmpty }

        guard !seriesByRecord.isEmpty else {
            return []
        }

        if seriesByRecord.count == 1 {
            return seriesByRecord[0].map(\.value)
        }

        if seriesByRecord.allSatisfy({ $0.allSatisfy { $0.timestamp == nil } }) {
            let maxCount = seriesByRecord.map(\.count).max() ?? 0
            return (0..<maxCount).compactMap { index in
                let values = seriesByRecord.compactMap { series in
                    series.indices.contains(index) ? series[index].value : nil
                }

                guard !values.isEmpty else {
                    return nil
                }

                if metric.averagesMultiGameSeries {
                    return values.reduce(0, +) / Double(values.count)
                }

                return values.reduce(0, +)
            }
        }

        var buckets: [String: [Double]] = [:]
        for series in seriesByRecord {
            for point in series {
                guard let timestamp = point.timestamp else {
                    continue
                }

                buckets[timestamp, default: []].append(point.value)
            }
        }

        return buckets.keys.sorted().compactMap { timestamp in
            guard let values = buckets[timestamp], !values.isEmpty else {
                return nil
            }

            if metric.averagesMultiGameSeries {
                return values.reduce(0, +) / Double(values.count)
            }

            return values.reduce(0, +)
        }
    }

    private func updatedText(records: [DashboardMetricsRecord]) -> String {
        let latestDate = records.compactMap(\.updatedAt).max()
        guard let latestDate else {
            return "Loaded from local dashboard cache"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: latestDate))"
    }

}
