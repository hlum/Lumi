import Foundation

/// Computes each key once. Hits never call `compute`.
actor AnalysisCache<Key: Hashable & Sendable, Value: Sendable> {
    private var store: [Key: Value] = [:]
    private(set) var computeCount = 0

    func value(for key: Key, compute: @Sendable () async throws -> Value) async rethrows -> Value {
        if let v = store[key] { return v }
        let v = try await compute()
        computeCount += 1
        store[key] = v
        return v
    }

    func invalidate(_ key: Key) { store[key] = nil }
}
