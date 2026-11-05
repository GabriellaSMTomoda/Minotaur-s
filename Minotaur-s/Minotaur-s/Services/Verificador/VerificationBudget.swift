import Foundation

/// Monotonic, session-scoped budget shared by all queries, retries and inference.
final class VerificationBudget: @unchecked Sendable {
    private let lock = NSLock()
    private let started: TimeInterval
    private let now: @Sendable () -> TimeInterval
    let totalSeconds: TimeInterval
    let networkSeconds: TimeInterval
    private var searches = 0
    private var pairs = 0
    private var issues = Set<VerificationLimitation>()
    private var embeddingCache: [String: [Float]] = [:]
    init(totalSeconds: TimeInterval = 15, networkSeconds: TimeInterval = 11,
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now; started = now()
        self.totalSeconds = totalSeconds; self.networkSeconds = min(networkSeconds, totalSeconds)
    }
    var elapsed: TimeInterval { max(0, now() - started) }
    var remaining: TimeInterval { max(0, totalSeconds - elapsed) }
    var networkRemaining: TimeInterval { max(0, networkSeconds - elapsed) }
    var searchCalls: Int { lock.withLock { searches } }
    var nliPairs: Int { lock.withLock { pairs } }
    var limitations: [VerificationLimitation] { lock.withLock { issues.sorted { $0.rawValue < $1.rawValue } } }
    func record(_ issue: VerificationLimitation) { _ = lock.withLock { issues.insert(issue) } }
    func reserveSearch() throws {
        try Task.checkCancellation()
        guard networkRemaining > 0 else { record(.deadline); throw VerificationError.deadlineExceeded }
        try lock.withLock {
            guard searches < 3 else { throw VerificationError.searchBudgetExceeded }
            searches += 1
        }
    }
    func reservePairs(_ count: Int = 1) throws {
        try Task.checkCancellation()
        guard remaining > 0.15 else { record(.deadline); throw VerificationError.deadlineExceeded }
        try lock.withLock {
            guard pairs + count <= 24 else {
                issues.insert(.inferenceBudget)
                throw VerificationError.inferenceBudgetExceeded
            }
            pairs += count
        }
    }
    func checkAnalysis() throws {
        try Task.checkCancellation()
        guard remaining > 0.15 else { record(.deadline); throw VerificationError.deadlineExceeded }
    }
    func embedding(for text: String, compute: () throws -> [Float]) rethrows -> [Float] {
        if let value = lock.withLock({ embeddingCache[text] }) { return value }
        let value = try compute()
        lock.withLock { embeddingCache[text] = value }
        return value
    }
}
