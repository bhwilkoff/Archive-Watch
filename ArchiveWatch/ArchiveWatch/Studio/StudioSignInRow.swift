#if os(iOS) || os(macOS) || os(tvOS)
import SwiftUI

// The one row in the go-live sheet that says who the broadcast goes out as
// (iOS-DESIGN §8.9, in the §8.5 form-sheet pattern). NOT a new surface.
//
// SHARED between iOS and macOS, and living in Studio/ for that reason. Rule
// B13g approved a Mac go-live sheet that is "the same sheet as iOS" and listed
// what it carries — the rights refusal, THE SIGN-IN ROW, §3.4a's warning, the
// title — and B13c's reason for mirroring rather than reinventing applies
// exactly here: a second copy of this row would be a second chance to get the
// sign-in and rights copy wrong. It was `#if os(iOS)` and lived in iOS/ only
// because the Mac had no way to sign in (§9.sss); it was moved, not rewritten.
//
// tvOS joined on 2026-09-18, when the owner answered Rule 8.8a's third
// question with "figure out the sign in path on the tv and implement it".
// The auth layer already supported it: `present(url:scheme:)` guards
// `presentationContextProvider` and `prefersEphemeralWebBrowserSession` with
// `#if !os(tvOS)` because both are `API_UNAVAILABLE(tvos)`, while the session
// class is `tvos(16.0)` and `start()` carries no annotation at all. What did
// NOT exist was any surface to call it from.
//
// One promise this row must not make on a television: a started
// `ASWebAuthenticationSession` cannot be cancelled programmatically there
// (`cancel` is `API_UNAVAILABLE(tvos)`). The Cancel button below belongs to
// TWITCH's device flow, which is our own poll loop and genuinely cancellable —
// so it is honest on every platform. YouTube's sheet is dismissed by the
// system, not by us.
//
// It has to carry three different states, and collapsing any two of them is
// how a host ends up pressing a button that cannot work:
//
//   · the build has no client id      → say so, and say whose job it is
//   · signed out                      → a button
//   · signed in                       → who, and a way out
//
// And the two platforms sign in DIFFERENTLY, which is visible here because it
// has to be. YouTube opens Google's own page. Twitch shows a code to confirm
// on another device — the only flow Twitch offers a client that holds no
// secret (see Studio/StudioPlatformAuth.swift). A host meeting the code with
// no explanation would reasonably think something had gone wrong, so the
// screen explains it rather than just displaying it.

struct StudioSignInRow: View {
    /// #FF5C35, the marquee orange of CLAUDE.md's brand block. Written out
    /// rather than read from `Brand`, which is defined in iOS/Design_iOS.swift
    /// and so does not exist in the Mac target.
    static let signedInAccent = Color(red: 1.0, green: 0.361, blue: 0.208)

    let platform: StudioPlatformAuth.Platform

    /// Reported upward so the surrounding sheet can gate its own Go Live.
    /// `isSignedIn` is a Keychain read, not observable state: a sheet that
    /// asked once would keep the answer it got BEFORE the host signed in, and
    /// leave the control disabled behind a row that says "Signed in".
    var onSignedInChange: ((Bool) -> Void)? = nil

    @State private var signedIn: Bool = false
    @State private var working = false
    @State private var problem: String?
    @State private var pending: DeviceCode?

    /// A device-flow prompt from EITHER platform.
    ///
    /// Twitch always had one; YouTube has one on a television now (tvOS-DESIGN
    /// Rule 8.8a's 2026-09-18 amendment). Wrapping the two `Pending` types here
    /// rather than unifying them in the auth layer is deliberate: the flows are
    /// genuinely different where it matters — Google needs a client secret,
    /// answers with an `error` field, and publishes no code-bearing URI — and
    /// flattening that into one struct would hide the differences the polling
    /// code has to respect. What the SCREEN needs is only these two strings.
    private enum DeviceCode {
        case twitch(TwitchDeviceAuth.Pending)
        case google(GoogleDeviceAuth.Pending)

        var verificationURI: String {
            switch self {
            case .twitch(let p): return p.verificationURI
            case .google(let p): return p.verificationURI
            }
        }
        var userCode: String {
            switch self {
            case .twitch(let p): return p.userCode
            case .google(let p): return p.userCode
            }
        }
    }
    /// Held so it can be CANCELLED. A `Task {}` started in a button action is
    /// unstructured: SwiftUI cancels `.task {}` modifiers when a view goes
    /// away, and nothing at all for this one. Twitch's poll runs for the full
    /// life of the code — up to 30 minutes at one request every 5 seconds —
    /// so without this, "Cancel" hid the code and left ~360 requests running
    /// against Twitch, and so did dismissing the sheet (§9.sss).
    @State private var signInTask: Task<Void, Never>?
    /// The channel a broadcast would reach, once asked of the platform.
    @State private var accountName: String?
    /// What the platform says this signed-in account can actually DO.
    ///
    /// Owner, 2026-09-18, after signing in to the wrong Google account:
    /// "there was no indication that I was logged in wrong." There was not.
    /// The row named the channel and stopped there, so signed-in-and-usable
    /// and signed-in-and-BLOCKED drew identically, and the difference only
    /// appeared on pressing Go live. A name answers "who"; it does not answer
    /// "can this broadcast at all", and on an account that owns nineteen
    /// channels those are different questions.
    @State private var blockedNote: String?

    private var label: String { platform.displayName }

    /// "https://www.twitch.tv/activate?device-code=X" -> "twitch.tv/activate",
    /// which is what a person types. The query is deliberately dropped: it
    /// carries the code, and the code is already on screen in 40-point type.
    static func shortHost(_ uri: String) -> String {
        guard let c = URLComponents(string: uri), let host = c.host else { return uri }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return h + c.path
    }

    private func setSignedIn(_ value: Bool) {
        signedIn = value
        onSignedInChange?(value)
    }

    var body: some View {
        Group {
            if let configProblem = StudioPlatformAuth.configurationProblem(for: platform) {
                // Not an error the host caused, and not one they can fix by
                // retrying. It names the missing thing.
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sign-in is not set up", systemImage: "wrench.and.screwdriver")
                        .font(.subheadline.weight(.medium))
                        // Not interactive, so not accent-coloured: the List's
                        // default tint made the wrench read as a button on the
                        // glass, and the brand split reserves #0047FF for
                        // things you can press (CLAUDE.md).
                        .foregroundStyle(.secondary)
                    Text(configProblem)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if signedIn {
                HStack {
                    // WHOSE channel. "Signed in" says a token was stored; it
                    // does not say where the broadcast lands, and a host about
                    // to go out under their own name has exactly that question
                    // — more so with brand accounts, where one Google login can
                    // own several channels. Read-only (`channels.list`), and it
                    // fails quietly: an unnamed channel is a smaller problem
                    // than a sign-in row that refuses to draw.
                    Label(accountName.map { "\(label) — \($0)" }
                            ?? "Signed in to \(label)",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Self.signedInAccent)
                        .font(.subheadline)
                    Spacer()
                    Button("Sign out") {
                        StudioPlatformAuth.signOut(platform)
                        accountName = nil
                        blockedNote = nil
                        setSignedIn(false)
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
            } else if let p = pending {
                deviceCode(p)
            } else {
                Button {
                    signInTask = Task { await start() }
                } label: {
                    HStack {
                        Label("Sign in to \(label)", systemImage: "person.badge.key")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
                // REQUIRED, not explanatory: YouTube's API Services policy
                // asks every client to put its Terms of Service in front of a
                // user before they connect (launch audit A5).
                if platform == .youtube {
                    #if os(tvOS)
                    Text("By signing in you agree to the YouTube Terms of Service (youtube.com/t/terms).")
                        .font(.footnote).foregroundStyle(.secondary)
                    #else
                    Text("By signing in you agree to the [YouTube Terms of Service](https://www.youtube.com/t/terms).")
                        .font(.footnote).foregroundStyle(.secondary)
                    #endif
                }
            }

            if let blockedNote {
                Text(blockedNote)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onAppear { setSignedIn(StudioPlatformAuth.isSignedIn(platform)) }
        // `.task(id:)` so it re-asks when the host signs in, and is cancelled
        // with the view rather than outliving it (§9.sss).
        .task(id: signedIn) {
            guard signedIn else { blockedNote = nil; return }
            if accountName == nil {
                accountName = try? await StudioPlatformAuth.accountName(for: platform)
            }
            // Asked HERE, at sign-in, rather than only at go-live. Both reads
            // are cheap and neither creates anything on the host's channel.
            if case .blocked(let why)? = try? await StudioPlatformAuth.readiness(for: platform) {
                blockedNote = why
            } else {
                blockedNote = nil
            }
        }
        .onDisappear {
            // A host who closes the sheet has stopped asking. Leaving the poll
            // running is both a pointless load on Twitch and a task that
            // outlives the view it reports to.
            signInTask?.cancel()
            signInTask = nil
        }
    }

    /// Twitch's device flow, on screen. The code is useless without the
    /// address, and the address is useless without the deadline, so all three
    /// are shown together.
    ///
    /// ON A TELEVISION THE ADDRESS IS A QR CODE. The owner, 2026-09-18: "The
    /// sign in can make use of QR codes and signing in with a phone, but you
    /// are logging in on the TV using that other device." That is precisely
    /// what a device flow is — the phone authorises and the TOKEN lands here —
    /// and it is why this flow suits a television better than the web sheet
    /// tvOS-DESIGN §8.8a first reached for.
    ///
    /// Measured against the live endpoint rather than assumed (2026-09-18):
    /// Twitch's `verification_uri` comes back ALREADY carrying the code —
    /// `https://www.twitch.tv/activate?device-code=XXXXXXXX` — so a QR of it
    /// lands a phone on a page with the code filled in. RFC 8628's optional
    /// `verification_uri_complete` is not needed here because the plain URI
    /// already is complete. The code stays on screen beside it: a QR is
    /// useless to someone whose phone camera is not to hand, and reading
    /// eight characters aloud is the fallback that always works.
    private func deviceCode(_ p: DeviceCode) -> some View {
        HStack(alignment: .top, spacing: 28) {
        #if os(tvOS)
        VStack(spacing: 10) {
            QRCode(string: p.verificationURI)
                .frame(width: 220, height: 220)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
            Text("Scan with your phone")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        #endif
        VStack(alignment: .leading, spacing: 8) {
            // On a television the full URI is noise AND self-contradictory:
            // the capture from Ben Bedroom read "Open
            // https://www.twitch.tv/activate?device-code=XGXWLMNK and enter
            // this code:" above the code it already contained. The QR carries
            // the complete URI; the text beside it only has to name the place
            // for someone typing it by hand.
            #if os(tvOS)
            Text("Scan the code, or open \(Self.shortHost(p.verificationURI)) "
                 + "on your phone and enter:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #else
            Text("Open \(p.verificationURI) and enter this code:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            #endif
            Text(p.userCode)
                .font(.system(.title, design: .monospaced).weight(.bold))
                // `textSelection` does not exist on tvOS, and would mean
                // nothing there anyway: nobody copies text off a television.
                // The code is read aloud off the screen, which is why the
                // accessibility label spells it out character by character.
                #if !os(tvOS)
                .textSelection(.enabled)
                #endif
                .accessibilityLabel(p.userCode.map(String.init).joined(separator: " "))
            HStack(spacing: 6) {
                // `controlSize` is unavailable on tvOS.
                #if os(tvOS)
                ProgressView()
                #else
                ProgressView().controlSize(.small)
                #endif
                Text("Waiting for you to confirm on \(label)\u{2026}")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Cancel") {
                // Cancel the WORK, not just the picture of it. `poll` sleeps
                // between attempts, so cancellation lands within one interval.
                signInTask?.cancel()
                signInTask = nil
                pending = nil
            }
                .font(.subheadline)
                .buttonStyle(.borderless)
        }
        }
        .padding(.vertical, 4)
    }

    private func start() async {
        problem = nil
        working = true
        defer { working = false }
        do {
            switch platform {
            case .youtube:
                // A television signs in from a phone; a device with a keyboard
                // uses the web sheet. The auth layer owns which is which so
                // this reads as a question rather than an `#if`.
                if StudioPlatformAuth.youTubeUsesDeviceFlow {
                    let p = try await StudioPlatformAuth.beginYouTubeDeviceSignIn()
                    pending = .google(p)
                    try await StudioPlatformAuth.completeYouTubeDeviceSignIn(p)
                    pending = nil
                } else {
                    try await StudioPlatformAuth.signInToYouTube()
                }
                setSignedIn(true)
            case .twitch:
                let p = try await StudioPlatformAuth.beginTwitchSignIn()
                pending = .twitch(p)
                // The poll runs for as long as the code is valid. Cancelling
                // is explicit — see `signInTask`. This comment used to claim
                // "the sheet's own dismissal cancels this task", which was
                // simply untrue of an unstructured Task and had never been
                // exercised, because no client id existed to reach it.
                try await StudioPlatformAuth.completeTwitchSignIn(p)
                pending = nil
                setSignedIn(true)
            }
        } catch is CancellationError {
            pending = nil
        } catch {
            pending = nil
            problem = "\(error)"
        }
    }
}
#endif
