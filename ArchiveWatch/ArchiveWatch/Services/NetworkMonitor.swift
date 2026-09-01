#if os(iOS) || os(macOS)
import Foundation
import Network

// Is there a network at all? (Decision 099.)
//
// The app has never asked before, and did not need to: every surface either
// worked from the local catalog DB or failed with its own error. Downloads
// change that — with films on disk there is a real, useful app to be had with
// the radio off, and the difference has to be visible: a Play button that
// cannot work should say so BEFORE it is pressed, not spin and time out.
//
// `NWPathMonitor` is the native answer and the only one: there is no supported
// "reachability" API beyond it, and a probe request would answer a different
// question (can we reach THAT host right now) more slowly and less reliably.
//
// A monitor reports `.satisfied` for a captive-portal wifi that serves nothing,
// so this is a floor, not a guarantee — which is why nothing here GATES
// playback. It selects what the app says, while the network layer stays the
// authority on what actually worked.
@MainActor
@Observable
final class NetworkMonitor {

    static let shared = NetworkMonitor()

    /// Starts true so a launch never flashes an offline banner before the
    /// first path update arrives.
    private(set) var isOnline = true
    /// Cellular or a personal hotspot — what a several-hundred-megabyte
    /// download needs to know before it starts spending someone's plan.
    private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in
                guard let self else { return }
                if self.isOnline != online { self.isOnline = online }
                if self.isExpensive != expensive { self.isExpensive = expensive }
            }
        }
        monitor.start(queue: DispatchQueue(label: "aw.network.monitor"))
    }
}
#endif
