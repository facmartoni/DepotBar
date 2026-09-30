import XCTest

@testable import DepotBar

// MARK: - Failure transition detection

final class FailureNotifyTests: XCTestCase {
    private func workflow(id: String, status: String, failedJobs: Int = 0) -> DepotWorkflow {
        DepotWorkflow(
            workflow_id: id, name: "CI", workflow_path: "ci.yml",
            repo: "o/r", status: status, trigger: "push",
            run_id: "r", sha: "abc1234", head_sha: "abc1234",
            created_at: "2026-09-18T20:00:00Z",
            job_counts: JobCounts(
                total: 2, queued: 0, waiting: 0,
                running: status == "running" ? 1 : 0,
                finished: status == "running" ? 1 : 2,
                failed: failedJobs, cancelled: 0, skipped: 0
            )
        )
    }

    func testRunningToFailedNotifies() {
        let current = [workflow(id: "w1", status: "failed")]
        XCTAssertEqual(FailureNotify.newlyFailed(current: current, previous: ["w1": "running"]).map(\.id), ["w1"])
    }

    func testUnchangedFailureDoesNotRenotify() {
        let current = [workflow(id: "w1", status: "failed")]
        XCTAssertTrue(FailureNotify.newlyFailed(current: current, previous: ["w1": "failed"]).isEmpty)
    }

    func testHealthyWorkflowsNeverNotify() {
        let current = [workflow(id: "w1", status: "finished"), workflow(id: "w2", status: "running")]
        XCTAssertTrue(FailureNotify.newlyFailed(current: current, previous: [:]).isEmpty)
    }

    func testFailedJobsCountAsFailure() {
        // Finished red after running: status changed, failed jobs present.
        let current = [workflow(id: "w1", status: "finished", failedJobs: 1)]
        XCTAssertEqual(FailureNotify.newlyFailed(current: current, previous: ["w1": "running"]).map(\.id), ["w1"])
    }

    func testAlreadyFinishedRedStaysSilent() {
        let current = [workflow(id: "w1", status: "finished", failedJobs: 1)]
        XCTAssertTrue(FailureNotify.newlyFailed(current: current, previous: ["w1": "finished"]).isEmpty)
    }

    func testCancelledDoesNotNotify() {
        let current = [workflow(id: "w1", status: "cancelled")]
        XCTAssertTrue(FailureNotify.newlyFailed(current: current, previous: ["w1": "running"]).isEmpty)
    }

    func testNewWorkflowAppearingFailedNotifies() {
        let current = [workflow(id: "w9", status: "failed")]
        XCTAssertEqual(FailureNotify.newlyFailed(current: current, previous: ["w1": "finished"]).map(\.id), ["w9"])
    }

    func testStatusMapKeysByWorkflowID() {
        let map = FailureNotify.statusMap([workflow(id: "a", status: "running"), workflow(id: "b", status: "failed")])
        XCTAssertEqual(map, ["a": "running", "b": "failed"])
    }
}

// MARK: - notifyOnFailure config flag (default true)

final class NotifyConfigTests: XCTestCase {
    private func tempFile(containing text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testDefaultsToTrue() {
        XCTAssertTrue(AppConfig().notifyOnFailure)
        XCTAssertTrue(AppConfig.load(environment: [:], fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")).notifyOnFailure)
    }

    func testCanBeDisabled() throws {
        let file = try tempFile(containing: #"{"notifyOnFailure":false}"#)
        XCTAssertFalse(AppConfig.load(environment: [:], fileURL: file).notifyOnFailure)
    }

    func testThemeStillLoadsAlongside() throws {
        let file = try tempFile(containing: #"{"theme":"black","notifyOnFailure":false}"#)
        let config = AppConfig.load(environment: [:], fileURL: file)
        XCTAssertEqual(config.theme, .black)
        XCTAssertFalse(config.notifyOnFailure)
    }
}
