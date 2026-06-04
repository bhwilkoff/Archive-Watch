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
    // Last sign-in failure, surfaced in Settings. Most commonly this is the
    // missing "Sign in with Apple" capability on the App ID (the request errors
    // out immediately) — without it the button looked like it did nothing.
    private(set) var signInError: String?

    private let key = "appleUserID"

    init() { appleUserID = UserDefaults.standard.string(forKey: key) }

    /// Configure the Sign in with Apple request (no scopes needed — we only want
    /// the stable user identifier for the CloudKit zone).
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = []
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            appleUserID = cred.user
            UserDefaults.standard.set(cred.user, forKey: key)
            signInError = nil
        case .failure(let error):
            // User-cancelled is not an error worth showing.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                signInError = nil
            } else {
                signInError = error.localizedDescription
            }
        }
    }

    func signOut() {
        appleUserID = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}
