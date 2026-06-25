import AppKit
import Foundation

final class RobloxStatsBarApp: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
    private let manageItem = NSMenuItem(title: "Manage Games...", action: #selector(showManageWindow), keyEquivalent: ",")
    private let configStore = ConfigStore()
    private let api = RobloxAPI()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshItem.target = self
        manageItem.target = self
        config = configStore.load()

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

        button.title = "RBX --"
        button.toolTip = "Roblox stats"
        statusItem.menu = statusMenu
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
            statusMenu.addItem(unavailableMetricsItem(snapshot.unavailableMetrics))
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
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func summaryItem(_ snapshot: RobloxStatsSnapshot) -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 136))

        addMetric(title: "Current CCU", value: compact(snapshot.totalCCU), x: 14, y: 84, to: view)
        addMetric(title: "Total visits", value: compact(snapshot.totalVisits), x: 130, y: 84, to: view)
        addMetric(title: "Favorites", value: compact(snapshot.totalFavorites), x: 246, y: 84, to: view)

        addMetric(title: "Tracked games", value: "\(snapshot.games.count)", x: 14, y: 34, to: view)
        addMetric(title: "Dashboard stats", value: "Pending", x: 130, y: 34, to: view)
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

    private func unavailableMetricsItem(_ metrics: [UnavailableMetric]) -> NSMenuItem {
        let rowHeight: CGFloat = 30
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: CGFloat(metrics.count) * rowHeight + 18))
        view.addSubview(label("Creator Hub metrics", frame: NSRect(x: 14, y: view.frame.height - 20, width: 332, height: 16), font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor))

        for (index, metric) in metrics.enumerated() {
            let y = view.frame.height - 48 - CGFloat(index) * rowHeight
            view.addSubview(label(metric.title, frame: NSRect(x: 14, y: y + 10, width: 126, height: 16), font: .systemFont(ofSize: 11, weight: .medium), color: .labelColor))
            view.addSubview(label(metric.reason, frame: NSRect(x: 144, y: y + 10, width: 202, height: 16), font: .systemFont(ofSize: 10), color: .secondaryLabelColor))
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

        let enabledIds = trackedGames().map(\.universeId)
        if enabledIds.isEmpty {
            snapshot = RobloxStatsSnapshot(capturedAt: Date(), games: [], unavailableMetrics: [
                UnavailableMetric(title: "D1 retention", reason: "Add games first"),
                UnavailableMetric(title: "D7 retention", reason: "Add games first"),
                UnavailableMetric(title: "72h Robux sales", reason: "Add games first"),
                UnavailableMetric(title: "Total sales", reason: "Add games first"),
                UnavailableMetric(title: "Performance errors", reason: "Add games first"),
                UnavailableMetric(title: "Playthrough rate", reason: "Add games first"),
            ])
            setStatusText("RBX --")
            rebuildMenu()
            return
        }

        isRefreshing = true
        refreshItem.isEnabled = false
        setStatusText("RBX ...")

        api.loadSnapshot(universeIds: enabledIds) { [weak self] result in
            guard let self else {
                return
            }

            self.isRefreshing = false
            self.refreshItem.isEnabled = true

            switch result {
            case .success(let snapshot):
                self.snapshot = snapshot
                self.mergeNames(from: snapshot.games)
                self.setStatusText("RBX \(self.compact(snapshot.totalCCU))")
                self.statusItem.button?.toolTip = "Roblox stats: \(self.compact(snapshot.totalCCU)) CCU across \(snapshot.games.count) games"
            case .failure(let error):
                self.setStatusText("RBX --")
                self.statusItem.button?.toolTip = error.localizedDescription
            }

            self.rebuildMenu()
            self.renderManageGames()
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
        statusItem.button?.title = text
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
