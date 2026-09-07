#if os(tvOS)
import AVFoundation
import Foundation

/// Keeps the Apple TV's audio session alive for the life of a playback session.
///
/// THE DEFECT THIS FIXES. The owner: "the audio keeps going out. I'll watch for
/// about 5 minutes and then the audio goes out. If I resume the movie again
/// from the detail view, the audio comes back. It isn't just this movie."
///
/// Measured on the Bedroom Apple TV across two full runs, at the moment audio
/// died: the buffer was HEALTHY (75-89s ahead), `rate` was 1.00, `stalls` was
/// 0, the item's error log was EMPTY, and the player item was never swapped
/// (one pointer for the whole run). Video kept advancing normally. Nothing in
/// the delivery path was wrong, which is what ruled out the starvation theory
/// that a first pass at this had blamed.
///
/// What was missing is this file. tvOS had NO audio-session handling at all --
/// no category, no activation, and no interruption observer -- while
/// `PlayerView_iOS` has had the full treatment for months. When something
/// interrupts the session (a system sound, Siri, an HDMI/eARC route change),
/// tvOS deactivates it; video needs no session and plays on, and with nobody
/// to call `setActive(true)` when the interruption ENDS the audio never comes
/// back. Reopening from Detail builds a new player, which is exactly the
/// workaround the owner found.
///
/// This is the repo's recurring shape, recorded in the 2026-08-12 audit:
/// "parity that landed on iOS/Android without returning to the platform it
/// started on."
///
/// It LOGS every session event unconditionally (`awdiag`), because an
/// interruption is rare, invisible from the app, and the only way to confirm
/// the mechanism on a device whose console we can read but whose living room
/// we cannot.
@MainActor
final class TVAudioSession {
    static let shared = TVAudioSession()

    private var interruption: NSObjectProtocol?
    private var routeChange: NSObjectProtocol?
    private var clients = 0
    private weak var player: AVPlayer?
    private var probe: Timer?
    private var lastSignature = ""
    private var lastReassert = Date.distantPast

    /// Health probe cadence, and how often the session is re-asserted.
    private static let probeEvery: TimeInterval = 2
    private static let reassertEvery: TimeInterval = 20

    /// Call when a player takes the screen. Reference-counted, because the
    /// movie and episode containers can hand over to one another.
    func begin(player: AVPlayer?) {
        self.player = player
        clients += 1
        activate(reason: "begin")
        startProbe()
        guard interruption == nil else { return }

        // Notification is not Sendable, so the primitives come out here and
        // the isolated work happens inside assumeIsolated -- the same shape
        // PlayerView_iOS uses for this exact observer.
        interruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main) { note in
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    TVAudioSession.shared.handle(typeRaw: typeRaw, optionsRaw: optsRaw)
                }
            }

        // A route change is the other way an Apple TV loses its output: an
        // AV receiver renegotiating, eARC dropping, a TV waking a soundbar.
        // The session survives the reason codes we can act on only if we
        // reactivate, and the log tells us which reason we are seeing.
        routeChange = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(), queue: .main) { note in
                let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated {
                    TVAudioSession.shared.handleRoute(reasonRaw: reasonRaw)
                }
            }
    }

    /// Call when a player leaves the screen. The observers are kept until the
    /// last client goes, so a movie -> next-episode handover never has a gap
    /// in which an interruption would go unheard.
    func end() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        if let routeChange { NotificationCenter.default.removeObserver(routeChange) }
        interruption = nil
        routeChange = nil
        probe?.invalidate()
        probe = nil
        lastSignature = ""
        player = nil
    }

    // MARK: - Health probe

    /// READ-ONLY, on purpose. The obvious instrument -- an
    /// MTAudioProcessingTap on the playing item -- cannot be used as a
    /// detector here: tvOS tears taps down on heavy-decode items regardless
    /// (17s on a 4K film), so tap silence does NOT mean silence, and the
    /// watchdog that once re-attached a tap to revive it WAS itself a
    /// rhythmic audio dropout (see the note in ResilientStreamLoader). So
    /// this samples only properties, writes nothing into the render, and
    /// logs a line just when something CHANGES -- plus a heartbeat, so a
    /// perfectly steady run is still distinguishable from a dead probe.
    private func startProbe() {
        guard probe == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: Self.probeEvery,
                                     repeats: true) { _ in
            MainActor.assumeIsolated { TVAudioSession.shared.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        probe = t
    }

    private func sample() {
        let s = AVAudioSession.sharedInstance()
        let outs = s.currentRoute.outputs
        // The TYPE alone is not enough to tell a HomePod from the television:
        // tvOS can report an AirPlay port for its own HDMI output, so the
        // NAME is what distinguishes "the TV" from "a speaker across the
        // room" -- and that distinction decides whether a mid-film silence
        // is a wireless link dropping or something local.
        let port = (outs.first?.portType.rawValue ?? "none")
                 + ":" + (outs.first?.portName ?? "-")
                 + (outs.count > 1 ? "+\(outs.count - 1)more" : "")
        let chans = s.outputNumberOfChannels
        // The audio TRACK as the player sees it: if tvOS drops the audible
        // renderer, this is where it should show, and it costs nothing to ask.
        var trackState = "n/a"
        if let item = player?.currentItem {
            let audio = item.tracks.filter { $0.assetTrack?.mediaType == .audio }
            trackState = "\(audio.count)tk enabled=\(audio.first?.isEnabled.description ?? "-")"
        }
        let sig = "\(port)|ch=\(chans)|\(trackState)|mute=\(player?.isMuted ?? false)"
              + "|vol=\(player?.volume ?? -1)|other=\(s.isOtherAudioPlaying)"
        if sig != lastSignature {
            awdiag("AWAUDHEALTH CHANGED %@  (was: %@)", sig,
                   lastSignature.isEmpty ? "first sample" : lastSignature)
            lastSignature = sig
        }

        // THE CANDIDATE FIX. On this tvOS 27.0 beta (24J5360a) the audio dies
        // mid-film with a healthy buffer, no error-log entry, no item swap and
        // -- measured -- no interruption notification at all, while a second
        // Apple TV on a public build plays the same film and build fine. A
        // session that has been deactivated WITHOUT posting the notification
        // would look exactly like that, and would be invisible to every
        // observer we have. Re-asserting is idempotent when the session is
        // already active, so it is cheap to hold the session continuously
        // rather than trust an event that may never arrive.
        if Date().timeIntervalSince(lastReassert) >= Self.reassertEvery {
            lastReassert = Date()
            let wasActive = sig
            do {
                try s.setActive(true)
            } catch {
                awdiag("AWAUDSESS re-assert FAILED: %@", error.localizedDescription)
                return
            }
            // Only worth a line when it actually changed something.
            let now = AVAudioSession.sharedInstance()
            if now.outputNumberOfChannels != chans {
                awdiag("AWAUDSESS re-assert CHANGED channels %ld -> %ld (%@)",
                       chans, now.outputNumberOfChannels, wasActive)
            }
        }
    }

    private func activate(reason: String) {
        let s = AVAudioSession.sharedInstance()
        do {
            // .playback + .moviePlayback is what a video app is meant to
            // declare, and it is what makes recovery well defined: an
            // un-declared session has no documented post-interruption state.
            try s.setCategory(.playback, mode: .moviePlayback)
            try s.setActive(true)
            awdiag("AWAUDSESS active (%@)", reason)
        } catch {
            awdiag("AWAUDSESS activate FAILED (%@): %@", reason,
                   error.localizedDescription)
        }
    }

    private func handle(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            // The system has already silenced us; say so, so the console
            // shows the cause next to the moment the viewer loses audio.
            awdiag("AWAUDSESS interruption BEGAN")
        case .ended:
            awdiag("AWAUDSESS interruption ENDED — reactivating")
            activate(reason: "interruption ended")
            let opts = optionsRaw.map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            // Only resume if the system says we should; a viewer who paused
            // during the interruption must stay paused.
            if opts.contains(.shouldResume), player?.rate == 0 { player?.play() }
        @unknown default:
            break
        }
    }

    private func handleRoute(reasonRaw: UInt?) {
        let reason = reasonRaw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
        awdiag("AWAUDSESS route change (reason %ld)", Int(reasonRaw ?? 0))
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .routeConfigurationChange,
             .override, .categoryChange:
            // Reactivating on a route change is cheap and idempotent, and it
            // is the case an eARC/receiver renegotiation lands in.
            activate(reason: "route change")
        default:
            break
        }
    }
}
#endif
