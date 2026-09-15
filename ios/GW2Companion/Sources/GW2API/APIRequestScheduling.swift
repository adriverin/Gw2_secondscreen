import Foundation

enum APIRequestPriority: Int, Comparable, Sendable {
    case high = 0
    case normal = 1
    case low = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Bounded-concurrency scheduler so interactive account reads are not stuck
/// behind bulk recipe/achievement indexing, and so bursts do not trip 429s.
actor APIRequestScheduler {
    static let defaultMaxConcurrent = 4

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [Waiter] = []
    private var pausedUntil: Date?
    private var consecutiveRateLimits = 0

    private struct Waiter {
        let priority: APIRequestPriority
        let continuation: CheckedContinuation<Void, Error>
    }

    init(maxConcurrent: Int = APIRequestScheduler.defaultMaxConcurrent) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func perform<T: Sendable>(
        priority: APIRequestPriority,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        try await acquire(priority: priority)
        defer { release() }
        try await waitForPause()
        return try await operation()
    }

    func noteRateLimited(retryAfter: TimeInterval?) {
        consecutiveRateLimits += 1
        let backoff = retryAfter ?? min(16, pow(2.0, Double(consecutiveRateLimits)))
        pausedUntil = Date().addingTimeInterval(max(0.4, backoff))
    }

    func noteSuccess() {
        consecutiveRateLimits = 0
    }

    private func acquire(priority: APIRequestPriority) async throws {
        if running < maxConcurrent {
            running += 1
            return
        }
        try await withCheckedThrowingContinuation { continuation in
            waiters.append(Waiter(priority: priority, continuation: continuation))
            waiters.sort { $0.priority < $1.priority }
        }
    }

    private func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.continuation.resume()
        } else {
            running = max(0, running - 1)
        }
    }

    private func waitForPause() async throws {
        guard let pausedUntil else { return }
        let remaining = pausedUntil.timeIntervalSinceNow
        guard remaining > 0 else {
            self.pausedUntil = nil
            return
        }
        try await Task.sleep(for: .milliseconds(Int(remaining * 1_000)))
        self.pausedUntil = nil
    }
}

enum RetryAfterParser {
    static func delay(from response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let value = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) {
                return max(0.4, seconds)
            }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: value) {
                return max(0.4, date.timeIntervalSinceNow)
            }
        }
        return min(16, pow(2.0, Double(attempt)))
    }
}
