#if os(iOS)
import SwiftUI

// iPhone Duo adaptations (iOS-DESIGN §2.8). Each one is a no-op where its API
// does not exist, so an iOS 18 phone draws exactly what it drew before.

extension View {
    /// Art that reaches the trailing edge continues under the Duo's vertical
    /// strip of bars instead of stopping short of it (§2.8, "Art under the strip").
    @ViewBuilder
    func extendsUnderBars() -> some View {
        if #available(iOS 26, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }
}
#endif
