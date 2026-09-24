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

/// TWITCH REQUIRES AN HOURLY `/oauth2/validate` WHILE A TOKEN IS IN USE
/// (launch audit B; Twitch's "Validating requests"). A token the host revoked
/// at twitch.tv stays in the Keychain until something asks, and an app that
/// never asks keeps presenting it. `token(for: .twitch)` consults this clock,
/// so every caller — the viewer count every 60 s, a chapter marker, the
/// go-live read — carries the check without having to remember it.
actor StudioValidationClock {
    static let interval: TimeInterval = 3600
    private var last: [String: Date] = [:]

    func isDue(_ key: String, now: Date = Date()) -> Bool {
        guard let t = last[key] else { return true }
        return now.timeIntervalSince(t) >= Self.interval
    }

    func mark(_ key: String, at now: Date = Date()) { last[key] = now }

    enum Verdict: Equatable { case valid, revoked, unknown }

    /// Only a 401 ends a sign-in. A 5xx, a timeout or no network says nothing
    /// about the token, and clearing it then would sign a host out mid-show
    /// because their Wi-Fi hiccupped.
    static func verdict(status: Int?) -> Verdict {
        switch status {
        case .some(200..<300): .valid
        case .some(401): .revoked
        default: .unknown
        }
    }
}
