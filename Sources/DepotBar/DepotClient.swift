import Foundation

// MARK: - Models (mirror `depot ci workflow list -o json`)

struct JobCounts: Codable, Sendable {
    var total: Int = 0
    var queued: Int = 0
    var waiting: Int = 0
    var running: Int = 0
    var finished: Int = 0
    var failed: Int = 0
    var cancelled: Int = 0
    var skipped: Int = 0
}

struct DepotWorkflow: Codable, Sendable, Identifiable {
    var workflow_id: String
    var name: String
    var workflow_path: String
    var repo: String
    var status: String
    var trigger: String
    var run_id: String
    var sha: String
    var head_sha: String
    var created_at: String
    var job_counts: JobCounts
    // Enriched post-list via `depot ci workflow show` (nil when detail is unavailable).
    var ref: String? = nil
    var started_at: String? = nil
    var finished_at: String? = nil

    var id: String { workflow_id }

    var isRunning: Bool {
        status == "running" || status == "queued"
            || job_counts.running > 0 || job_counts.queued > 0 || job_counts.waiting > 0
    }

    var isFailed: Bool { status == "failed" || status == "cancelled" || job_counts.failed > 0 }
    var isFinished: Bool { status == "finished" && job_counts.failed == 0 }

    var shortRepo: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    var shortSHA: String { String(sha.prefix(7)) }

    var createdAt: Date? {
        ISO8601DateFormatter().date(from: created_at)
    }

    func relativeTime(now: Date = Date()) -> String {
        guard let date = createdAt else { return "" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case 0..<60: return "\(seconds)s ago"
        case 60..<3600: return "\(seconds / 60)m ago"
        case 3600..<86400: return "\(seconds / 3600)h ago"
        default: return "\(seconds / 86400)d ago"
        }
    }

    /// PR number parsed from refs like `refs/pull/317/merge` (nil for push triggers).
    var prNumber: Int? {
        guard let ref else { return nil }
        let parts = ref.split(separator: "/")
        guard parts.count >= 3, parts[0] == "refs", parts[1] == "pull",
              let number = Int(parts[2])
        else { return nil }
        return number
    }

    var startedAt: Date? {
        started_at.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    var finishedAt: Date? {
        finished_at.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    /// Seconds from workflow start to finish (or to now while still running).
    func elapsedSeconds(now: Date = Date()) -> Int? {
        guard let start = startedAt else { return nil }
        let end = finishedAt ?? now
        return max(0, Int(end.timeIntervalSince(start)))
    }

    /// Bare duration ("8m22s") — the row icon already says running vs finished.
    func durationText(now: Date = Date()) -> String? {
        guard let seconds = elapsedSeconds(now: now) else { return nil }
        return Self.formatDuration(seconds)
    }

    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 {
            return String(format: "%dm%02ds", seconds / 60, seconds % 60)
        }
        return String(format: "%dh%02dm", seconds / 3600, (seconds % 3600) / 60)
    }

}

// MARK: - Detail models (mirror `depot ci workflow show -o json`, subset we need)

struct WorkflowShowOutput: Codable, Sendable {
    struct RunInfo: Codable, Sendable {
        var ref: String?
    }
    struct WorkflowInfo: Codable, Sendable {
        var started_at: String?
        var finished_at: String?
    }
    var run: RunInfo?
    var workflow: WorkflowInfo?
}

// MARK: - Client (shells out to the Depot CLI, reusing its auth)

enum DepotError: Error, Sendable {
    case cliNotFound
    case failed(exitCode: Int32, message: String)
    case decodeError(String)
}

struct DepotClient: Sendable {
    let cliPath: String
    let orgID: String?
    let count: Int

    init(count: Int = 5) throws {
        self.cliPath = try Self.resolveCLIPath()
        self.orgID = Self.resolveOrgID()
        self.count = count
    }

    /// Locate the `depot` binary (Homebrew + standard paths + PATH lookup).
    static func resolveCLIPath() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/depot",
            "/usr/local/bin/depot",
            "\(NSHomeDirectory())/.local/bin/depot",
        ]
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Fall back to a login-shell PATH lookup.
        if let found = try? shellOut("/bin/zsh", ["-l", "-c", "command -v depot"])
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !found.isEmpty, fm.isExecutableFile(atPath: found)
        {
            return found
        }
        throw DepotError.cliNotFound
    }

    /// Read the current org id from the CLI's own settings (used for web URLs).
    static func resolveOrgID() -> String? {
        if let env = ProcessInfo.processInfo.environment["DEPOT_ORG_ID"], !env.isEmpty {
            return env
        }
        let path = "\(NSHomeDirectory())/Library/Application Support/depot/depot.yaml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("org_id:") {
                let value = trimmed.dropFirst("org_id:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    func fetchWorkflows() async throws -> [DepotWorkflow] {
        let data = try await run(arguments: ["ci", "workflow", "list", "-n", "\(count)", "-o", "json"])
        let listed: [DepotWorkflow]
        do {
            listed = try JSONDecoder().decode([DepotWorkflow].self, from: data)
        } catch {
            throw DepotError.decodeError(error.localizedDescription)
        }
        // Enrich each workflow with timing + PR ref via `show`, concurrently.
        // A detail failure for one workflow must not fail the whole refresh.
        return await withTaskGroup(of: (Int, WorkflowShowOutput?).self) { group in
            for (index, workflow) in listed.enumerated() {
                group.addTask {
                    let detail = try? await self.fetchDetail(for: workflow.workflow_id)
                    return (index, detail)
                }
            }
            var enriched = listed
            for await (index, detail) in group {
                if let detail {
                    enriched[index].ref = detail.run?.ref
                    enriched[index].started_at = detail.workflow?.started_at
                    enriched[index].finished_at = detail.workflow?.finished_at
                }
            }
            return enriched
        }
    }

    func fetchDetail(for workflowID: String) async throws -> WorkflowShowOutput {
        let data = try await run(arguments: ["ci", "workflow", "show", workflowID, "-o", "json"])
        return try JSONDecoder().decode(WorkflowShowOutput.self, from: data)
    }

    func dashboardURL() -> URL? {
        guard let org = orgID else { return URL(string: "https://depot.dev/orgs") }
        return URL(string: "https://depot.dev/orgs/\(org)/workflows/")
    }

    func workflowURL(for workflow: DepotWorkflow) -> URL? {
        guard let org = orgID else { return dashboardURL() }
        return URL(string: "https://depot.dev/orgs/\(org)/workflows/\(workflow.workflow_id)")
    }

    // MARK: - Process plumbing

    private func run(arguments: [String]) async throws -> Data {
        let cliPath = self.cliPath
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: cliPath)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: DepotError.failed(exitCode: -1, message: error.localizedDescription))
                    return
                }
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: errData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
                    continuation.resume(throwing: DepotError.failed(exitCode: process.terminationStatus, message: message))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }

    private static func shellOut(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
