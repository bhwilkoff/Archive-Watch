import Foundation

/**
 The Studio's DEBUG doors, in ONE place because they were in the wrong one.

 The `AW_STUDIO_AUTH` door lived in `Views/RootView.swift`, which is the **tvOS**
 root — iOS has `RootView_iOS` and macOS has `RootView_macOS`. So on an iPhone
 the door was not shut, it was not there, and four launches in a row were read
 as "the harness cannot deliver environment variables" when nothing had been
 asked. A speculative fix for that non-problem went into the codebase as a
 comment asserting `devicectl` was broken; it was removed rather than left to
 be believed later.

 This is the same shape as §6.3's idle timer (implemented only in `StudioLab`,
 so tvOS never had it), §6.2's audio session (the same), and the Android studio
 bench door (collected only in `TvAppRoot`, found the same day) — a capability
 that exists on one platform's surface and is believed to exist everywhere.
 A door belongs beside the engine it opens, not beside one platform's view.
 */
enum StudioDoors {

    /// Environment first, then a launch argument: a harness may have only one.
    /// `devicectl` takes `-e`; an Xcode scheme and `simctl` take `-key value`,
    /// which UserDefaults parses for free.
    static var authDoor: String {
        ProcessInfo.processInfo.environment["AW_STUDIO_AUTH"]
            ?? UserDefaults.standard.string(forKey: "AW_STUDIO_AUTH") ?? ""
    }

    /// Read-only: what is this device signed in to, and is it ready to go live?
    /// Creates nothing and writes nothing. It exists because "the iPhone is
    /// blocked on a sign-in" had been carried across sessions as an assumption
    /// that no run had ever tested.
    ///
    /// Returns true when it handled the launch, so a caller can stop.
    @MainActor
    static func runStateProbeIfAsked() async -> Bool {
        #if DEBUG
        // `audience:youtube:<videoID>` / `audience:twitch:<login>` — reads a
        // REAL live stream's count through the product's own parser (§D27).
        // Read-only; one YouTube quota unit.
        if authDoor.hasPrefix("audience:") {
            let parts = authDoor.split(separator: ":").map(String.init)
            guard parts.count == 3 else { return false }
            var ref: StudioBroadcastRef?
            awdiag("AWAUDIENCE probe signedIn youtube=%@ twitch=%@",
                   StudioPlatformAuth.isSignedIn(.youtube) ? "y" : "n",
                   StudioPlatformAuth.isSignedIn(.twitch) ? "y" : "n")
            if parts[1] == "youtube" {
                ref = .youtube(parts[2])
                // The product swallows a failed read as "not reported"; the
                // probe must not, or "unknown" hides WHICH layer said no.
                do {
                    let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
                    let n = try await yt.concurrentViewers(videoID: parts[2])
                    awdiag("AWAUDIENCE probe raw youtube=%@", n.map(String.init) ?? "absent")
                } catch { awdiag("AWAUDIENCE probe youtube error: %@", "\(error)") }
            }
            if parts[1] == "twitch",
               let token = try? await StudioPlatformAuth.token(for: .twitch),
               let cid = StudioPlatformAuth.clientID(for: .twitch),
               let id = try? await TwitchLive(token: token, clientID: cid).userID(login: parts[2]) {
                ref = .twitch(userID: id)
            }
            let n: Int? = if let ref { await StudioAudience.count(ref) } else { nil }
            awdiag("AWAUDIENCE probe %@ %@ watching=%@", parts[1], parts[2],
                   n.map(String.init) ?? "unknown")
            return true
        }
        if authDoor == "youtube-upcoming" {
            do {
                let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
                let list = try await yt.debugUpcoming()
                awdiag("AWUPCOMING %d upcoming broadcast(s)", list.count)
                for b in list { awdiag("AWUPCOMING %@ %@ \"%@\"", b.id, b.status, b.title) }
            } catch { awdiag("AWUPCOMING failed — %@", "\(error)") }
            return true
        }
        guard authDoor == "state" else { return false }
        for platform in [StudioPlatformAuth.Platform.youtube, .twitch] {
            let configured = StudioPlatformAuth.clientID(for: platform) != nil
            let signedIn = StudioPlatformAuth.isSignedIn(platform)
            awdiag("AWAUTH %@ configured=%@ signedIn=%@",
                   String(describing: platform),
                   configured ? "true" : "false", signedIn ? "true" : "false")
            guard signedIn else { continue }
            switch platform {
            case .youtube:
                if let who = try? await StudioPlatformAuth.youTubeAccount() {
                    awdiag("AWAUTH youtube account id=%@ title=%@", who.id, who.title)
                }
            case .twitch:
                if let who = try? await StudioPlatformAuth.twitchAccount() {
                    awdiag("AWAUTH twitch login=%@ scopes=%@",
                           who.login, who.scopes.joined(separator: ","))
                }
            }
            let readiness = try? await StudioPlatformAuth.readiness(for: platform)
            awdiag("AWAUTH %@ readiness=%@",
                   String(describing: platform), String(describing: readiness))
        }
        awdiag("AWAUTH state probe complete")
        return true
        #else
        return false
        #endif
    }

    /// The go-live door's raw value: `1`, `twitch` or `youtube`.
    static var goLiveDoor: String {
        ProcessInfo.processInfo.environment["AW_STUDIO_GOLIVE"]
            ?? UserDefaults.standard.string(forKey: "AW_STUDIO_GOLIVE") ?? ""
    }

    /// The request a host's go-live sheet would have produced, built from the
    /// door. PURE — it creates no broadcast and touches no network.
    ///
    /// The first version of this resolved the destination and armed
    /// `StudioSession` directly, copying the macOS door. That is right on
    /// macOS, where the player window reads the armed session, and WRONG on
    /// iOS, where the Studio is presented as a `fullScreenCover(item:)` bound
    /// to a `GoLiveRequest` and the container resolves the destination itself.
    /// The mismatch was not a compile error and not a crash: the door armed a
    /// session nothing read, `AW_AUTOPLAY` opened the PLAIN player, the film
    /// played happily, and a real unlisted YouTube broadcast was created and
    /// abandoned. Presenting the same request the sheet presents is the only
    /// way a door tests the product rather than a parallel path.
    ///
    ///   AW_STUDIO_GOLIVE = 1 | twitch | youtube
    ///   AW_STUDIO_LAYOUT = film | corner | theatre | side | host
    static func goLiveRequest(film: Catalog.Item) -> GoLiveRequest? {
        #if DEBUG
        let door = goLiveDoor
        guard !door.isEmpty else { return nil }
        let env = ProcessInfo.processInfo.environment
        let layout = StudioLayout(rawValue: env["AW_STUDIO_LAYOUT"] ?? "") ?? .corner
        let platform: GoLivePlatform
        switch door {
        case "twitch": platform = .twitch
        case "youtube": platform = .youtube
        case "1": platform = .custom      // the bench server, not a platform
        default:
            awdiag("AWDOOR REFUSED: unknown door value %@", door); return nil
        }
        awdiag("AWDOOR go-live request %@ door=%@ layout=%@",
               film.archiveID, door, layout.rawValue)
        return GoLiveRequest(
            archiveID: film.archiveID, platform: platform,
            title: film.title, category: "", privacy: .unlisted,
            layout: layout,
            customServer: door == "1" ? env["AW_STUDIO_DEST"].flatMap(URL.init(string:)) : nil,
            customKey: door == "1" ? (env["AW_STUDIO_KEY"] ?? "bench") : nil)
        #else
        return nil
        #endif
    }
}
