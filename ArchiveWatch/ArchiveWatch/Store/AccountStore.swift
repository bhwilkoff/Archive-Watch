import Foundation
import AuthenticationServices
import Observation
import UIKit

// #11 (Decision 022): Sign in with Apple — the only auth, no external providers.
// Sign-in is OPTIONAL: it gates only cross-Apple-TV sync (Decision 009's "no
// funnel" spirit), never browsing or playback. Holds the stable Apple user id
// (not a secret — a UserDefaults stash is fine) and drives CloudKit sync.
//
// IMPORTANT (tvOS): we drive the flow through a UIKit ASAuthorizationController
// with an explicit presentation anchor, NOT SwiftUI's `SignInWithAppleButton`.
// On tvOS that button frequently does NOTHING — it can't resolve a presentation
// context inside a List/Form, so the authorization sheet never appears. Owning
// the controller + supplying the key window as the anchor makes it present
// reliably. (Verified symptom on a TestFlight device: button clicked, nothing.)
@MainActor
@Observable
final class AccountStore {
    private(set) var appleUserID: String?
    var isSignedIn: Bool { appleUserID != nil }
    // Last sign-in failure, surfaced in Settings.
    private(set) var signInError: String?

    private let key = "appleUserID"
    private let coordinator = SignInCoordinator()

    init() { appleUserID = UserDefaults.standard.string(forKey: key) }

    /// Begin Sign in with Apple. Presents the system sheet via our own
    /// ASAuthorizationController (see type note above).
    func startSignIn() {
        signInError = nil
        coordinator.start { [weak self] result in
            Task { @MainActor in self?.handle(result) }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                signInError = "Unexpected credential type."
                return
            }
            appleUserID = cred.user
            UserDefaults.standard.set(cred.user, forKey: key)
            signInError = nil
        case .failure(let error):
            // User-cancelled / unknown-with-no-account are not worth alarming on.
            let code = (error as NSError).code
            if code == ASAuthorizationError.canceled.rawValue {
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

// UIKit bridge: performs the Apple ID request and supplies the presentation
// anchor tvOS needs. Kept separate from the @Observable store so the NSObject /
// delegate conformances don't tangle with observation.
private final class SignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var onResult: ((Result<ASAuthorization, Error>) -> Void)?

    func start(onResult: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onResult = onResult
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []   // identifier only; we don't need name/email
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithAuthorization authorization: ASAuthorization) {
        onResult?(.success(authorization)); onResult = nil
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithError error: Error) {
        onResult?(.failure(error)); onResult = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? scenes.flatMap { $0.windows }.first
        return window ?? ASPresentationAnchor()
    }
}
