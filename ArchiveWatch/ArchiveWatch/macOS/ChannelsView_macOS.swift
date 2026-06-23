#if os(macOS)
import SwiftUI
import SwiftData

// Channels (docs/macOS-DESIGN.md §1 — the parity face includes "channels"; §1's
// "build Mac-native, do not port touch idioms"). Same deterministic date-seeded
// schedule + presets as every platform (shared ChannelScheduler + Models/Channels.swift):
// a proportional EPG with a fixed channel rail, a pinned time ruler, and program
// blocks sized to their real runtimes on a shared time window. The window holds still
// (the proven tvOS/iOS layout — no fragile offset-mirrored 2D frozen-column scroll);
// pointer-native chrome shifts it: Earlier/Later/Now controls (the Mac substitute for
// tvOS focus paging / the iOS swipe-to-page touch idiom §1 says not to port), hover on
// blocks, click to tune in joined-in-progress (#92) with vintage commercial breaks
// woven between programs (#89). User channels (create / right-click-delete) reach
// iOS/Android parity.

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query(sort: \UserChannel.createdAt, order: .reverse) private var userChannels: [UserChannel]

    @State private var guide: [GuideChannel] = []
    @State private var playing: ChannelLineup?
    @State private var showCreate = false
    @State private var nowTick = Date()
    /// The visible window's left edge. nil = "live": the window starts at NOW.
    @State private var windowStart: Date?

    private let railW: CGFloat = 152
    private let rowH: CGFloat = 58
    private let windowMinutes: Double = 180
    private let accent = Color(hex: "#FF5C35") ?? .orange   // marquee orange (Brand is iOS-only)

    private var winStart: Date { windowStart ?? nowTick }
    private var winEnd: Date { winStart.addingTimeInterval(windowMinutes * 60) }
    private var isLive: Bool { windowStart == nil }

    var body: some View {
        Group {
            if guide.isEmpty {
                ProgressView("Building the guide…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    controlBar
                    Divider()
                    epg
                }
            }
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem {
                Button {
                    store.channelCommercialBreaks.toggle()
                } label: {
                    Label("Commercial breaks",
                          systemImage: store.channelCommercialBreaks ? "tv.fill" : "tv.slash")
                }
                .help(store.channelCommercialBreaks
                      ? "Commercial breaks on — click to turn off"
                      : "Commercial breaks off — click to turn on")
            }
            ToolbarItem {
                Button { showCreate = true } label: { Label("Create channel", systemImage: "plus") }
                    .help("Create a custom channel")
            }
        }
        .task(id: store.dbVersion) { rebuild() }
        .onChange(of: userChannels.count) { rebuild() }
        .sheet(item: $playing) { box in
            ChannelPlayer(lineup: box.items, startOffset: box.startOffset)
                .frame(minWidth: 760, minHeight: 480)
        }
        .sheet(isPresented: $showCreate, onDismiss: rebuild) { CreateChannelSheet() }
    }

    // MARK: - Window controls

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button { shift(-90) } label: { Image(systemName: "chevron.left") }
                .help("Earlier")
            Text(windowLabel)
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(minWidth: 210)
            Button { shift(90) } label: { Image(systemName: "chevron.right") }
                .help("Later")
            if !isLive {
                Button("Now") { withAnimation(.easeOut(duration: 0.15)) { windowStart = nil } }
                    .buttonStyle(.borderedProminent).tint(accent).controlSize(.small)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var windowLabel: String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(winStart.formatted(f)) – \(winEnd.formatted(f))"
    }

    /// Shift the window, clamped to the broadcast day (anchor → +20h). Landing within
    /// 5 minutes of NOW snaps back to live mode (the red now-line returns).
    private func shift(_ minutes: Double) {
        let proposed = (windowStart ?? nowTick).addingTimeInterval(minutes * 60)
        let floor = ChannelScheduler.dayAnchor(for: nowTick)
        let ceiling = nowTick.addingTimeInterval(20 * 3600)
        let clamped = min(max(proposed, floor), ceiling)
        withAnimation(.easeOut(duration: 0.15)) {
            windowStart = abs(clamped.timeIntervalSince(nowTick)) < 300 ? nil : clamped
        }
    }

    // MARK: - The proportional guide (fixed rail + pinned ruler + runtime-sized blocks)

    private var epg: some View {
        GeometryReader { geo in
            let timelineW = max(280, geo.size.width - railW - 24)
            let ppm = timelineW / windowMinutes
            ScrollView(.vertical) {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        rows(ppm: ppm, timelineW: timelineW)
                    } header: {
                        ruler(timelineW: timelineW)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
        }
    }

    private func ruler(timelineW: CGFloat) -> some View {
        let ticks = Int(windowMinutes / 30)
        let tickW = timelineW / CGFloat(ticks)
        return HStack(spacing: 0) {
            Color.clear.frame(width: railW)
            ForEach(0..<ticks, id: \.self) { i in
                let t = winStart.addingTimeInterval(Double(i) * 1800)
                Text(isLive && i == 0 ? "NOW" : t.formatted(date: .omitted, time: .shortened))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isLive && i == 0 ? accent : .secondary)
                    .frame(width: tickW, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
                    }
            }
        }
        .frame(height: 28)
        .background(Color(nsColor: .underPageBackgroundColor))   // pinned header occludes rows beneath
    }

    @ViewBuilder
    private func rows(ppm: CGFloat, timelineW: CGFloat) -> some View {
        ForEach(guide) { ch in
            HStack(spacing: 0) {
                railCell(ch)
                timeline(ch, ppm: ppm, timelineW: timelineW)
            }
            .frame(height: rowH)
            Divider()
        }
        // One red now-line across every row, only when NOW is in the window.
        .overlay(alignment: .topLeading) {
            if nowTick >= winStart && nowTick < winEnd {
                Rectangle()
                    .fill(accent.opacity(0.85))
                    .frame(width: 2)
                    .offset(x: railW + CGFloat(nowTick.timeIntervalSince(winStart) / 60) * ppm)
                    .allowsHitTesting(false)
            }
        }
    }

    private func railCell(_ ch: GuideChannel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ch.icon)
                .font(.subheadline).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(ch.accent.gradient, in: .rect(cornerRadius: 6))
            Text(ch.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: railW, height: rowH, alignment: .leading)
        .contextMenu {
            if ch.id.hasPrefix("user-") {
                Button("Delete Channel", role: .destructive) { deleteUserChannel(ch.id) }
            }
        }
    }

    private func timeline(_ ch: GuideChannel, ppm: CGFloat, timelineW: CGFloat) -> some View {
        let visible = ch.slots.filter { $0.end > winStart && $0.start < winEnd }
        return HStack(spacing: 2) {
            // Lead-in gap when the first visible program starts inside the window.
            if let first = visible.first, first.start > winStart {
                Color.clear.frame(width: CGFloat(first.start.timeIntervalSince(winStart) / 60) * ppm)
            }
            ForEach(visible) { slot in
                let visStart = max(slot.start, winStart)
                let visEnd = min(slot.end, winEnd)
                let w = max(26, CGFloat(visEnd.timeIntervalSince(visStart) / 60) * ppm - 2)
                programBlock(slot, channel: ch, width: w, airing: slot.contains(nowTick))
            }
            Spacer(minLength: 0)
        }
        .frame(width: timelineW, height: rowH, alignment: .leading)
        .clipped()
    }

    private func programBlock(_ slot: ScheduledProgram, channel: GuideChannel,
                              width: CGFloat, airing: Bool) -> some View {
        Button { tune(channel, from: slot) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.item.title)
                    .font(.caption.weight(airing ? .bold : .medium))
                    .lineLimit(2)
                    .foregroundStyle(airing ? .white : .primary)
                Spacer(minLength: 0)
                Text(slot.start, style: .time)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(airing ? .white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 5)
            .frame(width: width, height: rowH - 8, alignment: .topLeading)
            .background(
                airing ? AnyShapeStyle(channel.accent.gradient)
                       : AnyShapeStyle(Color(nsColor: .controlBackgroundColor)),
                in: .rect(cornerRadius: 7)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(channel.accent.opacity(airing ? 0 : 0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(slot.item.title) · \(slot.start.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: - build the guide (mirrors the iOS/tvOS rebuild)

    private func rebuild() {
        nowTick = Date()
        let now = nowTick
        var out: [GuideChannel] = []
        var number = 2
        for uc in userChannels {
            let pool = playable(store.dbBrowse(contentType: uc.contentType, decade: uc.decade,
                                               genre: uc.genre, sort: .popular, limit: 150))
            let slots = ChannelScheduler.schedule(channelID: "user-\(uc.id)", programs: pool, now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: "user-\(uc.id)", number: number, title: uc.name,
                                    accent: Color(hex: "#0047FF") ?? .blue,
                                    icon: "dot.radiowaves.left.and.right", slots: slots))
            number += 1
        }
        for ch in Channel.all {
            var pool = playable(store.dbBrowse(contentType: ch.contentType, genre: ch.genre,
                                               sort: .popular, limit: 90))
            if ch.contentType == "animation" { pool = colorEmphasized(pool, bwFraction: 0.10) }
            let slots = ChannelScheduler.schedule(channelID: ch.id, programs: pool, now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: ch.id, number: number, title: ch.title,
                                    accent: ch.accent, icon: ch.icon, slots: slots))
            number += 1
        }
        guide = out
    }

    private func playable(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter { $0.videoURLParsed != nil }
    }

    /// Color animation leads; B&W/silent capped to a minority (Decision 025).
    private func colorEmphasized(_ items: [Catalog.Item], bwFraction: Double) -> [Catalog.Item] {
        func bwOrSilent(_ it: Catalog.Item) -> Bool {
            if it.isColor == true { return false }
            if it.isBlackAndWhite { return true }
            if it.isSilentFilm == true { return true }
            if let y = it.year, y < 1930 { return true }
            return false
        }
        let color = items.filter { !bwOrSilent($0) }.shuffled()
        let bw = items.filter { bwOrSilent($0) }.shuffled()
        let cap = max(3, Int(Double(color.count) * bwFraction))
        return color + Array(bw.prefix(cap))
    }

    // MARK: - tune in

    private func tune(_ channel: GuideChannel, from slot: ScheduledProgram) {
        let programs = channel.slots.drop { $0.id != slot.id }.map(\.item)
        let now = Date()
        let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
        playing = ChannelLineup(items: weaveCommercials(into: Array(programs)), startOffset: offset)
    }

    /// #89: drop a vintage PD commercial between programs (gated by the setting).
    private func weaveCommercials(into programs: [Catalog.Item]) -> [Catalog.Item] {
        guard store.channelCommercialBreaks, programs.count > 1 else { return programs }
        let ads = store.randomCommercials(limit: 60).filter { $0.videoURLParsed != nil }
        guard !ads.isEmpty else { return programs }
        var out: [Catalog.Item] = []
        out.reserveCapacity(programs.count * 2)
        for (i, program) in programs.enumerated() {
            out.append(program)
            if i < programs.count - 1 { out.append(ads[i % ads.count]) }
        }
        return out
    }

    private func deleteUserChannel(_ guideID: String) {
        let id = guideID.replacingOccurrences(of: "user-", with: "")
        guard let uc = userChannels.first(where: { $0.id == id }) else { return }
        ctx.delete(uc)
        // Tombstone so the deletion propagates on CloudKit pull instead of resurrecting
        // (documented keying "ch:<id>"; the foreground/sign-in sync triggers push it).
        ctx.insert(Tombstone(key: "ch:\(id)"))
        try? ctx.save()
        rebuild()
    }
}

// Channel lineup box (live TV: no resume, no Watched pollution). The iOS/tvOS twins
// are platform-guarded, so this macOS definition never collides.
struct ChannelLineup: Identifiable {
    let id = UUID()
    let items: [Catalog.Item]
    var startOffset: TimeInterval = 0
}

// MARK: - Create a channel (native macOS Form sheet)

private struct CreateChannelSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var genre: String?
    @State private var type: String?
    @State private var decade: Int?

    private let genres = ["Drama", "Comedy", "Crime", "Thriller", "Romance",
                          "Action", "Horror", "Mystery", "Western", "Documentary",
                          "Adventure", "War", "Fantasy", "Family", "Music", "Science Fiction"]
    private let types = ["feature-film", "animation", "silent-film",
                         "short-film", "newsreel", "documentary"]
    private let decades = [1900, 1910, 1920, 1930, 1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010]

    private func typeLabel(_ t: String) -> String {
        t.replacingOccurrences(of: "-", with: " ").capitalized
    }
    private var autoName: String {
        let parts = [decade.map { "\(String($0))s" }, genre, type.map(typeLabel)].compactMap { $0 }
        return parts.isEmpty ? "My Channel" : parts.joined(separator: " ")
    }
    private var canSave: Bool { genre != nil || type != nil || decade != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Filters") {
                    Picker("Genre", selection: $genre) {
                        Text("Any").tag(String?.none)
                        ForEach(genres, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    Picker("Type", selection: $type) {
                        Text("Any").tag(String?.none)
                        ForEach(types, id: \.self) { Text(typeLabel($0)).tag(String?.some($0)) }
                    }
                    Picker("Era", selection: $decade) {
                        Text("Any").tag(Int?.none)
                        ForEach(decades, id: \.self) { Text(verbatim: "\($0)s").tag(Int?.some($0)) }
                    }
                }
                Section("Name") {
                    TextField(autoName, text: $name)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Text("Pick any mix — your channel plays it straight through, all day.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(width: 440, height: 340)
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        ctx.insert(UserChannel(name: n.isEmpty ? autoName : n,
                               genre: genre, contentType: type, decade: decade))
        try? ctx.save()
        dismiss()
    }
}
#endif
