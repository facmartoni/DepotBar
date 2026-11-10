import XCTest

@testable import DepotBar

// MARK: - Cancelled runs are not failures
//
// CI cancels a queued run when a newer push to the same branch supersedes it.
// Showing those as ✗ makes a healthy branch look broken, so a cancelled run
// gets its own mark and never turns the menu bar icon red.

final class StatusTests: XCTestCase {
    private func workflow(status: String, failedJobs: Int = 0, cancelledJobs: Int = 0) -> DepotWorkflow {
        DepotWorkflow(
            workflow_id: "w1", name: "Tests & Deploy", workflow_path: "ci.yml",
            repo: "o/r", status: status, trigger: "push",
            run_id: "r", sha: "abc1234", head_sha: "abc1234",
            created_at: "2026-09-18T20:00:00Z",
            job_counts: JobCounts(
                total: 2, queued: 0, waiting: 0, running: 0,
                finished: 2 - cancelledJobs - failedJobs,
                failed: failedJobs, cancelled: cancelledJobs, skipped: 0
            )
        )
    }

    private func icon(_ workflows: [DepotWorkflow]) -> StatusIcon {
        MenuPresentation.statusIcon(
            workflows: workflows, isFetching: false, fetchStartedAt: nil,
            lastError: nil, spinnerIndex: 0
        )
    }

    func testCancelledRunIsNotAFailure() {
        let cancelled = workflow(status: "cancelled", cancelledJobs: 2)
        XCTAssertTrue(cancelled.isCancelled)
        XCTAssertFalse(cancelled.isFailed)
    }

    func testCancelledRowShowsItsOwnMark() {
        let title = MenuPresentation.rowTitle(for: workflow(status: "cancelled", cancelledJobs: 2), spinnerIndex: 0)
        XCTAssertTrue(title.hasPrefix("⊘"), title)
    }

    func testFailedRowStillShowsCross() {
        let title = MenuPresentation.rowTitle(for: workflow(status: "failed", failedJobs: 1), spinnerIndex: 0)
        XCTAssertTrue(title.hasPrefix("✗"), title)
    }

    func testCancelledRunsKeepTheMenuBarIconGreen() {
        let workflows = [workflow(status: "cancelled", cancelledJobs: 2), workflow(status: "finished")]
        XCTAssertEqual(icon(workflows), .symbol(name: "checkmark.circle.fill"))
    }

    func testAFailedRunStillTurnsTheMenuBarIconRed() {
        let workflows = [workflow(status: "cancelled", cancelledJobs: 2), workflow(status: "failed", failedJobs: 1)]
        XCTAssertEqual(icon(workflows), .symbol(name: "xmark.circle.fill"))
    }
}
