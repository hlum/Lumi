import Foundation
import Testing
@testable import Lumi

struct BatchRunnerTests {
    struct Boom: Error {}
    actor Log { var seen: [Int] = []; var ticks: [Int] = []; func add(_ i: Int) { seen.append(i) }; func tick(_ n: Int) { ticks.append(n) } }

    @Test func processesAllInOrder() async {
        let log = Log()
        let r = await BatchRunner.run([1, 2, 3]) { await log.add($0) }
        #expect(r == [.done(1), .done(2), .done(3)])
        #expect(await log.seen == [1, 2, 3])
    }

    @Test func oneFailureDoesNotStopTheBatch() async {
        let r = await BatchRunner.run([1, 2, 3]) { if $0 == 2 { throw Boom() } }
        #expect(r.count == 3)
        #expect(r[0] == .done(1) && r[2] == .done(3))
        if case .failed(let id, _) = r[1] { #expect(id == 2) } else { Issue.record("expected failure") }
    }

    @Test func emptyBatchIsFine() async {
        #expect(await BatchRunner.run([Int]()) { _ in }.isEmpty)
    }

    @Test func reportsProgressFromZeroToTotal() async {
        let log = Log()
        _ = await BatchRunner.run([10, 20, 30], progress: { done, total in
            #expect(total == 3)
            Task { await log.tick(done) }
        }) { _ in }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(Set(await log.ticks) == [0, 1, 2, 3])
    }

    @Test func cancellationMarksRemainingItems() async {
        let task = Task { () -> [BatchResult<Int>] in
            await BatchRunner.run([1, 2, 3]) { _ in try await Task.sleep(for: .seconds(5)) }
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let r = await task.value
        #expect(r.count == 3)
        #expect(r.allSatisfy { if case .cancelled = $0 { true } else { false } })
    }
}
