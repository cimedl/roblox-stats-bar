import Foundation

struct DashboardMetricsRecord: Codable {
    let universeId: Int64
    var d1Retention: String?
    var d7Retention: String?
    var robuxSales72h: String?
    var totalSales: String?
    var performanceErrors: String?
    var playthroughRate: String?
    var updatedAt: Date?
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
        return [
            status(title: "D1 retention", source: "Creator Hub cache", records: records, value: \.d1Retention),
            status(title: "D7 retention", source: "Creator Hub cache", records: records, value: \.d7Retention),
            status(title: "72h Robux sales", source: "Creator Hub cache", records: records, value: \.robuxSales72h),
            status(title: "Total sales", source: "Creator Hub cache", records: records, value: \.totalSales),
            status(title: "Performance errors", source: "Creator Hub cache", records: records, value: \.performanceErrors),
            status(title: "Playthrough rate", source: "Creator Hub cache", records: records, value: \.playthroughRate),
        ]
    }

    static func waitingStatuses() -> [MetricSourceStatus] {
        metricTitles.map {
            MetricSourceStatus(title: $0, status: "Waiting", source: "Config", detail: "Add games first")
        }
    }

    private func loadRecords(for universeIds: [Int64]) -> [DashboardMetricsRecord] {
        guard FileManager.default.fileExists(atPath: metricsURL.path),
              let data = try? Data(contentsOf: metricsURL) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let file = try? decoder.decode(DashboardMetricsFile.self, from: data) else {
            return []
        }

        let selectedIds = Set(universeIds)
        return file.metrics.filter { selectedIds.contains($0.universeId) }
    }

    private func status(
        title: String,
        source: String,
        records: [DashboardMetricsRecord],
        value: (DashboardMetricsRecord) -> String?
    ) -> MetricSourceStatus {
        let values = records.compactMap(value).filter { !$0.isEmpty }

        guard !values.isEmpty else {
            return MetricSourceStatus(
                title: title,
                status: "Pending",
                source: "Creator Hub",
                detail: "No local dashboard metric cached"
            )
        }

        if values.count == 1 {
            return MetricSourceStatus(
                title: title,
                status: "Live",
                source: source,
                detail: updatedText(records: records),
                value: values[0]
            )
        }

        return MetricSourceStatus(
            title: title,
            status: "Cached",
            source: source,
            detail: "\(values.count) games have cached values",
            value: "\(values.count) games"
        )
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

    private static let metricTitles = [
        "D1 retention",
        "D7 retention",
        "72h Robux sales",
        "Total sales",
        "Performance errors",
        "Playthrough rate",
    ]
}
