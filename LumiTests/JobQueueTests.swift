import Foundation
import Testing
@testable import Lumi

@MainActor
struct JobQueueTests {
    @Test func jobsRunOneAtATimeInOrder() async {
        let c = JobCenter()
        var log: [String] = []
        c.submit("a") { _ in log.append("a-start"); try await Task.sleep(for: .milliseconds(30)); log.append("a-end") }
        c.submit("b") { _ in log.append("b-start") }
        await c.idle()
        #expect(log == ["a-start", "a-end", "b-start"])
        #expect(c.jobs.map(\.state) == [.done, .done] && c.active.isEmpty)
    }

    @Test func progressIsReportedAndClamped() async {
        let c = JobCenter()
        let id = c.submit("p") { h in h.progress(0.4); try await Task.sleep(for: .milliseconds(50)); h.progress(7) }
        try? await Task.sleep(for: .milliseconds(25))
        #expect(c.jobs.first { $0.id == id }?.progress == 0.4)
        await c.idle()
        #expect(c.jobs.first { $0.id == id }?.progress == 1)
    }

    @Test func failuresAreRecordedAndTheQueueContinues() async {
        struct Boom: Error {}
        let c = JobCenter()
        c.submit("bad") { _ in throw Boom() }
        c.submit("good") { _ in }
        await c.idle()
        if case .failed = c.jobs[0].state {} else { Issue.record("expected failure") }
        #expect(c.jobs[1].state == .done)
    }

    @Test func cancellingARunningJobStopsIt() async {
        let c = JobCenter()
        let id = c.submit("long") { _ in try await Task.sleep(for: .seconds(30)) }
        try? await Task.sleep(for: .milliseconds(30))
        c.cancel(id)
        await c.idle()
        #expect(c.jobs.first { $0.id == id }?.state == .cancelled)
    }

    @Test func cancellingAQueuedJobSkipsIt() async {
        let c = JobCenter()
        var ran = false
        c.submit("first") { _ in try await Task.sleep(for: .milliseconds(50)) }
        let second = c.submit("second") { _ in ran = true }
        c.cancel(second)
        await c.idle()
        #expect(!ran && c.jobs[1].state == .cancelled)
    }

    @Test func cancelOfUnknownOrFinishedJobsIsHarmless() async {
        let c = JobCenter()
        let id = c.submit("x") { _ in }
        await c.idle()
        c.cancel(id); c.cancel(UUID())
        #expect(c.jobs[0].state == .done)
    }

    @Test func recentShowsFinishedJobsNewestFirstAndClearsOnRequest() async {
        let c = JobCenter()
        for i in 0..<3 { c.submit("j\(i)") { _ in } }
        await c.idle()
        #expect(c.recent.map(\.title) == ["j2", "j1", "j0"])
        c.clearHistory(); #expect(c.recent.isEmpty && c.jobs.isEmpty)
    }
}
