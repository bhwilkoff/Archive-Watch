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
/// Live progress for an off-main Supercut Search compose pass (so the UI never beachballs).
@MainActor @Observable final class ComposeStatus {
    var running = false
    var done = 0
    var total = 0
}

struct SupercutSheet: View {
    let model: EditorModel
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    /// Add a batch of assembled takes to the timeline INSTANTLY (and the SwiftData Library, #12),
    /// then tighten/level them in the background (EditorModel.addSupercutClips). No per-clip
    /// blocking — 80 clips appear at once instead of crawling one-by-one.
    private func commit(_ takes: [EditorModel.SupercutTake]) {
        for t in takes {
            var p = t.proxy
            p.caption = t.captionText        // carry the dialogue so the sidebar shows it (#5)
            ctx.insert(LibraryClip(from: p))
        }
        try? ctx.save()
        model.addSupercutClips(takes, tighten: tightenToWord, evenVolume: evenVolume, addSubtitles: addSubtitles)
        dismiss()
    }

    enum Mode: String, CaseIterable, Identifiable { case find = "Phrase Finder", compose = "Supercut Search"; var id: String { rawValue } }
    @State private var mode: Mode = .find

    @State private var phrase = ""
    @State private var results: [SubtitleCue] = []
    @State private var excluded: Set<String> = []
    @State private var plan: [SentenceComposer.Segment] = []
    @State private var index: SubtitleIndex?
    @State private var indexedLines: Int?        // computed ONCE when the index loads (see .task) —
                                                 // NOT per render: cueCount runs SELECT count(*) over
                                                 // ~1.7M rows, and reading it in body on every keystroke
                                                 // was the typing lag.
    @State private var building = true
    @State private var searched = false
    @State private var searching = false                 // Phrase Finder query in flight (off-main)
    @State private var compose = ComposeStatus()          // Supercut Search progress (off-main)
    @State private var tightenToWord = false
    @State private var fullSentence = false        // Phrase Finder: clip the whole spoken statement
    @State private var evenVolume = false
    @State private var addSubtitles = false
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
        // Native macOS task-sheet shape: a top-anchored header, a content area that FILLS the
        // sheet (so it never looks squished into the vertical center), and a pinned footer with
        // the default action bottom-right. Resizable within sensible bounds.
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            optionsBar
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 860,
               minHeight: 460, idealHeight: 600, maxHeight: 900)
        .task {
            await SubtitleIndexBuilder.ensureIndex(store: store)
            let idx = SubtitleIndex(path: SubtitleIndex.bestURL)
            index = idx
            indexedLines = await Task.detached { idx?.cueCount }.value   // count(*) off-main (the typing-lag fix)
            building = false
        }
    }

    // MARK: Header (title + mode + search field + index status)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(.tint)
                Text("Text → Supercut").font(.headline)
                Spacer()
            }
            Picker("Mode", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().disabled(building)

            // Search field — a native macOS search-field shape (capsule + magnifier), full-width,
            // with the action button trailing. Submitting runs the search; typing does NOT (so it
            // stays responsive).
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(mode == .find ? "A phrase that’s spoken on screen — e.g. “I love you”"
                                            : "Type a line — the catalog will speak it back",
                              text: $phrase)
                        .textFieldStyle(.plain)
                        .onSubmit { mode == .find ? runFind() : runCompose() }
                    if !phrase.isEmpty {
                        Button { phrase = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator))

                Button(mode == .find ? "Find" : "Compose") { mode == .find ? runFind() : runCompose() }
                    .disabled(phrase.isEmpty || building || searching || compose.running)
            }

            HStack(spacing: 6) {
                if building {
                    ProgressView().controlSize(.small)
                    Text("Building the subtitle index…")
                } else if let n = indexedLines {
                    Text("\(n.formatted()) lines indexed")
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    // MARK: Content (fills) — results, or guidance

    @ViewBuilder private var content: some View {
        if building {
            VStack(spacing: 10) {
                ProgressView()
                Text("Building the subtitle index…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if mode == .find {
            findResults
        } else {
            composeResults
        }
    }

    @ViewBuilder private var findResults: some View {
        if searching {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching the public-domain catalog…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView {
                Label(searched ? "No spoken lines matched" : "Find a spoken phrase",
                      systemImage: searched ? "text.magnifyingglass" : "quote.bubble")
            } description: {
                Text(searched ? "Try a shorter or more common phrase."
                              : "Type a phrase people say on screen, then press Find. Every matching moment across the public-domain catalog becomes an editable clip.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Check the takes you want — \(included.count) of \(results.count) selected")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("All") { excluded.removeAll() }.disabled(excluded.isEmpty)
                    Button("None") { excluded = Set(results.map(\.id)) }.disabled(excluded.count == results.count)
                }
                .controlSize(.small).padding(.horizontal, 20).padding(.vertical, 8)
                Divider()
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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if excluded.contains(cue.id) { excluded.remove(cue.id) } else { excluded.insert(cue.id) }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    @ViewBuilder private var composeResults: some View {
        if compose.running {
            // Live progress while the catalog is searched word-by-word (off-main, so the spinner
            // actually animates — proof the UI isn't frozen — and the count advances as runs resolve).
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text("Finding clips for your line — \(compose.done) of \(compose.total) words")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Searching every spoken line in the public-domain catalog.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if plan.isEmpty {
            ContentUnavailableView {
                Label("Supercut Search", systemImage: "quote.bubble")
            } description: {
                Text("Type a line and the catalog will speak it back, word by word, using the fewest clips. Missing words become editable gaps you can fill.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("\(coveredWords) of \(totalWords) words found · \(planFound) clip\(planFound == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { plan = SentenceComposer.shuffle(plan) } label: { Label("Shuffle takes", systemImage: "shuffle") }
                }
                .controlSize(.small).padding(.horizontal, 20).padding(.vertical, 8)
                Divider()
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
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: Options (tighten / level) — only when there are takes to refine

    @ViewBuilder private var optionsBar: some View {
        if (mode == .find && !results.isEmpty) || (mode == .compose && !plan.isEmpty) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Tighten each clip to the spoken word (on-device speech)", isOn: $tightenToWord)
                    .disabled(fullSentence)
                // The OPPOSITE of tighten (Phrase Finder only): clip the whole spoken statement —
                // start at the beginning of the sentence, the phrase in the middle, end at the
                // sentence's end (natural pauses). Mutually exclusive with tighten.
                if mode == .find {
                    Toggle("Clip only full sentences", isOn: $fullSentence)
                        .disabled(tightenToWord)
                }
                // Both options apply to both tabs (owner ask) — leveling matters as much
                // when assembling found phrases as when composing a sentence.
                Toggle("Even out the volume across clips", isOn: $evenVolume)
                // One editable subtitle per clip, showing the spoken words across the whole supercut
                // so it reads as one sentence (owner ask). Placed after verify/tighten so the text
                // lines up with each clip's final length.
                Toggle("Add subtitles to supercut clips", isOn: $addSubtitles)
            }
            .toggleStyle(.checkbox).font(.callout)
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // MARK: Footer (pinned) — Cancel + default action

    private var footer: some View {
        HStack {
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            if mode == .find {
                Button("Add \(included.count) Clips") { assembleFind() }
                    .keyboardShortcut(.defaultAction).disabled(included.isEmpty)
            } else {
                Button("Add \(planFound) Clips") { assembleCompose() }
                    .keyboardShortcut(.defaultAction).disabled(planFound == 0)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var statusText: String {
        if mode == .find { return results.isEmpty ? "" : "\(included.count) of \(results.count) selected" }
        return plan.isEmpty ? "" : (coveredWords == totalWords ? "Every word found" : "\(totalWords - coveredWords) word(s) missing")
    }

    private func runFind() {
        guard let index, !phrase.isEmpty else { return }
        let p = phrase
        searching = true; searched = true; results = []; excluded.removeAll()
        Task {
            // Run the LIKE scan OFF the main thread so the UI stays responsive.
            let found = await Task.detached {
                // De-dupe to ONE result per film so the list reflects how many distinct examples we
                // actually have (results are shortest-cue first → keep the most precise per film).
                var seen = Set<String>(), deduped: [SubtitleCue] = []
                for cue in index.search(p, limit: 400) where seen.insert(cue.archiveID).inserted {
                    deduped.append(cue)
                }
                return Array(deduped.prefix(200))
            }.value
            results = found
            searching = false
        }
    }

    private func runCompose() {
        guard let index, !phrase.isEmpty else { return }
        let p = phrase
        let status = compose
        status.running = true; status.done = 0; status.total = SentenceComposer.tokens(p).count
        plan = []; gapEdits.removeAll(); excludedSegments.removeAll()
        Task {
            // The longest-match plan fires ~O(words²) LIKE scans — run it OFF the main thread and
            // stream per-word progress so the window never beachballs and shows what's been sourced.
            let result = await Task.detached {
                SentenceComposer.plan(p, index: index) { done, total in
                    Task { @MainActor in status.done = max(status.done, done); status.total = total }
                }
            }.value
            plan = result
            status.running = false
        }
    }

    private func gapBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { gapEdits[id] ?? "" }, set: { gapEdits[id] = $0 })
    }

    /// Fill a gap with a user-typed replacement word/phrase that IS in the corpus.
    private func replaceGap(_ id: UUID) {
        guard let index, plan.contains(where: { $0.id == id }) else { return }
        let word = (gapEdits[id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return }
        Task {
            let cands = await Task.detached { SentenceComposer.resolve(word, index: index) }.value
            guard !cands.isEmpty, let i = plan.firstIndex(where: { $0.id == id }) else { return }
            plan[i] = SentenceComposer.Segment(phrase: word, candidates: cands)
            gapEdits[id] = nil
        }
    }

    /// Add the selected found cues INSTANTLY (tighten happens in the background). When "Clip only full
    /// sentences" is on, expand each cue to its whole spoken statement (an off-main index query) so the
    /// clip starts at the sentence's beginning, holds the phrase in the middle, and ends at its end.
    private func assembleFind() {
        let cues = included, ph = phrase
        guard fullSentence, let index else {
            commit(cues.map { EditorModel.SupercutTake(proxy: $0.proxyClip, phrase: ph, captionText: $0.text) })
            return
        }
        Task {
            let takes = await Task.detached { () -> [EditorModel.SupercutTake] in
                cues.map { cue in
                    let proxy: ProxyClip
                    if let r = index.sentenceRange(archiveID: cue.archiveID, nearSeconds: cue.startSeconds) {
                        proxy = ProxyClip(catalogItemID: cue.archiveID, sourceURL: cue.sourceURL, sourceRange: r,
                                          label: "\(cue.title): \(cue.text.prefix(28))",
                                          posterFrameSeconds: cue.startSeconds, title: cue.title)
                    } else {
                        proxy = cue.proxyClip       // no neighbors found → the cue's own padded range
                    }
                    return EditorModel.SupercutTake(proxy: proxy, phrase: ph, captionText: cue.text)
                }
            }.value
            commit(takes)
        }
    }

    /// Add the composed sentence's selected segments INSTANTLY (tighten/level in the background).
    private func assembleCompose() {
        let takes = includedSegments.compactMap { seg -> EditorModel.SupercutTake? in
            guard let proxy = SentenceComposer.proxyClip(seg), let cue = seg.chosen?.cue else { return nil }
            // Carry the segment's other candidates as ranked alternates: if the chosen clip doesn't
            // actually SPEAK the phrase, the verify pass swaps in the first alternate that does.
            return EditorModel.SupercutTake(proxy: proxy, phrase: seg.phrase, captionText: cue.text,
                                            alternates: SentenceComposer.alternateProxies(seg))
        }
        commit(takes)
    }
}
#endif
