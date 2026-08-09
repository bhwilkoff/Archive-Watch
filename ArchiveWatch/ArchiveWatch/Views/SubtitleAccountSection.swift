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
            TextField("OpenSubtitles username", text: $username)
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
            Link("Create a free account", destination: URL(string: "https://www.opensubtitles.com/en/users/sign_up")!)
                .font(.footnote)
        }
    }
}

/// Automatic captions row — shown only where the on-device engine exists.
struct AutoCaptionsSettingsSection: View {
    @AppStorage("autoCaptionsEnabled") private var enabled = false

    var body: some View {
        if AutoCaptions.isSupported {
            Section {
                Toggle("Offer automatic captions", isOn: $enabled)
            } header: {
                Text("Automatic Captions")
            } footer: {
                // Say what they are. A machine transcript of eighty-year-old
                // audio is sometimes wrong, and the viewer deserves to know that
                // before they rely on it — the reason these were withdrawn once.
                Text("When a film has no subtitles, Archive Watch can transcribe it on this device. Nothing is uploaded. Automatic captions are labelled as such, are never offered for silent films, and are discarded when the audio is too poor to transcribe well.")
            }
        }
    }
}
