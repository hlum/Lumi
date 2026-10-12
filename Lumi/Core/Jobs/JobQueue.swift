import Foundation
import Observation

struct Job: Identifiable, Equatable {
    enum State: Equatable { case queued, running, done, failed(String), cancelled }
    let id: UUID
    var title: String
    var state = State.queued
    var progress = 0.0
    var isFinished: Bool { if case .queued = state { false } else if case .running = state { false } else { true } }
}

/// Runs long jobs (video export, upscale, batch) one at a time, with progress, cancel and a short history ("recent tasks").
@Observable @MainActor
final class JobCenter {
    /// The app-wide queue (tests make their own).
    static let shared = JobCenter()
    static let historyLimit = 20
    private(set) var jobs: [Job] = []
    private var work: [UUID: (JobHandle) async throws -> Void] = [:]
    private var running: Task<Void, Never>?
    private var current: UUID?

    var active: [Job] { jobs.filter { !$0.isFinished } }
    var recent: [Job] { jobs.filter(\.isFinished).suffix(Self.historyLimit).reversed() }

    /// Queues a job; it starts when the previous one finishes.
    @discardableResult
    func submit(_ title: String, _ body: @escaping (JobHandle) async throws -> Void) -> UUID {
        let job = Job(id: UUID(), title: title)
        jobs.append(job); work[job.id] = body
        pump()
        return job.id
    }

    func cancel(_ id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), !jobs[i].isFinished else { return }
        if current == id { running?.cancel() }
        else { jobs[i].state = .cancelled; work[id] = nil }
    }

    func clearHistory() { jobs.removeAll(where: \.isFinished) }

    /// Waits until everything queued so far has finished (tests, app shutdown).
    func idle() async { while !active.isEmpty { await running?.value; await Task.yield() } }

    private func pump() {
        guard running == nil, let next = jobs.first(where: { $0.state == .queued }) else { return }
        current = next.id
        update(next.id) { $0.state = .running }
        let body = work[next.id]
        running = Task { [weak self] in
            var result: Job.State = .done
            do { try await body?(JobHandle { p in Task { @MainActor in self?.update(next.id) { $0.progress = min(max(p, 0), 1) } } }) }
            catch is CancellationError { result = .cancelled }
            catch { result = .failed(String(describing: error)) }
            if Task.isCancelled, result == .done { result = .cancelled }
            await self?.finish(next.id, result)
        }
    }

    private func finish(_ id: UUID, _ state: Job.State) {
        update(id) { $0.state = state; if state == .done { $0.progress = 1 } }
        work[id] = nil; current = nil; running = nil
        // keep memory bounded: drop the oldest finished jobs beyond twice the history we show
        let finished = jobs.filter(\.isFinished)
        if finished.count > Self.historyLimit * 2 { let drop = Set(finished.prefix(finished.count - Self.historyLimit * 2).map(\.id)); jobs.removeAll { drop.contains($0.id) } }
        pump()
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[i]) }
    }
}

/// Passed to a job body so it can report progress.
struct JobHandle: Sendable {
    let report: @Sendable (Double) -> Void
    func progress(_ p: Double) { report(p) }
}
