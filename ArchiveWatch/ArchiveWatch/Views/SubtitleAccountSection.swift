import SwiftUI

// The "Subtitles" Settings section, shared by all three Apple platforms.
//
// One `Section` rather than three copies: every platform's Settings is already a
// `Form`, so the same view lands natively inside each — grouped insets on iOS,
// the focusable ten-foot rows on tvOS, the preferences pane on macOS — while the
// wording and the states stay identical.
//
// It asks ONLY for a username and password. The Api-Key ships in the bundle, so
// the viewer never meets one; and because the download quota follows the
// signed-in ACCOUNT (only per-second request throughput is shared), their
// allowance is theirs alone. The section shows the number the API reports for
// their account rather than one we hardcode — the free allowance has changed
// repeatedly over the years.
struct SubtitleAccountSection: View {
    @State private var account = SubtitleAccount.shared
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focused: Field?

    private enum Field { case user, pass }

    var body: some View {
        Section {
            if !SubtitleAccount.isAvailable {
                // A build without the key: say so plainly instead of showing a
                // sign-in that could never succeed.
                Label("Subtitle search isn't available in this build.",
                      systemImage: "captions.bubble")
                    .foregroundStyle(.secondary)
            } else if account.isConnected {
                connected
            } else {
                signIn
            }
        } header: {
            Text("Subtitles")
        } footer: {
            Text(account.isConnected
                 ? "Archive Watch will look for subtitles on OpenSubtitles when a film has none. Downloads count against your own account."
                 : "Connect a free OpenSubtitles account to find subtitles for films that don't have them. Your daily download allowance is your own — it isn't shared with other viewers.")
        }
    }

    private var connected: some View {
        Group {
            LabeledContent("Account", value: account.username)
            if let q = account.quota {
                LabeledContent("Downloads today",
                               value: "\(max(0, q.allowed - q.remaining)) of \(q.allowed) used")
                if q.remaining == 0 {
                    Text("You've used today's downloads. The allowance resets every 24 hours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Button("Disconnect", role: .destructive) { account.disconnect() }
        }
    }

    private var signIn: some View {
        Group {
            // Say "not your email" up front. OpenSubtitles rejects an email in
            // this field, and it is the single most likely thing a person types.
            TextField("OpenSubtitles username (not your email)", text: $username)
                .textContentType(.username)
                .focused($focused, equals: .user)
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .disableAutocorrection(true)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .focused($focused, equals: .pass)
            Button {
                Task {
                    let u = username, p = password
                    if await account.connect(username: u, password: p) { password = "" }
                }
            } label: {
                if account.isWorking { ProgressView() } else { Text("Connect") }
            }
            .disabled(username.isEmpty || password.isEmpty || account.isWorking)

            if let err = account.lastError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
            #if os(tvOS)
            // A `Link` on tvOS renders as a focusable button that does NOTHING
            // when pressed — there is no browser to hand the URL to. The QR is
            // the mechanism here (the donate section's precedent, Decision
            // 010): the account gets created on the phone, the credentials get
            // typed here.
            HStack(alignment: .center, spacing: 20) {
                QRCode(string: "https://www.opensubtitles.com/en/users/sign_up")
                    .frame(width: 120, height: 120)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
                Text("No account yet? Scan to create a free one on your phone, "
                     + "then sign in here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #else
            Link("Create a free account", destination: URL(string: "https://www.opensubtitles.com/en/users/sign_up")!)
                .font(.footnote)
            #endif
        }
    }
}

/// Automatic captions — what they are and where to find them.
///
/// This was a "Offer automatic captions" TOGGLE, and the toggle was read
/// nowhere: switching it on did nothing at all, while its wording implied the
/// app would start captioning films. That is worse than having no control,
/// because it answers "why don't I see subtitles?" with a reassuring lie.
///
/// There is nothing for a global preference to gate. Transcribing is a
/// deliberate, per-film action that already asks for confirmation and states
/// what it will download, so a switch in Settings could only duplicate that
/// consent. What Settings owes the viewer here is an accurate account of what
/// exists and where the button is.
struct AutoCaptionsSettingsSection: View {
    @State private var showDiagnostics = false

    var body: some View {
        if AutoCaptions.isSupported {
            Section {
                Label("Open a film, then choose Subtitles.", systemImage: "captions.bubble")
                    .foregroundStyle(.secondary)
                // The device reports its own caption behaviour, on screen —
                // an Apple TV's console cannot be read from a development
                // machine, and this is how the tvOS 27 generated-subtitles
                // question finally gets answered on the device it concerns
                // (Decision 067) instead of inferred from a Mac.
                Button {
                    showDiagnostics = true
                } label: {
                    Label("Caption Diagnostics", systemImage: "stethoscope")
                }
                .sheet(isPresented: $showDiagnostics) {
                    CaptionDiagnosticsView()
                        #if os(macOS)
                        .frame(minWidth: 560, minHeight: 420)
                        #endif
                }
            } header: {
                Text("Automatic Captions")
            } footer: {
                // A machine transcript of eighty-year-old audio is sometimes
                // wrong, and the viewer deserves to know that before relying on
                // it — the reason these were withdrawn once (Decision 039b).
                Text("When a film has no subtitles, this device can transcribe it. The film is downloaded first and nothing is uploaded. Automatic captions are labelled as such, are never offered for silent films, and are discarded when the audio is too poor to transcribe well.")
            }
        }
    }
}
