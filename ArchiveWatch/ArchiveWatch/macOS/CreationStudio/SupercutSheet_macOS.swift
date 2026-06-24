#if os(macOS)
import SwiftUI
import SwiftData
import CoreMedia

// Text → Supercut (#9, the flagship). Two modes:
//  • Find clips (v1): type a phrase, find every moment across the public-domain catalog where it's
//    spoken, pick the takes, assemble them as editable candidates.
//  • Compose a sentence (v2): type a line and the catalog SPEAKS it word-by-word, covered with the
//    fewest clips (longest-match), missing words surfaced as gaps (docs/research/
//    creation-studio-sentence-supercut.md).
// Either way the result is an EDITABLE timeline (Rule 5a — the editorial cut stays the human's).
struct SupercutSheet: View {
    let model: EditorModel
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    /// Add a batch of assembled takes to the timeline INSTANTLY (and the SwiftData Library, #12),
    /// then tighten/level them in the background (EditorModel.addSupercutClips). No per-clip
    /// blocking — 80 clips appear at once instead of crawling one-by-one.
    private func commit(_ takes: [EditorModel.SupercutTake]) {
        for t in takes { ctx.insert(LibraryClip(from: t.proxy)) }
        try? ctx.save()
        model.addSupercutClips(takes, tighten: tightenToWord, evenVolume: evenVolume)
        dismiss()
    }

    enum Mode: String, CaseIterable, Identifiable { case find = "Find clips", compose = "Compose a sentence"; var id: String { rawValue } }
    @State private var mode: Mode = .find

    @State private var phrase = ""
    @State private var results: [SubtitleCue] = []
    @State private var excluded: Set<String> = []
    @State private var plan: [SentenceComposer.Segment] = []
    @State private var index: SubtitleIndex?
    @State private var building = true
    @State private var searched = false
    @State private var tightenToWord = false
    @State private var evenVolume = false
    @State private var gapEdits: [UUID: String] = [:]
    @State private var excludedSegments: Set<UUID> = []     // compose-mode per-segment opt-out

    private var included: [SubtitleCue] { results.filter { !excluded.contains($0.id) } }
    private var includedSegments: [SentenceComposer.Segment] {
        plan.filter { $0.found && !excludedSegments.contains($0.id) }
    }
    private var planFound: Int { includedSegments.count }                     // clips actually selected
    private func words(_ s: SentenceComposer.Segment) -> Int { s.phrase.split(separator: " ").count }
    private var totalWords: Int { plan.reduce(0) { $0 + words($1) } }
    private var coveredWords: Int { plan.filter(\.found).reduce(0) { $0 + words($1) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text → Supercut").font(.title3).bold()

            if building {
                VStack(spacing: 8) {
                    ProgressView(); Text("Indexing subtitles…").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Picker("", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                if mode == .find { findUI } else { composeUI }
                if let index { Text("\(index.cueCount.formatted()) lines indexed").font(.caption).foregroundStyle(.secondary) }
            }

            if (mode == .find && !results.isEmpty) || (mode == .compose && !plan.isEmpty) {
                Toggle("Tighten each clip to the spoken word (on-device speech)", isOn: $tightenToWord).font(.caption)
            }
            if mode == .compose && !plan.isEmpty {
                Toggle("Even out the volume across clips", isOn: $evenVolume).font(.caption)
            }
            footer
        }
        .padding(20)
        .frame(width: 580, height: 500)
        .task {
            await SubtitleIndexBuilder.ensureIndex(store: store)
            index = SubtitleIndex(path: SubtitleIndex.bestURL)
            building = false
        }
    }

    // MARK: Find clips (v1)

    private var findUI: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("A phrase that’s spoken on screen — e.g. “I love you”", text: $phrase)
                    .textFieldStyle(.roundedBorder).onSubmit(runFind)
                Button("Find", action: runFind).disabled(phrase.isEmpty)
            }
            if searched && results.isEmpty {
                ContentUnavailableView("No spoken lines matched", systemImage: "text.magnifyingglass").frame(minHeight: 150)
            } else if !results.isEmpty {
                HStack {
                    Text("Check the takes you want — \(included.count) of \(results.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("All") { excluded.removeAll() }.controlSize(.small).disabled(excluded.isEmpty)
                    Button("None") { excluded = Set(results.map(\.id)) }
                        .controlSize(.small).disabled(excluded.count == results.count)
                }
                List(results) { cue in
                    HStack(alignment: .top, spacing: 10) {
                        Button {
                            if excluded.contains(cue.id) { excluded.remove(cue.id) } else { excluded.insert(cue.id) }
                        } label: {
                            Image(systemName: excluded.contains(cue.id) ? "circle" : "checkmark.circle.fill")
                                .foregroundStyle(excluded.contains(cue.id) ? .secondary : Color.accentColor)
                                .font(.title3)
                        }.buttonStyle(.borderless)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cue.text).lineLimit(2)
                            Text("\(cue.title) · \(cue.timecode)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }.contentShape(Rectangle())
                }.frame(minHeight: 200)
            }
        }
    }

    // MARK: Compose a sentence (v2)

    private var composeUI: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Type a line — the catalog will speak it back", text: $phrase)
                    .textFieldStyle(.roundedBorder).onSubmit(runCompose)
                Button("Compose", action: runCompose).disabled(phrase.isEmpty)
            }
            if !plan.isEmpty {
                HStack {
                    Text("\(coveredWords) of \(totalWords) words found · \(planFound) clip\(planFound == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { plan = SentenceComposer.shuffle(plan) } label: { Label("Shuffle takes", systemImage: "shuffle") }
                        .controlSize(.small)
                }
                // Each run shows its chosen source film; ‹ › swap among the alternate films that
                // say the same words (the editorial control — pick the take you want).
                List($plan) { $seg in
                    HStack(spacing: 8) {
                        if seg.found {
                            let on = !excludedSegments.contains(seg.id)
                            Button {
                                if on { excludedSegments.insert(seg.id) } else { excludedSegments.remove(seg.id) }
                            } label: {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? Color.accentColor : .secondary)
                            }.buttonStyle(.borderless)
                        } else {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                        }
                        Text("“\(seg.phrase)”").bold()
                        Spacer()
                        if let c = seg.chosen {
                            Text(c.cue.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if seg.candidates.count > 1 {
                                Button { seg.selected = (seg.selected + seg.candidates.count - 1) % seg.candidates.count } label: { Image(systemName: "chevron.left") }
                                    .buttonStyle(.borderless)
                                Text("\(seg.selected + 1)/\(seg.candidates.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                Button { seg.selected = (seg.selected + 1) % seg.candidates.count } label: { Image(systemName: "chevron.right") }
                                    .buttonStyle(.borderless)
                            }
                        } else {
                            // Gap recovery: type a replacement word that IS in the corpus.
                            TextField("try another word…", text: gapBinding(seg.id))
                                .textFieldStyle(.roundedBorder).frame(width: 150)
                                .onSubmit { replaceGap(seg.id) }
                            Button("Use") { replaceGap(seg.id) }.controlSize(.small)
                                .disabled((gapEdits[seg.id] ?? "").isEmpty)
                        }
                    }
                }.frame(minHeight: 200)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
            if mode == .find {
                Button("Add \(included.count) Clips") { assembleFind() }
                    .keyboardShortcut("b", modifiers: .command).disabled(included.isEmpty)
            } else {
                Button("Add \(planFound) Clips") { assembleCompose() }
                    .keyboardShortcut("b", modifiers: .command).disabled(planFound == 0)
            }
        }
    }

    private var statusText: String {
        if mode == .find { return results.isEmpty ? "" : "\(included.count) of \(results.count) selected" }
        return plan.isEmpty ? "" : (coveredWords == totalWords ? "Every word found" : "\(totalWords - coveredWords) word(s) missing")
    }

    private func runFind() {
        guard let index, !phrase.isEmpty else { return }
        results = index.search(phrase); excluded.removeAll(); searched = true
    }
    private func runCompose() {
        guard let index, !phrase.isEmpty else { return }
        plan = SentenceComposer.plan(phrase, index: index)
        gapEdits.removeAll()
        excludedSegments.removeAll()
    }

    private func gapBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { gapEdits[id] ?? "" }, set: { gapEdits[id] = $0 })
    }

    /// Fill a gap with a user-typed replacement word/phrase that IS in the corpus.
    private func replaceGap(_ id: UUID) {
        guard let index, let i = plan.firstIndex(where: { $0.id == id }) else { return }
        let word = (gapEdits[id] ?? "").trimmingCharacters(in: .whitespaces)
        let cands = SentenceComposer.resolve(word, index: index)
        guard !cands.isEmpty else { return }
        plan[i] = SentenceComposer.Segment(phrase: word, candidates: cands)
        gapEdits[id] = nil
    }

    /// Add the selected found cues INSTANTLY (tighten happens in the background).
    private func assembleFind() {
        commit(included.map { EditorModel.SupercutTake(proxy: $0.proxyClip, phrase: phrase, captionText: $0.text) })
    }

    /// Add the composed sentence's selected segments INSTANTLY (tighten/level in the background).
    private func assembleCompose() {
        let takes = includedSegments.compactMap { seg -> EditorModel.SupercutTake? in
            guard let proxy = SentenceComposer.proxyClip(seg), let cue = seg.chosen?.cue else { return nil }
            return EditorModel.SupercutTake(proxy: proxy, phrase: seg.phrase, captionText: cue.text)
        }
        commit(takes)
    }
}
#endif
