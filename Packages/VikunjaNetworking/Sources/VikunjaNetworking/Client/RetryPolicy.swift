import Foundation

/// How many times to retry a request the server marked as rate-limited
/// (429) or temporarily unable to handle (503), and how long to wait
/// between attempts. Neither status implies the request was processed, so
/// retrying either is safe regardless of HTTP method — a 4xx/5xx for any
/// other reason reflects something about the request or server state that
/// retrying won't fix.
struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval

    static let `default` = RetryPolicy(maxAttempts: 4, baseDelay: 0.5, maxDelay: 8)

    static func isRetryable(statusCode: Int) -> Bool {
        statusCode == 429 || statusCode == 503
    }

    /// The server's own `Retry-After` value takes priority when present;
    /// otherwise an exponentially growing delay with a little jitter so a
    /// burst of requests that all got rate-limited together don't all
    /// retry on the exact same tick.
    func delay(forAttempt attempt: Int, retryAfter: TimeInterval?) -> Duration {
        let seconds = retryAfter ?? jitteredExponentialSeconds(forAttempt: attempt)
        return .milliseconds(Int((seconds * 1000).rounded()))
    }

    private func jitteredExponentialSeconds(forAttempt attempt: Int) -> TimeInterval {
        let exponential = min(maxDelay, baseDelay * pow(2, Double(attempt)))
        return exponential + Double.random(in: 0 ... (exponential * 0.25))
    }
}

/// Seam around `Task.sleep` so a test can assert on the computed retry
/// delay without the test itself waiting that long.
protocol RetryDelaying: Sendable {
    func sleep(for duration: Duration) async throws
}

struct TaskSleepDelayer: RetryDelaying {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
