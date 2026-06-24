#if os(macOS)
import SwiftUI

// Text → Supercut (#9, the flagship). Type a phrase, find every moment across the public-domain
// catalog where it is spoken, pick the takes you want, and assemble them into the timeline as an
// EDITABLE set of candidate clips (Rule 5a — the editorial cut stays the human's; this only
// automates the search + gather). Line-level v1: each candidate is the spoken CUE containing the
// phrase; word-level isolation (SpeechTranscriber) is the refinement.
struct SupercutSheet: View {
    let model: EditorModel
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var results: [SubtitleCue] = []
    @State private var excluded: Set<String> = []
    @State private var index: SubtitleIndex?
    @State private var building = true
    @State private var searched = false

    private var included: [SubtitleCue] { results.filter { !excluded.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text → Supercut").font(.title3).bold()

            if building {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Indexing subtitles…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HStack {
                    TextField("A phrase that’s spoken on screen — e.g. “I love you”", text: $phrase)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(run)
                    Button("Find", action: run).keyboardShortcut(.defaultAction).disabled(phrase.isEmpty)
                }
                if let index { Text("\(index.cueCount.formatted()) lines indexed").font(.caption).foregroundStyle(.secondary) }

                if searched && results.isEmpty {
                    ContentUnavailableView("No spoken lines matched", systemImage: "text.magnifyingglass")
                        .frame(minHeight: 160)
                } else if !results.isEmpty {
                    List(results) { cue in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: excluded.contains(cue.id) ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(excluded.contains(cue.id) ? .secondary : Color.accentColor)
                                .onTapGesture {
                                    if excluded.contains(cue.id) { excluded.remove(cue.id) } else { excluded.insert(cue.id) }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cue.text).lineLimit(2)
                                Text("\(cue.title) · \(cue.timecode)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .frame(minHeight: 220)
                }
            }

            HStack {
                Text(results.isEmpty ? "" : "\(included.count) of \(results.count) selected")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add \(included.count) Clips") { build() }
                    .keyboardShortcut("b", modifiers: .command)
                    .disabled(included.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .task {
            await SubtitleIndexBuilder.ensureIndex(store: store)
            index = SubtitleIndex(path: SubtitleIndex.bestURL)
            building = false
        }
    }

    private func run() {
        guard let index, !phrase.isEmpty else { return }
        results = index.search(phrase)
        excluded.removeAll()
        searched = true
    }

    /// Assemble the selected cues into the timeline as editable candidates (in screen order).
    private func build() {
        for cue in included { model.addClip(from: cue.proxyClip) }
        dismiss()
    }
}
#endif
