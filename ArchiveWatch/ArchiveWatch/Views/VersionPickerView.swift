#if os(tvOS)
import SwiftUI

// Choose which copy of a film to play (owner, 2026-08-17).
//
// The learning-orientation test (CLAUDE.md) is why the labels are literal —
// `480p · H.264 · 575 MB — Archive derivative`, never "Best" or "Auto". A
// viewer who opens this once learns something true about the Internet
// Archive: the same film exists there in several conditions, scanned and
// re-encoded by different people at different times. A screen that hid that
// behind a quality grade would make the choice for them and teach nothing.
struct VersionPickerView: View {
    let archiveID: String
    let versions: [ArchiveVersions.Version]
    let isLoading: Bool
    /// The copy the pipeline picked, so "what am I watching now?" is answerable
    /// even before the viewer has ever chosen.
    let pipelineChoiceName: String?
    let onChoose: (ArchiveVersions.Version?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose Version")
                    .scaledFont(46, weight: .bold)
                // Only a fact the viewer cannot see from the list. The old
                // paragraph explained the control, claimed "more than one
                // transfer" over a single copy, and was cut to one line.
                if !isLoading, versions.count == 1 {
                    Text("This is the only copy on the Internet Archive.")
                        .scaledFont(24)
                        .foregroundStyle(.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isLoading && versions.isEmpty {
                ProgressView().padding(.vertical, 40)
            } else if versions.isEmpty {
                // Universal feature states: an empty result here means the
                // Archive did not answer, which is a different thing from
                // "there is only one copy" and should not be dressed up as it.
                Text("Couldn't reach the Internet Archive for this title's file "
                     + "list. The film still plays — try again in a moment.")
                    .scaledFont(24)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: 900, alignment: .leading)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(versions) { version in
                            Button {
                                let isReselect = chosen == version.choiceKey
                                chosen = isReselect ? nil : version.choiceKey
                                onChoose(isReselect ? nil : version)
                                dismiss()
                            } label: {
                                row(for: version)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.ignoresSafeArea())
        .onAppear { chosen = ArchiveVersions.chosenName(for: archiveID) }
    }

    private func row(for version: ArchiveVersions.Version) -> some View {
        HStack(spacing: 20) {
            // The check marks what PLAYS: the viewer's choice, or with none
            // made, the default (it showed an empty circle beside "Currently
            // playing by default").
            let playing = chosen.map { $0 == version.choiceKey }
                ?? (!version.isOtherUpload && version.name == pipelineChoiceName)
            Image(systemName: playing ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(playing ? .white : .white.opacity(0.35))
            VStack(alignment: .leading, spacing: 4) {
                Text(version.label)
                    .scaledFont(26, weight: .medium)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !version.isOtherUpload, version.name == pipelineChoiceName {
                    Text("Currently playing by default")
                        .scaledFont(20)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
