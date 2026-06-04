import Foundation
import AuthenticationServices
import Observation

// #11 (Decision 022): Sign in with Apple — the only auth, no external providers.
// Sign-in is OPTIONAL: it gates only cross-Apple-TV sync (Decision 009's "no
// funnel" spirit), never browsing or playback. Holds the stable Apple user id
// (not a secret — a UserDefaults stash is fine) and drives CloudKit sync.
@MainActor
@Observable
final class AccountStore {
    private(set) var appleUserID: String?
    var isSignedIn: Bool { appleUserID != nil }

    private let key = "appleUserID"

    init() { appleUserID = UserDefaults.standard.string(forKey: key) }

    /// Configure the Sign in with Apple request (no scopes needed — we only want
    /// the stable user identifier for the CloudKit zone).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = []
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        appleUserID = cred.user
        UserDefaults.standard.set(cred.user, forKey: key)
    }

    func signOut() {
        appleUserID = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}
