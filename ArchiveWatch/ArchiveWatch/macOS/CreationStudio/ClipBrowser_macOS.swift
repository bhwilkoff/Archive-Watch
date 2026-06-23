#if os(macOS)
import SwiftUI
import AVKit
import AVFoundation
import UniformTypeIdentifiers
import CoreTransferable

// Unit 4 — the source browser + mark-in/out (docs/macOS-DESIGN.md §7e "browser = Storyblocks
// UX minus licensing"). Browse the catalog for CLIPPABLE titles (Rule 5c — rights gate),
// mark an in/out window on a chosen title, and add it to the timeline (also saved to the
// proxy-clip Library for reuse). Phase 3's stock-shot index slots into this same browser.

// A ProxyClip is draggable (references only — Rule 4a) from the Library onto the timeline.
extension ProxyClip: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}

// MARK: - Browser sheet: pick a clippable title

struct ClipBrowserSheet: View {
    let onAdd: (ProxyClip) -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Catalog.Item] = []
    @State private var marking: Catalog.Item?

    private let cols = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if results.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Browse for a clip" : "No clippable results",
                                           systemImage: "magnifyingglass",
                                           description: Text("Search the public-domain catalog, then mark an in/out point."))
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: cols, spacing: 16) {
                        ForEach(results) { item in
                            Button { marking = item } label: { BrowserCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Add a Clip")
            .searchable(text: $query, prompt: "Films, shows, people…")
            .onChange(of: query) { reload() }
            .task { reload() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .frame(minWidth: 640, minHeight: 460)
        }
        .sheet(item: $marking) { item in
            MarkClipView(item: item) { proxy in
                onAdd(proxy)
                marking = nil
                dismiss()
            }
        }
    }

    private func reload() {
        let raw = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? store.browse(sort: .popular, limit: 60)
            : store.search(query)
        results = raw.filter { $0.isClippable }
    }
}

private struct BrowserCard: View {
    let item: Catalog.Item
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .aspectRatio(2.0/3.0, contentMode: .fit)
                .overlay {
                    if let u = item.posterURLParsed {
                        AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(item.title).font(.caption).lineLimit(1)
        }
    }
}

// MARK: - Mark in/out on a chosen title

struct MarkClipView: View {
    let item: Catalog.Item
    let onAdd: (ProxyClip) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var player = AVPlayer()
    @State private var loader: ResilientStreamLoader?
    @State private var inSeconds = 0.0
    @State private var outSeconds = 8.0
    @State private var label = ""

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                VideoPlayerNS(player: player)
            }
            .frame(minWidth: 640, minHeight: 380)

            Form {
                HStack {
                    Button("Set In at Playhead") { inSeconds = currentSeconds() }
                    Text(timecode(inSeconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Text(timecode(outSeconds)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    Button("Set Out at Playhead") { outSeconds = max(currentSeconds(), inSeconds + 0.2) }
                }
                LabeledContent("Length", value: String(format: "%.1f s", max(0, outSeconds - inSeconds)))
                TextField("Clip name", text: $label, prompt: Text(item.title))
            }
            .formStyle(.grouped).frame(height: 150)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add to Timeline") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(outSeconds <= inSeconds)
            }
            .padding(12)
        }
        .onAppear(perform: open)
        .onDisappear { player.pause() }
        .frame(width: 700, height: 640)
    }

    private func open() {
        guard let url = item.videoURLParsed else { return }
        let (asset, l) = ResilientStreamLoader.makeAsset(for: url)
        loader = l
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
    }

    private func currentSeconds() -> Double {
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, t) : 0
    }

    private func add() {
        guard let url = item.videoURLParsed else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        let proxy = ProxyClip(
            catalogItemID: item.archiveID, sourceURL: url,
            sourceRange: TimeRange(startSeconds: inSeconds, durationSeconds: outSeconds - inSeconds),
            label: name.isEmpty ? item.title : name,
            posterFrameSeconds: inSeconds, title: item.title)
        onAdd(proxy)
        dismiss()
    }

    private func timecode(_ s: Double) -> String {
        String(format: "%d:%02d.%d", Int(s) / 60, Int(s) % 60, Int((s.truncatingRemainder(dividingBy: 1)) * 10))
    }
}
#endif
