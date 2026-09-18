import AppKit
import ServiceManagement
import os

// MARK: - App entry point

if CommandLine.arguments.contains("--dump-menu") {
    MenuDump.runAndExit()
}

let app = NSApplication.shared
let delegate = DepotBarApp()
app.delegate = delegate
app.run()

// MARK: - Menu bar app

@MainActor
final class DepotBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let logger = Logger(subsystem: "com.facmartoni.DepotBar", category: "app")
    private static let refreshInterval: TimeInterval = 30

    private var statusItem: NSStatusItem!
    private var menu = NSMenu()
    private var client: DepotClient?
    private var workflows: [DepotWorkflow] = []
    private var lastFetch: Date?
    private var lastError: String?
    private var isFetching = false
    private var spinnerIndex = 0
    private var rowItems: [String: NSMenuItem] = [:]
    private var statusFooterItem: NSMenuItem?
    private var logHandle: FileHandle?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        openLog()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        menu.delegate = self
        menu.autoenablesItems = false

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Depot CI")
        }

        do {
            client = try DepotClient(count: 5)
            log("Depot CLI: \(client!.cliPath) org=\(client!.orgID ?? "unknown")")
        } catch {
            lastError = "Depot CLI not found. Install it: brew install depot/tap/depot"
            log("ERROR: depot CLI not found")
        }

        enableLaunchAtLogin()
        rebuildMenu()
        refresh()

        Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Spinner animation tick (menu bar icon + running rows).
        Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickSpinner() }
        }
        log("DepotBar alive")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("DepotBar quitting")
        try? logHandle?.close()
    }

    // MARK: - Menu delegate

    func menuWillOpen(_ menu: NSMenu) {
        updateRowTitles()
        updateFooter()
        // Refresh in the background every time the menu opens.
        refresh()
    }

    // MARK: - Fetching

    private var fetchTask: Task<Void, Never>?

    func refresh() {
        guard let client, !isFetching else { return }
        isFetching = true
        updateStatusIcon()
        fetchTask = Task {
            do {
                let workflows = try await client.fetchWorkflows()
                self.workflows = workflows
                self.lastFetch = Date()
                self.lastError = nil
                let running = workflows.filter { $0.isRunning }.count
                self.log("fetched \(workflows.count) workflows (\(running) running)")
            } catch is CancellationError {
                return
            } catch let DepotError.failed(_, message) {
                self.lastError = message
                self.log("ERROR: fetch failed: \(message)")
            } catch {
                self.lastError = error.localizedDescription
                self.log("ERROR: \(error.localizedDescription)")
            }
            self.isFetching = false
            self.rebuildMenu()
            self.updateStatusIcon()
        }
    }

    // MARK: - Menu construction

    private func rebuildMenu() {
        menu.removeAllItems()
        rowItems.removeAll()

        let header = NSMenuItem(title: "Depot CI", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if workflows.isEmpty {
            let empty = NSMenuItem(
                title: lastError == nil ? "Loading workflows…" : "⚠  \(lastError!)",
                action: nil, keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for workflow in workflows {
                let item = NSMenuItem(
                    title: rowTitle(for: workflow),
                    action: #selector(openWorkflow(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = workflow.workflow_id
                item.isEnabled = true
                menu.addItem(item)
                rowItems[workflow.workflow_id] = item
            }
        }

        menu.addItem(.separator())

        statusFooterItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusFooterItem?.isEnabled = false
        menu.addItem(statusFooterItem!)
        updateFooter()

        let refreshItem = NSMenuItem(title: "Refresh now", action: #selector(refreshNow(_:)), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let dashboardItem = NSMenuItem(title: "Open Depot dashboard", action: #selector(openDashboard(_:)), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit DepotBar", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func rowTitle(for workflow: DepotWorkflow) -> String {
        MenuPresentation.rowTitle(for: workflow, spinnerIndex: spinnerIndex)
    }

    private func updateRowTitles() {
        let now = Date()
        for workflow in workflows {
            guard let item = rowItems[workflow.workflow_id] else { continue }
            item.title = MenuPresentation.rowTitle(for: workflow, spinnerIndex: spinnerIndex, now: now)
        }
    }

    private func updateFooter() {
        guard let footer = statusFooterItem else { return }
        footer.title = MenuPresentation.footerTitle(
            isFetching: isFetching, lastFetch: lastFetch, lastError: lastError,
            spinnerIndex: spinnerIndex
        )
    }

    // MARK: - Status icon + spinner

    private func tickSpinner() {
        spinnerIndex += 1
        updateStatusIcon()
        updateRowTitles()
        updateFooter()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        switch MenuPresentation.statusIcon(
            workflows: workflows, isFetching: isFetching,
            lastError: lastError, spinnerIndex: spinnerIndex
        ) {
        case .spinner(let frame):
            // Animated spinner while fetching or while any workflow is still running.
            button.image = nil
            button.title = frame
        case .symbol(let name):
            button.title = ""
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Depot CI")
        }
    }

    // MARK: - Actions

    @objc private func openWorkflow(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let workflow = workflows.first(where: { $0.workflow_id == id }),
              let url = client?.workflowURL(for: workflow)
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openDashboard(_ sender: NSMenuItem) {
        guard let url = client?.dashboardURL() ?? URL(string: "https://depot.dev/orgs") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func refreshNow(_ sender: NSMenuItem) {
        refresh()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: - Launch at login

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            log("launch at login: enabled")
        } catch {
            log("launch at login: register failed: \(error.localizedDescription)")
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
                log("launch at login: disabled by user")
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
                log("launch at login: enabled by user")
            }
        } catch {
            log("launch at login: toggle failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    private func openLog() {
        let path = "/tmp/depotbar.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        logHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path))
        _ = try? logHandle?.seekToEnd()
    }

    private func log(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let data = line.data(using: .utf8) {
            try? logHandle?.write(contentsOf: data)
        }
        Self.logger.info("\(message, privacy: .public)")
    }
}
