#if os(iOS)
import SwiftUI

// The one row in the go-live sheet that says who the broadcast goes out as
// (iOS-DESIGN §8.9, in the §8.5 form-sheet pattern). NOT a new surface.
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
    let platform: StudioPlatformAuth.Platform

    @State private var signedIn: Bool = false
    @State private var working = false
    @State private var problem: String?
    @State private var pending: TwitchDeviceAuth.Pending?
    /// Held so it can be CANCELLED. A `Task {}` started in a button action is
    /// unstructured: SwiftUI cancels `.task {}` modifiers when a view goes
    /// away, and nothing at all for this one. Twitch's poll runs for the full
    /// life of the code — up to 30 minutes at one request every 5 seconds —
    /// so without this, "Cancel" hid the code and left ~360 requests running
    /// against Twitch, and so did dismissing the sheet (§9.sss).
    @State private var signInTask: Task<Void, Never>?

    private var label: String { platform.displayName }

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
                    Label("Signed in to \(label)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Brand.primary)
                        .font(.subheadline)
                    Spacer()
                    Button("Sign out") {
                        StudioPlatformAuth.signOut(platform)
                        signedIn = false
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }
            } else if let p = pending {
                twitchCode(p)
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
            }

            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
        }
        .onAppear { signedIn = StudioPlatformAuth.isSignedIn(platform) }
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
    private func twitchCode(_ p: TwitchDeviceAuth.Pending) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open \(p.verificationURI) and enter this code:")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(p.userCode)
                .font(.system(.title, design: .monospaced).weight(.bold))
                .textSelection(.enabled)
                .accessibilityLabel(p.userCode.map(String.init).joined(separator: " "))
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for you to confirm on Twitch\u{2026}")
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
        .padding(.vertical, 4)
    }

    private func start() async {
        problem = nil
        working = true
        defer { working = false }
        do {
            switch platform {
            case .youtube:
                try await StudioPlatformAuth.signInToYouTube()
                signedIn = true
            case .twitch:
                let p = try await StudioPlatformAuth.beginTwitchSignIn()
                pending = p
                // The poll runs for as long as the code is valid. Cancelling
                // is explicit — see `signInTask`. This comment used to claim
                // "the sheet's own dismissal cancels this task", which was
                // simply untrue of an unstructured Task and had never been
                // exercised, because no client id existed to reach it.
                try await StudioPlatformAuth.completeTwitchSignIn(p)
                pending = nil
                signedIn = true
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
