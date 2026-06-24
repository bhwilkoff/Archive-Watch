#if os(macOS)
import SwiftUI
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
    @Environment(\.dismiss) private var dismiss

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
    @State private var assembling = false
    @State private var assembleProgress = 0.0

    private var included: [SubtitleCue] { results.filter { !excluded.contains($0.id) } }
    private var planFound: Int { plan.filter(\.found).count }                 // clips (found runs)
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
            if assembling { ProgressView(value: assembleProgress) { Text("Assembling…").font(.caption) } }
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
                List(results) { cue in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: excluded.contains(cue.id) ? "circle" : "checkmark.circle.fill")
                            .foregroundStyle(excluded.contains(cue.id) ? .secondary : Color.accentColor)
                            .onTapGesture { if excluded.contains(cue.id) { excluded.remove(cue.id) } else { excluded.insert(cue.id) } }
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
                        Image(systemName: seg.found ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(seg.found ? Color.accentColor : .orange)
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
                        } else { Text("no clip — gap").font(.caption).foregroundStyle(.orange) }
                    }
                }.frame(minHeight: 200)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(statusText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }.disabled(assembling)
            if mode == .find {
                Button("Add \(included.count) Clips") { Task { await assembleFind() } }
                    .keyboardShortcut("b", modifiers: .command).disabled(included.isEmpty || assembling)
            } else {
                Button("Add \(planFound) Clips") { Task { await assembleCompose() } }
                    .keyboardShortcut("b", modifiers: .command).disabled(planFound == 0 || assembling)
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
    }

    /// Add the selected found cues (v1), optionally speech-tightened to the phrase.
    private func assembleFind() async {
        assembling = true
        for (i, cue) in included.enumerated() {
            assembleProgress = Double(i) / Double(max(1, included.count))
            model.addClip(from: await resolved(cue.proxyClip, phrase: phrase, cue: cue))
        }
        assembling = false; dismiss()
    }

    /// Assemble the sentence in order (v2): each found segment's word window, optionally tightened.
    private func assembleCompose() async {
        assembling = true
        let segs = plan.filter(\.found)
        for (i, seg) in segs.enumerated() {
            assembleProgress = Double(i) / Double(max(1, segs.count))
            guard let proxy = SentenceComposer.proxyClip(seg), let cue = seg.chosen?.cue else { continue }
            // For tightening, run speech on the FULL cue window (context) and use the phrase's range;
            // otherwise the (word-index or proportional) word window.
            let base = tightenToWord ? cue.proxyClip : proxy
            model.addClip(from: tightenToWord ? await resolved(base, phrase: seg.phrase, cue: cue) : proxy)
            // A tiny fade on each tight word-cut so the assembled sentence doesn't CLICK at the
            // joins (each word starts/ends mid-waveform). The hard visual jump between films stays.
            if let id = model.selectedClipID { model.setClipFade(id, fadeIn: 0.03, fadeOut: 0.03) }
        }
        assembling = false; dismiss()
    }

    /// Optionally narrow `proxy` to just `phrase` via on-device speech (validated vs the caption).
    private func resolved(_ proxy: ProxyClip, phrase: String, cue: SubtitleCue) async -> ProxyClip {
        guard tightenToWord,
              let url = try? await ClipCacheService.cachedURL(for: TimelineClip.from(proxy, at: .zero)),
              let r = await WordTiming.tighten(mediaURL: url, phrase: phrase, caption: cue.text) else { return proxy }
        let newIn = proxy.sourceRange.start.seconds + r.start.seconds
        return ProxyClip(catalogItemID: proxy.catalogItemID, sourceURL: proxy.sourceURL,
                         sourceRange: TimeRange(startSeconds: max(0, newIn), durationSeconds: r.duration.seconds),
                         label: phrase, posterFrameSeconds: newIn, title: cue.title)
    }
}
#endif
