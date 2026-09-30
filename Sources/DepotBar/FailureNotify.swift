import Foundation

// MARK: - Failure transitions (pure logic behind failure notifications)
//
// A workflow counts as newly failed when it is *really* failed (status
// "failed" or failed jobs — cancelled runs are noise, not failures) and its
// status changed since the previous fetch. Unchanged failures never re-notify.

enum FailureNotify {
    static func isFailure(_ workflow: DepotWorkflow) -> Bool {
        workflow.status == "failed" || workflow.job_counts.failed > 0
    }

    static func statusMap(_ workflows: [DepotWorkflow]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: workflows.map { ($0.workflow_id, $0.status) })
    }

    static func newlyFailed(
        current: [DepotWorkflow], previous: [String: String]
    ) -> [DepotWorkflow] {
        current.filter { workflow in
            guard isFailure(workflow) else { return false }
            return previous[workflow.workflow_id] != workflow.status
        }
    }
}
