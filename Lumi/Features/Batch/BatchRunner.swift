import Foundation

enum BatchResult<ID: Hashable & Sendable>: Equatable where ID: Equatable {
    case done(ID), failed(ID, String), cancelled(ID)
}

/// Runs `process` over items one at a time (memory-friendly for full-res photos), reporting progress.
enum BatchRunner {
    static func run<ID: Hashable & Sendable>(
        _ items: [ID],
        progress: @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in },
        process: @Sendable (ID) async throws -> Void
    ) async -> [BatchResult<ID>] {
        var out: [BatchResult<ID>] = []
        progress(0, items.count)
        for (i, item) in items.enumerated() {
            if Task.isCancelled { out.append(.cancelled(item)); continue }
            do { try await process(item); out.append(.done(item)) }
            catch is CancellationError { out.append(.cancelled(item)) }
            catch { out.append(.failed(item, String(describing: error))) }      // one bad photo never stops the batch
            progress(i + 1, items.count)
        }
        return out
    }
}
