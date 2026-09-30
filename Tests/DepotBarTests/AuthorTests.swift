import XCTest

@testable import DepotBar

// MARK: - GitHub author display (`@login` preferred, commit name fallback)

final class GitHubAuthorDisplayTests: XCTestCase {
    func testLoginWinsWithAtPrefix() throws {
        let output = try JSONDecoder().decode(
            GitHubAuthorOutput.self,
            from: Data(#"{"login":"octocat","name":"The Octocat"}"#.utf8)
        )
        XCTAssertEqual(GitHubAuthor.displayName(from: output), "@octocat")
    }

    func testFallsBackToCommitNameWhenLoginIsNull() throws {
        let output = try JSONDecoder().decode(
            GitHubAuthorOutput.self,
            from: Data(#"{"login":null,"name":"Ada Lovelace"}"#.utf8)
        )
        XCTAssertEqual(GitHubAuthor.displayName(from: output), "Ada Lovelace")
    }

    func testNilWhenNoAuthorInfo() throws {
        let output = try JSONDecoder().decode(
            GitHubAuthorOutput.self, from: Data(#"{"login":null,"name":null}"#.utf8)
        )
        XCTAssertNil(GitHubAuthor.displayName(from: output))
    }

    func testNilWhenStringsAreBlank() {
        XCTAssertNil(GitHubAuthor.displayName(from: GitHubAuthorOutput(login: "", name: "")))
        XCTAssertNil(GitHubAuthor.displayName(from: GitHubAuthorOutput(login: nil, name: "")))
    }
}

// MARK: - Author cache (commits are immutable: hits never expire, misses are remembered)

final class AuthorCacheTests: XCTestCase {
    func testMissThenHit() async {
        let cache = AuthorCache()
        let before = await cache.lookup("o/r@abc")
        XCTAssertFalse(before.hit)
        await cache.store("@octocat", for: "o/r@abc")
        let after = await cache.lookup("o/r@abc")
        XCTAssertTrue(after.hit)
        XCTAssertEqual(after.author, "@octocat")
    }

    func testNilAuthorIsCachedToo() async {
        let cache = AuthorCache()
        await cache.store(nil, for: "o/r@deadbee")
        let result = await cache.lookup("o/r@deadbee")
        XCTAssertTrue(result.hit)
        XCTAssertNil(result.author)
    }
}

// MARK: - Row title shows the author between repo and PR number

final class RowTitleAuthorTests: XCTestCase {
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    private func workflow(author: String?, ref: String? = "refs/pull/317/merge") -> DepotWorkflow {
        var workflow = DepotWorkflow(
            workflow_id: "w1", name: "React Doctor", workflow_path: "ci.yml",
            repo: "macch-info/macch-core", status: "finished", trigger: "pull_request",
            run_id: "r1", sha: "abc1234", head_sha: "abc1234",
            created_at: "2026-09-18T20:00:00Z",
            job_counts: JobCounts(total: 2, queued: 0, waiting: 0, running: 0, finished: 2, failed: 0, cancelled: 0, skipped: 0),
            ref: ref, started_at: "2026-09-18T20:00:00Z", finished_at: "2026-09-18T20:00:31Z"
        )
        workflow.author = author
        return workflow
    }

    func testRowIncludesAuthorAfterRepo() {
        let created = iso.date(from: "2026-09-18T20:00:00Z")!
        let now = created.addingTimeInterval(15 * 60)
        let title = MenuPresentation.rowTitle(for: workflow(author: "@octocat"), spinnerIndex: 0, now: now)
        XCTAssertEqual(title, "✓  React Doctor — macch-core · @octocat · #317 · 15m ago · 31s")
    }

    func testRowOmitsAuthorWhenNil() {
        let created = iso.date(from: "2026-09-18T20:00:00Z")!
        let now = created.addingTimeInterval(15 * 60)
        let title = MenuPresentation.rowTitle(for: workflow(author: nil), spinnerIndex: 0, now: now)
        XCTAssertEqual(title, "✓  React Doctor — macch-core · #317 · 15m ago · 31s")
    }

    func testRowOmitsBlankAuthor() {
        let created = iso.date(from: "2026-09-18T20:00:00Z")!
        let now = created.addingTimeInterval(15 * 60)
        let title = MenuPresentation.rowTitle(for: workflow(author: ""), spinnerIndex: 0, now: now)
        XCTAssertEqual(title, "✓  React Doctor — macch-core · #317 · 15m ago · 31s")
    }
}

// MARK: - List JSON without author info still decodes (author is enriched, never listed)

final class WorkflowDecodeTests: XCTestCase {
    func testListJSONWithoutAuthorDecodesWithNilAuthor() throws {
        let json = """
        [{
            "workflow_id": "w1", "name": "CI", "workflow_path": "ci.yml",
            "repo": "o/r", "status": "finished", "trigger": "push",
            "run_id": "r1", "sha": "abc1234", "head_sha": "abc1234",
            "created_at": "2026-09-18T20:00:00Z",
            "job_counts": {"total": 1, "queued": 0, "waiting": 0, "running": 0, "finished": 1, "failed": 0, "cancelled": 0, "skipped": 0}
        }]
        """
        let workflows = try JSONDecoder().decode([DepotWorkflow].self, from: Data(json.utf8))
        XCTAssertEqual(workflows.count, 1)
        XCTAssertNil(workflows[0].author)
    }
}
