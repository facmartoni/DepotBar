import AppKit
import Foundation

// MARK: - Runloop-aware timers
//
// Timer.scheduledTimer fires only in the runloop's `.default` mode. While an
// NSMenu is open the main runloop switches to event-tracking mode, so plain
// timers freeze — including the spinner animation. Adding the timer to
// `.common` modes keeps it firing in every common mode (default, event
// tracking, modal panels, …). All app timers must go through here.

enum AppTimers {
    @discardableResult
    static func scheduled(interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

// MARK: - Self test (`DepotBar --self-test`)
//
// Reproduces "menu is open" headlessly: runs the main runloop in
// event-tracking mode (exactly what NSMenu tracking does) and counts timer
// firings. No UI is shown.

enum SelfTest {
    // Fires only on the main thread in this test; no actual sharing.
    final class Counter: @unchecked Sendable {
        var trackingFires = 0
        var totalFires = 0
    }

    @MainActor
    static func runAndExit() -> Never {
        // AppKit registers event-tracking as a common runloop mode at
        // NSApplication init — required for a faithful simulation.
        _ = NSApplication.shared
        let fixed = Counter()
        let plain = Counter()

        // Timer created the way the app creates them (must keep firing).
        _ = AppTimers.scheduled(interval: 0.05, repeats: true) { _ in
            fixed.totalFires += 1
            if RunLoop.main.currentMode == .eventTracking { fixed.trackingFires += 1 }
        }
        // Plain default-mode timer (negative control: must freeze, like the old bug).
        _ = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            plain.totalFires += 1
            if RunLoop.main.currentMode == .eventTracking { plain.trackingFires += 1 }
        }

        // Simulate an open menu for 0.5s (~10 expected firings at 50ms).
        let end = Date().addingTimeInterval(0.5)
        while Date() < end {
            RunLoop.main.run(mode: .eventTracking, before: end)
        }

        print("menu-tracking simulation (0.5s, 50ms timer, expect ~10 fires):")
        print("  app timer:   \(fixed.trackingFires) tracking-mode fires")
        print("  plain timer: \(plain.trackingFires) tracking-mode fires (negative control, expect 0)")

        // Successive ticks must change the visible glyph (production formatting).
        let frames = (0..<10).map { MenuPresentation.spinner(at: $0) }
        let distinctFrames = Set(frames).count
        let sample = DepotWorkflow(
            workflow_id: "test", name: "CI", workflow_path: "ci.yml", repo: "o/r",
            status: "running", trigger: "push", run_id: "r", sha: "abc1234",
            head_sha: "abc1234", created_at: "2026-09-18T20:00:00Z",
            job_counts: JobCounts(total: 4, queued: 0, waiting: 0, running: 2, finished: 2, failed: 0, cancelled: 0, skipped: 0)
        )
        let titles = (0..<10).map { MenuPresentation.rowTitle(for: sample, spinnerIndex: $0) }
        let distinctTitles = Set(titles).count
        print("  spinner frames over 10 ticks: \(distinctFrames) distinct (\(frames.joined()))")
        print("  running-row titles over 10 ticks: \(distinctTitles) distinct")

        // Menu bar icon must not flash on routine refreshes (the noise bug).
        let now = Date()
        let finished = DepotWorkflow(
            workflow_id: "done", name: "CI", workflow_path: "ci.yml", repo: "o/r",
            status: "finished", trigger: "push", run_id: "r", sha: "abc1234",
            head_sha: "abc1234", created_at: "2026-09-18T20:00:00Z",
            job_counts: JobCounts(total: 2, queued: 0, waiting: 0, running: 0, finished: 2, failed: 0, cancelled: 0, skipped: 0)
        )
        func isSpinner(_ icon: MenuPresentation.StatusIcon) -> Bool {
            if case .spinner = icon { return true }
            return false
        }
        let quickRefresh = MenuPresentation.statusIcon(
            workflows: [finished], isFetching: true,
            fetchStartedAt: now.addingTimeInterval(-0.5),
            lastError: nil, spinnerIndex: 0, now: now)
        let slowRefresh = MenuPresentation.statusIcon(
            workflows: [finished], isFetching: true,
            fetchStartedAt: now.addingTimeInterval(-3),
            lastError: nil, spinnerIndex: 0, now: now)
        let runningIdle = MenuPresentation.statusIcon(
            workflows: [sample], isFetching: false, fetchStartedAt: nil,
            lastError: nil, spinnerIndex: 0, now: now)
        print("  icon during 0.5s refresh (settled): \(quickRefresh) — expect symbol, no flash")
        print("  icon during 3s refresh (settled):   \(slowRefresh) — expect spinner")
        print("  icon with running workflow, idle:   \(runningIdle) — expect spinner")
        let noFlash = !isSpinner(quickRefresh) && isSpinner(slowRefresh) && isSpinner(runningIdle)

        let pass = fixed.trackingFires >= 5 && plain.trackingFires == 0
            && distinctFrames == 10 && distinctTitles == 10 && noFlash
        print(pass
            ? "SELF-TEST PASS: spinner keeps animating while the menu is open"
            : "SELF-TEST FAIL")
        exit(pass ? 0 : 1)
    }
}
