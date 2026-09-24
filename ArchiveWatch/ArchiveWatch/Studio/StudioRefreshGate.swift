import Foundation

/// ONE REFRESH AT A TIME PER PLATFORM (launch audit B).
///
/// Twitch's refresh tokens are single-use, and during a show several callers
/// ask for a token at once — the viewer count, a chapter marker, a readiness
/// check. Each saw an expired token and refreshed it; the first spent the
/// refresh token and the second was refused, which reads to the host as
/// "sign in to Twitch again" mid-show. While one refresh is in flight, every
/// other caller awaits that same result.
actor StudioRefreshGate {
    private var inFlight: [String: Task<String, Error>] = [:]

    func run(_ key: String,
             _ work: @escaping @Sendable () async throws -> String) async throws -> String {
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await work() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }
}
