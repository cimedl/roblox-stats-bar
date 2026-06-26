import AppKit
import Foundation

private enum CreatorMetricField: CaseIterable {
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

    func value(from record: DashboardMetricsRecord) -> String {
        switch self {
        case .d1Retention:
            return record.d1Retention ?? ""
        case .d7Retention:
            return record.d7Retention ?? ""
        case .robuxSales72h:
            return record.robuxSales72h ?? ""
        case .totalSales:
            return record.totalSales ?? ""
        case .performanceErrors:
            return record.performanceErrors ?? ""
        case .playthroughRate:
            return record.playthroughRate ?? ""
        }
    }

    func apply(_ value: String?, to record: inout DashboardMetricsRecord) {
        switch self {
        case .d1Retention:
            record.d1Retention = value
        case .d7Retention:
            record.d7Retention = value
        case .robuxSales72h:
            record.robuxSales72h = value
        case .totalSales:
            record.totalSales = value
        case .performanceErrors:
            record.performanceErrors = value
        case .playthroughRate:
            record.playthroughRate = value
        }
    }
}

final class RobloxStatsBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    private let manageItem = NSMenuItem(title: "Manage Games...", action: #selector(showManageWindow), keyEquivalent: ",")
    private let metricsItem = NSMenuItem(title: "Update Creator Hub Metrics...", action: #selector(showMetricsWindow), keyEquivalent: "m")
    private let sessionItem = NSMenuItem(title: "Creator Hub Session...", action: #selector(showSessionWindow), keyEquivalent: "s")
    private let configStore = ConfigStore()
    private let dashboardMetricsStore = DashboardMetricsStore()
    private let api = RobloxAPI()
    private lazy var creatorHubScraper = CreatorHubScraper(metricsStore: dashboardMetricsStore)
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    private let compactFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private var config = AppConfig()
    private var snapshot: RobloxStatsSnapshot?
    private var timer: Timer?
    private var isRefreshing = false
    private var manageWindow: NSWindow?
    private var gamesStackView: NSStackView?
    private var inputField: NSTextField?
    private var statusLabel: NSTextField?
    private var metricsWindow: NSWindow?
    private var metricsGamePopup: NSPopUpButton?
    private var metricsFields: [CreatorMetricField: NSTextField] = [:]
    private var metricsStatusLabel: NSTextField?
    private var sessionWindow: NSWindow?
    private var sessionCookieField: NSSecureTextField?
    private var sessionStatusLabel: NSTextField?
    private var creatorHubFetchStatus: String?
    private var hasStatusIcon = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshItem.target = self
        manageItem.target = self
        metricsItem.target = self
        sessionItem.target = self
        config = configStore.load()

        configureApplicationMenu()
        configureStatusItem()
        rebuildMenu()
        refresh()

        timer = Timer.scheduledTimer(withTimeInterval: max(config.refreshIntervalSeconds, 30), repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        button.image = robloxTemplateIcon()
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        hasStatusIcon = true

        setStatusText("--")
        button.toolTip = "Roblox stats"
        statusItem.menu = statusMenu
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)

        let applicationMenu = NSMenu()
        applicationMenuItem.submenu = applicationMenu
        applicationMenu.addItem(NSMenuItem(title: "Quit Roblox Stats Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        NSApp.mainMenu = mainMenu
    }

    private func robloxTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: -18)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        let iconPath = NSBezierPath()
        iconPath.append(NSBezierPath(rect: NSRect(x: 2.2, y: 2.2, width: 13.6, height: 13.6)))
        iconPath.append(NSBezierPath(rect: NSRect(x: 6.6, y: 6.6, width: 4.8, height: 4.8)))
        iconPath.windingRule = .evenOdd

        NSColor.black.setFill()
        iconPath.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()

        if let snapshot {
            statusMenu.addItem(summaryItem(snapshot))
            statusMenu.addItem(.separator())

            if snapshot.games.isEmpty {
                let emptyItem = NSMenuItem(title: "No enabled games", action: nil, keyEquivalent: "")
                emptyItem.isEnabled = false
                statusMenu.addItem(emptyItem)
            } else {
                for game in snapshot.games {
                    statusMenu.addItem(gameItem(game))
                }
            }

            statusMenu.addItem(.separator())
            statusMenu.addItem(dashboardMetricsItem(snapshot.dashboardMetrics))
            if let creatorHubFetchStatus {
                let item = NSMenuItem(title: "Creator Hub fetch: \(creatorHubFetchStatus)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                statusMenu.addItem(item)
            }
        } else {
            let loadingItem = NSMenuItem(title: trackedGames().isEmpty ? "Add games to start tracking" : "Loading Roblox stats...", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            statusMenu.addItem(loadingItem)
        }

        statusMenu.addItem(.separator())
        appendGameToggles()
        statusMenu.addItem(.separator())
        statusMenu.addItem(refreshItem)
        statusMenu.addItem(manageItem)
        metricsItem.isEnabled = !config.games.isEmpty
        statusMenu.addItem(metricsItem)
        statusMenu.addItem(sessionItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func summaryItem(_ snapshot: RobloxStatsSnapshot) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 136))

        addMetric(title: "Current CCU", value: compact(snapshot.totalCCU), x: 14, y: 84, to: view)
        addMetric(title: "Total visits", value: compact(snapshot.totalVisits), x: 130, y: 84, to: view)
        addMetric(title: "Favorites", value: compact(snapshot.totalFavorites), x: 246, y: 84, to: view)

        addMetric(title: "Tracked games", value: "\(snapshot.games.count)", x: 14, y: 34, to: view)
        let cachedDashboardCount = snapshot.dashboardMetrics.filter { $0.value != nil }.count
        addMetric(title: "Dashboard stats", value: "\(cachedDashboardCount)/\(snapshot.dashboardMetrics.count)", x: 130, y: 34, to: view)
        addMetric(title: "Updated", value: dateFormatter.string(from: snapshot.capturedAt), x: 246, y: 34, to: view)

        return viewMenuItem(view)
    }

    private func gameItem(_ game: RobloxGameStat) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 76))
        let title = label(game.name, frame: NSRect(x: 14, y: 48, width: 332, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor)
        view.addSubview(title)

        let detail = "CCU \(compact(game.playing ?? 0))  |  Visits \(compact(game.visits ?? 0))  |  Favorites \(compact(game.favoritedCount ?? 0))"
        view.addSubview(label(detail, frame: NSRect(x: 14, y: 28, width: 332, height: 16), font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor))

        let idText = "Universe \(game.id)" + (game.rootPlaceId.map { "  |  Place \($0)" } ?? "")
        view.addSubview(label(idText, frame: NSRect(x: 14, y: 10, width: 332, height: 14), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor))

        return viewMenuItem(view)
    }

    private func dashboardMetricsItem(_ metrics: [MetricSourceStatus]) -> NSMenuItem {
        let rowHeight: CGFloat = 34
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: CGFloat(metrics.count) * rowHeight + 18))
        view.addSubview(label("Creator Hub metrics", frame: NSRect(x: 14, y: view.frame.height - 20, width: 332, height: 16), font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor))

        for (index, metric) in metrics.enumerated() {
            let y = view.frame.height - 52 - CGFloat(index) * rowHeight
            let statusText = metric.value ?? metric.status
            view.addSubview(label(metric.title, frame: NSRect(x: 14, y: y + 14, width: 122, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .labelColor))
            view.addSubview(label(statusText, frame: NSRect(x: 140, y: y + 14, width: 62, height: 16), font: .systemFont(ofSize: 10, weight: .semibold), color: .secondaryLabelColor))
            view.addSubview(label(metric.source, frame: NSRect(x: 206, y: y + 14, width: 140, height: 16), font: .systemFont(ofSize: 10), color: .secondaryLabelColor))
            view.addSubview(label(metric.detail, frame: NSRect(x: 14, y: y, width: 332, height: 14), font: .systemFont(ofSize: 10), color: .tertiaryLabelColor))
        }

        return viewMenuItem(view)
    }

    private func appendGameToggles() {
        let games = config.games.sorted { ($0.displayName ?? "\($0.universeId)") < ($1.displayName ?? "\($1.universeId)") }
        guard !games.isEmpty else {
            return
        }

        for game in games {
            let title = game.displayName ?? "Universe \(game.universeId)"
            let item = NSMenuItem(title: title, action: #selector(toggleGame(_:)), keyEquivalent: "")
            item.target = self
            item.state = game.enabled ? .on : .off
            item.tag = Int(game.universeId)
            statusMenu.addItem(item)
        }
    }

    @objc private func toggleGame(_ sender: NSMenuItem) {
        guard let index = config.games.firstIndex(where: { $0.universeId == Int64(sender.tag) }) else {
            return
        }

        config.games[index].enabled.toggle()
        saveConfig()
        refresh()
        renderManageGames()
    }

    @objc private func refreshNow() {
        refresh()
    }

    private func refresh() {
        guard !isRefreshing else {
            return
        }

        config = configStore.load()
        let enabledIds = trackedGames().map(\.universeId)
        if enabledIds.isEmpty {
            snapshot = RobloxStatsSnapshot(capturedAt: Date(), games: [], dashboardMetrics: DashboardMetricsStore.waitingStatuses())
            setStatusText("--")
            rebuildMenu()
            return
        }

        isRefreshing = true
        refreshItem.isEnabled = false
        setStatusText("...")

        api.loadSnapshot(universeIds: enabledIds) { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshing = false
            self.refreshItem.isEnabled = true

            switch result {
            case .success(let snapshot):
                let dashboardMetrics = self.dashboardMetricsStore.metricStatuses(for: enabledIds)
                let mergedSnapshot = RobloxStatsSnapshot(
                    capturedAt: snapshot.capturedAt,
                    games: snapshot.games,
                    dashboardMetrics: dashboardMetrics
                )
                self.snapshot = mergedSnapshot
                self.mergeNames(from: snapshot.games)
                self.setStatusText(self.compact(mergedSnapshot.totalCCU))
                self.statusItem.button?.toolTip = "Roblox stats: \(self.compact(mergedSnapshot.totalCCU)) CCU across \(mergedSnapshot.games.count) games"
                self.refreshCreatorHubMetrics(enabledIds: enabledIds)
            case .failure(let error):
                self.setStatusText("--")
                self.statusItem.button?.toolTip = error.localizedDescription
            }

            self.rebuildMenu()
            self.renderManageGames()
        }
    }

    private func refreshCreatorHubMetrics(enabledIds: [Int64]) {
        creatorHubScraper.refresh(universeIds: enabledIds) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let status):
                if let skippedReason = status.skippedReason {
                    self.creatorHubFetchStatus = skippedReason
                } else {
                    self.creatorHubFetchStatus = "Fetched \(status.fetchedCount) game\(status.fetchedCount == 1 ? "" : "s")"
                }
            case .failure(let error):
                self.creatorHubFetchStatus = error.localizedDescription
            }

            guard let snapshot = self.snapshot else {
                return
            }

            self.snapshot = RobloxStatsSnapshot(
                capturedAt: snapshot.capturedAt,
                games: snapshot.games,
                dashboardMetrics: self.dashboardMetricsStore.metricStatuses(for: enabledIds)
            )
            self.rebuildMenu()
            self.renderManageGames()
            self.loadMetricsForSelectedGame()
        }
    }

    private func trackedGames() -> [TrackedGame] {
        config.games.filter(\.enabled)
    }

    private func mergeNames(from stats: [RobloxGameStat]) {
        var changed = false
        for stat in stats {
            guard let index = config.games.firstIndex(where: { $0.universeId == stat.id }) else {
                continue
            }

            if config.games[index].displayName != stat.name {
                config.games[index].displayName = stat.name
                changed = true
            }
        }

        if changed {
            saveConfig()
        }
    }

    @objc private func showManageWindow() {
        if manageWindow == nil {
            buildManageWindow()
        }

        renderManageGames()
        manageWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildManageWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Roblox Stats Bar"
        window.center()

        let rootView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 520, height: 420))
        rootView.autoresizingMask = [.width, .height]

        let title = label("Tracked Roblox Games", frame: NSRect(x: 22, y: 372, width: 300, height: 24), font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor)
        rootView.addSubview(title)

        let input = NSTextField(frame: NSRect(x: 22, y: 330, width: 366, height: 28))
        input.placeholderString = "Universe ID or Roblox game URL"
        rootView.addSubview(input)
        inputField = input

        let addButton = NSButton(title: "Add", target: self, action: #selector(addGameFromInput))
        addButton.frame = NSRect(x: 398, y: 329, width: 84, height: 30)
        rootView.addSubview(addButton)

        let status = label("", frame: NSRect(x: 22, y: 304, width: 460, height: 18), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        rootView.addSubview(status)
        statusLabel = status

        let scrollView = NSScrollView(frame: NSRect(x: 22, y: 62, width: 460, height: 230))
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true

        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 438, height: 230))
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .left
        scrollView.documentView = stack
        rootView.addSubview(scrollView)
        gamesStackView = stack

        let footer = label("Public stats refresh every \(Int(max(config.refreshIntervalSeconds, 30)))s. Retention, sales breakdowns, performance errors, and playthrough need a Creator Hub source.", frame: NSRect(x: 22, y: 20, width: 460, height: 32), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        footer.lineBreakMode = .byWordWrapping
        rootView.addSubview(footer)

        window.contentView = rootView
        manageWindow = window
    }

    private func renderManageGames() {
        guard let stack = gamesStackView else {
            return
        }

        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if config.games.isEmpty {
            let empty = label("No games added yet.", frame: NSRect(x: 0, y: 0, width: 438, height: 42), font: .systemFont(ofSize: 13), color: .secondaryLabelColor)
            stack.addArrangedSubview(empty)
            return
        }

        for game in config.games.sorted(by: { $0.addedAt < $1.addedAt }) {
            stack.addArrangedSubview(gameManageRow(game))
        }
    }

    @objc private func showMetricsWindow() {
        config = configStore.load()

        if metricsWindow == nil {
            buildMetricsWindow()
        }

        renderMetricsGames()
        loadMetricsForSelectedGame()
        metricsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildMetricsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Creator Hub Metrics"
        window.center()

        let rootView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 520, height: 430))
        rootView.autoresizingMask = [.width, .height]

        rootView.addSubview(label("Creator Hub Metrics", frame: NSRect(x: 22, y: 382, width: 300, height: 24), font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))
        rootView.addSubview(label("Game", frame: NSRect(x: 22, y: 340, width: 120, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))

        let popup = NSPopUpButton(frame: NSRect(x: 22, y: 310, width: 310, height: 28), pullsDown: false)
        popup.target = self
        popup.action = #selector(metricsGameChanged)
        rootView.addSubview(popup)
        metricsGamePopup = popup

        let openButton = NSButton(title: "Open Hub", target: self, action: #selector(openSelectedCreatorHub))
        openButton.frame = NSRect(x: 344, y: 309, width: 104, height: 30)
        rootView.addSubview(openButton)

        metricsFields.removeAll()
        let startY: CGFloat = 262
        for (index, metric) in CreatorMetricField.allCases.enumerated() {
            let y = startY - CGFloat(index) * 40
            rootView.addSubview(label(metric.title, frame: NSRect(x: 22, y: y + 6, width: 140, height: 16), font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor))

            let field = NSTextField(frame: NSRect(x: 174, y: y, width: 180, height: 26))
            field.placeholderString = metric.placeholder
            rootView.addSubview(field)
            metricsFields[metric] = field
        }

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearSelectedMetrics))
        clearButton.frame = NSRect(x: 22, y: 34, width: 82, height: 30)
        rootView.addSubview(clearButton)

        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadSelectedMetrics))
        reloadButton.frame = NSRect(x: 112, y: 34, width: 82, height: 30)
        rootView.addSubview(reloadButton)

        let fetchButton = NSButton(title: "Fetch", target: self, action: #selector(fetchSelectedMetrics))
        fetchButton.frame = NSRect(x: 202, y: 34, width: 82, height: 30)
        rootView.addSubview(fetchButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSelectedMetrics))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 386, y: 34, width: 82, height: 30)
        rootView.addSubview(saveButton)

        let status = label("", frame: NSRect(x: 22, y: 12, width: 446, height: 16), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        rootView.addSubview(status)
        metricsStatusLabel = status

        window.contentView = rootView
        metricsWindow = window
    }

    private func renderMetricsGames() {
        guard let popup = metricsGamePopup else {
            return
        }

        let selectedId = selectedMetricsUniverseId()
        popup.removeAllItems()

        let games = config.games.sorted { lhs, rhs in
            (lhs.displayName ?? "\(lhs.universeId)") < (rhs.displayName ?? "\(rhs.universeId)")
        }

        for game in games {
            let title = game.displayName ?? "Universe \(game.universeId)"
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = NSNumber(value: game.universeId)
        }

        if let selectedId,
           let item = popup.itemArray.first(where: { ($0.representedObject as? NSNumber)?.int64Value == selectedId }) {
            popup.select(item)
        } else if !games.isEmpty {
            popup.selectItem(at: 0)
        }

        metricsStatusLabel?.stringValue = games.isEmpty ? "Add a game first." : ""
    }

    @objc private func showSessionWindow() {
        if sessionWindow == nil {
            buildSessionWindow()
        }

        renderSessionWindow()
        sessionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSessionWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 190),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Creator Hub Session"
        window.center()

        let rootView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 520, height: 190))
        rootView.autoresizingMask = [.width, .height]

        rootView.addSubview(label("Creator Hub Session", frame: NSRect(x: 22, y: 142, width: 300, height: 24), font: .systemFont(ofSize: 18, weight: .semibold), color: .labelColor))
        rootView.addSubview(label("Cookie", frame: NSRect(x: 22, y: 104, width: 120, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .secondaryLabelColor))

        let field = NSSecureTextField(frame: NSRect(x: 22, y: 72, width: 454, height: 28))
        field.placeholderString = ".ROBLOSECURITY"
        rootView.addSubview(field)
        sessionCookieField = field

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearCreatorHubSession))
        clearButton.frame = NSRect(x: 22, y: 28, width: 82, height: 30)
        rootView.addSubview(clearButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveCreatorHubSession))
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: 394, y: 28, width: 82, height: 30)
        rootView.addSubview(saveButton)

        let status = label("", frame: NSRect(x: 116, y: 34, width: 266, height: 16), font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
        rootView.addSubview(status)
        sessionStatusLabel = status

        window.contentView = rootView
        sessionWindow = window
    }

    private func renderSessionWindow() {
        sessionCookieField?.stringValue = ""
        sessionStatusLabel?.stringValue = creatorHubScraper.hasLocalCookie() ? "Session saved locally." : "No saved session."
    }

    @objc private func saveCreatorHubSession() {
        do {
            try creatorHubScraper.saveCookie(sessionCookieField?.stringValue ?? "")
            sessionCookieField?.stringValue = ""
            sessionStatusLabel?.stringValue = "Session saved locally."
            creatorHubFetchStatus = "Session saved"
            refresh()
        } catch {
            sessionStatusLabel?.stringValue = error.localizedDescription
        }
    }

    @objc private func clearCreatorHubSession() {
        do {
            try creatorHubScraper.clearCookie()
            sessionCookieField?.stringValue = ""
            sessionStatusLabel?.stringValue = "Session cleared."
            creatorHubFetchStatus = "No local Roblox cookie configured"
            rebuildMenu()
        } catch {
            sessionStatusLabel?.stringValue = error.localizedDescription
        }
    }

    @objc private func metricsGameChanged() {
        loadMetricsForSelectedGame()
    }

    @objc private func reloadSelectedMetrics() {
        loadMetricsForSelectedGame()
    }

    @objc private func fetchSelectedMetrics() {
        guard let universeId = selectedMetricsUniverseId() else {
            metricsStatusLabel?.stringValue = "Add a game first."
            return
        }

        metricsStatusLabel?.stringValue = "Fetching Creator Hub..."
        creatorHubScraper.refresh(universeIds: [universeId]) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let status):
                if let skippedReason = status.skippedReason {
                    self.metricsStatusLabel?.stringValue = skippedReason
                } else {
                    self.metricsStatusLabel?.stringValue = "Fetched Creator Hub metrics."
                }
            case .failure(let error):
                self.metricsStatusLabel?.stringValue = error.localizedDescription
            }

            self.loadMetricsForSelectedGame()
            self.refresh()
        }
    }

    private func loadMetricsForSelectedGame() {
        guard let universeId = selectedMetricsUniverseId() else {
            CreatorMetricField.allCases.forEach { metricsFields[$0]?.stringValue = "" }
            metricsStatusLabel?.stringValue = "Add a game first."
            return
        }

        if let record = dashboardMetricsStore.record(for: universeId) {
            for metric in CreatorMetricField.allCases {
                metricsFields[metric]?.stringValue = metric.value(from: record)
            }
            metricsStatusLabel?.stringValue = updatedMetricsText(record.updatedAt)
        } else {
            CreatorMetricField.allCases.forEach { metricsFields[$0]?.stringValue = "" }
            metricsStatusLabel?.stringValue = "No cached Creator Hub metrics for this game."
        }
    }

    @objc private func saveSelectedMetrics() {
        guard let universeId = selectedMetricsUniverseId() else {
            metricsStatusLabel?.stringValue = "Add a game first."
            return
        }

        var record = DashboardMetricsRecord(
            universeId: universeId,
            d1Retention: nil,
            d7Retention: nil,
            robuxSales72h: nil,
            totalSales: nil,
            performanceErrors: nil,
            playthroughRate: nil,
            updatedAt: Date()
        )

        for metric in CreatorMetricField.allCases {
            metric.apply(trimmedMetricValue(metricsFields[metric]?.stringValue ?? ""), to: &record)
        }

        do {
            try dashboardMetricsStore.save(record)
            metricsStatusLabel?.stringValue = "Saved local Creator Hub metrics."
            refresh()
        } catch {
            metricsStatusLabel?.stringValue = "Could not save metrics: \(error.localizedDescription)"
        }
    }

    @objc private func clearSelectedMetrics() {
        guard let universeId = selectedMetricsUniverseId() else {
            metricsStatusLabel?.stringValue = "Add a game first."
            return
        }

        do {
            try dashboardMetricsStore.deleteRecord(for: universeId)
            CreatorMetricField.allCases.forEach { metricsFields[$0]?.stringValue = "" }
            metricsStatusLabel?.stringValue = "Cleared local Creator Hub metrics."
            refresh()
        } catch {
            metricsStatusLabel?.stringValue = "Could not clear metrics: \(error.localizedDescription)"
        }
    }

    @objc private func openSelectedCreatorHub() {
        guard let universeId = selectedMetricsUniverseId(),
              let url = URL(string: "https://create.roblox.com/dashboard/creations/experiences/\(universeId)/overview") else {
            metricsStatusLabel?.stringValue = "Add a game first."
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func selectedMetricsUniverseId() -> Int64? {
        (metricsGamePopup?.selectedItem?.representedObject as? NSNumber)?.int64Value
    }

    private func trimmedMetricValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func updatedMetricsText(_ updatedAt: Date?) -> String {
        guard let updatedAt else {
            return "Loaded local Creator Hub metrics."
        }

        return "Loaded local metrics from \(dateFormatter.string(from: updatedAt))."
    }

    private func gameManageRow(_ game: TrackedGame) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 438, height: 48))

        let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleGameButton(_:)))
        checkbox.identifier = NSUserInterfaceItemIdentifier(String(game.universeId))
        checkbox.state = game.enabled ? .on : .off
        checkbox.frame = NSRect(x: 10, y: 14, width: 22, height: 22)
        row.addSubview(checkbox)

        let title = game.displayName ?? "Universe \(game.universeId)"
        row.addSubview(label(title, frame: NSRect(x: 40, y: 24, width: 280, height: 18), font: .systemFont(ofSize: 13, weight: .medium), color: .labelColor))
        row.addSubview(label("Universe \(game.universeId)", frame: NSRect(x: 40, y: 8, width: 280, height: 14), font: .systemFont(ofSize: 10), color: .secondaryLabelColor))

        let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeGameButton(_:)))
        removeButton.identifier = NSUserInterfaceItemIdentifier(String(game.universeId))
        removeButton.frame = NSRect(x: 338, y: 10, width: 84, height: 28)
        row.addSubview(removeButton)

        return row
    }

    @objc private func addGameFromInput() {
        guard let inputField else {
            return
        }

        let value = inputField.stringValue
        statusLabel?.stringValue = "Resolving..."

        api.resolveUniverseId(from: value) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success(let universeId):
                    if self.config.games.contains(where: { $0.universeId == universeId }) {
                        self.statusLabel?.stringValue = "Already tracking universe \(universeId)."
                    } else {
                        self.config.games.append(TrackedGame(universeId: universeId))
                        self.saveConfig()
                        self.inputField?.stringValue = ""
                        self.statusLabel?.stringValue = "Added universe \(universeId)."
                        self.renderManageGames()
                        self.refresh()
                    }
                case .failure(let error):
                    self.statusLabel?.stringValue = error.localizedDescription
                }
            }
        }
    }

    @objc private func toggleGameButton(_ sender: NSButton) {
        guard let idText = sender.identifier?.rawValue,
              let universeId = Int64(idText),
              let index = config.games.firstIndex(where: { $0.universeId == universeId }) else {
            return
        }

        config.games[index].enabled = sender.state == .on
        saveConfig()
        refresh()
    }

    @objc private func removeGameButton(_ sender: NSButton) {
        guard let idText = sender.identifier?.rawValue,
              let universeId = Int64(idText) else {
            return
        }

        config.games.removeAll { $0.universeId == universeId }
        saveConfig()
        snapshot = nil
        renderManageGames()
        refresh()
    }

    private func saveConfig() {
        do {
            try configStore.save(config)
        } catch {
            statusLabel?.stringValue = "Could not save config: \(error.localizedDescription)"
        }
    }

    private func addMetric(title: String, value: String, x: CGFloat, y: CGFloat, to view: NSView) {
        view.addSubview(label(title, frame: NSRect(x: x, y: y + 24, width: 104, height: 14), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor))
        view.addSubview(label(value, frame: NSRect(x: x, y: y, width: 104, height: 24), font: .monospacedDigitSystemFont(ofSize: 17, weight: .semibold), color: .labelColor))
    }

    private func label(_ text: String, frame: NSRect, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = font
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func viewMenuItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func setStatusText(_ text: String) {
        statusItem.button?.title = hasStatusIcon ? " \(text)" : text
    }

    private func compact(_ value: Int) -> String {
        let absolute = abs(value)
        if absolute >= 1_000_000 {
            return compact(value, divisor: 1_000_000, suffix: "M")
        }
        if absolute >= 1_000 {
            return compact(value, divisor: 1_000, suffix: "k")
        }
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func compact(_ value: Int, divisor: Double, suffix: String) -> String {
        let scaled = Double(value) / divisor
        let rounded = (scaled * 10).rounded() / 10
        if rounded.rounded() == rounded {
            return "\(Int(rounded))\(suffix)"
        }
        return (compactFormatter.string(from: NSNumber(value: rounded)) ?? String(format: "%.1f", rounded)) + suffix
    }
}

let application = NSApplication.shared
let delegate = RobloxStatsBarApp()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
