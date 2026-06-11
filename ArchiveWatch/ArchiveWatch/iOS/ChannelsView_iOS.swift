#if os(iOS)
import SwiftUI
import SwiftData

// Channels (PARITY §5) — the touch guide for the tvOS EPG, reworked 2026-06-12
// as a TRUE TV-listing grid (owner: "a series of tiles rather than the true
// grid that is essential for it to feel like you are looking at a tv listing").
// Same deterministic date-seeded schedule (shared ChannelScheduler) and presets
// (Models/Channels.swift). Anatomy mirrors tvOS's proportional EPG: a pinned
// time ruler, a fixed channel rail, and program blocks sized to their real
// runtimes on a shared time window — vertical scrolling only (the reliable
// axis), with the window shifted by chevrons or a horizontal swipe (the touch
// substitute for tvOS's fixed now→+3h window). Tap a block to tune in
// joined-in-progress (#92) with vintage commercial breaks woven between
// programs (#89); tap a channel's rail for its full-day schedule.

struct ChannelsRoute: Hashable {}

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Environment(\.horizontalSizeClass) private var hSize
    @Query(sort: \UserChannel.createdAt, order: .reverse) private var userChannels: [UserChannel]
    @State private var guide: [GuideChannel] = []
    @State private var builtAt = Date()
    @State private var playing: ChannelLineup?
    @State private var showCreate = false
    /// The guide window's left edge. nil = "live": the window starts at NOW.
    @State private var windowStart: Date?

    private var windowMinutes: Double { hSize == .regular ? 180 : 120 }

    var body: some View {
        Group {
            if guide.isEmpty {
                ProgressView("Building the guide…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EPGGuide(channels: guide,
                         windowStart: windowStart ?? Date(),
                         windowMinutes: windowMinutes,
                         isLive: windowStart == nil,
                         onShift: shift(by:),
                         onJumpToNow: { windowStart = nil },
                         onTune: tune(_:from:),
                         onRail: { router.push(ChannelScheduleRoute(channelID: $0.id)) })
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.channelCommercialBreaks.toggle()
                } label: {
                    Image(systemName: store.channelCommercialBreaks ? "tv.fill" : "tv.slash")
                        .accessibilityLabel(store.channelCommercialBreaks
                            ? "Commercial breaks on" : "Commercial breaks off")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").accessibilityLabel("Create channel")
                }
            }
        }
        .task(id: store.dbVersion) { rebuild() }
        .onChange(of: userChannels.count) { rebuild() }
        .fullScreenCover(item: $playing) { box in
            if let player = PlayerView(lineup: box.items, startOffset: box.startOffset) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: rebuild) { CreateChannelSheet() }
    }

    /// Shift the visible window, clamped to the broadcast day (anchor → +20h).
    /// Landing within 5 minutes of NOW snaps back to live mode.
    private func shift(by minutes: Double) {
        let now = Date()
        let proposed = (windowStart ?? now).addingTimeInterval(minutes * 60)
        let floor = ChannelScheduler.dayAnchor(for: now)
        let ceiling = now.addingTimeInterval(20 * 3600)
        let clamped = min(max(proposed, floor), ceiling)
        windowStart = abs(clamped.timeIntervalSince(now)) < 300 ? nil : clamped
    }

    // MARK: schedule build (mirrors tvOS ChannelsView.rebuild)

    private func rebuild() {
        let now = Date()
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
            let raw = store.dbBrowse(contentType: ch.contentType, genre: ch.genre,
                                     sort: .popular, limit: 90)
            var pool = playable(raw)
            if ch.contentType == "animation" {
                pool = colorEmphasized(pool, bwFraction: 0.10)
            }
            let slots = ChannelScheduler.schedule(channelID: ch.id, programs: pool, now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: ch.id, number: number, title: ch.title,
                                    accent: ch.accent, icon: ch.icon, slots: slots))
            number += 1
        }
        builtAt = now
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

    // MARK: tune in

    private func tune(_ channel: GuideChannel, from slot: ScheduledProgram) {
        let programs = channel.slots.drop { $0.id != slot.id }.map(\.item)
        let now = Date()
        let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
        playing = ChannelLineup(items: weaveCommercials(into: Array(programs)), startOffset: offset)
    }

    /// #89: drop a vintage PD commercial between programs (gated by setting).
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

    private func deleteUserChannels(at offsets: IndexSet) {
        let userGuide = guide.filter { $0.id.hasPrefix("user-") }
        for i in offsets {
            let gid = userGuide[i].id.replacingOccurrences(of: "user-", with: "")
            if let uc = userChannels.first(where: { $0.id == gid }) {
                ctx.delete(uc)
                SyncNudge.recordDeletion("ch:\(uc.id)", in: ctx)
            }
        }
        rebuild()
    }
}

struct ChannelLineup: Identifiable {
    let id = UUID()
    let items: [Catalog.Item]
    var startOffset: TimeInterval = 0
}

// MARK: - The touch EPG grid (proportional TV listing)
//
// tvOS's guide anatomy in the touch idiom: a pinned half-hour ruler
// (LazyVStack section header), a fixed channel rail on the left, and program
// blocks whose width is proportional to runtime on the shared window. Only the
// vertical axis scrolls; the WINDOW moves instead of a second scroll axis —
// chevrons or a horizontal swipe shift it ±90 min (clamped to the broadcast
// day), and "Now" snaps back to live with the red now-line.

private struct EPGGuide: View {
    let channels: [GuideChannel]
    let windowStart: Date
    let windowMinutes: Double
    let isLive: Bool
    let onShift: (Double) -> Void
    let onJumpToNow: () -> Void
    let onTune: (GuideChannel, ScheduledProgram) -> Void
    let onRail: (GuideChannel) -> Void

    private let railW: CGFloat = 76
    private let rowH: CGFloat = 64
    private var windowEnd: Date { windowStart.addingTimeInterval(windowMinutes * 60) }

    var body: some View {
        GeometryReader { geo in
            let timelineW = max(200, geo.size.width - railW - 16)
            let ppm = timelineW / windowMinutes
            VStack(spacing: 0) {
                controls
                ScrollView(.vertical) {
                    LazyVStack(spacing: 4, pinnedViews: [.sectionHeaders]) {
                        Section {
                            rows(ppm: ppm, timelineW: timelineW)
                        } header: {
                            ruler(timelineW: timelineW)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
                }
            }
            // The touch substitute for a second scroll axis: a deliberate
            // horizontal swipe pages the window. High threshold + dominant-axis
            // check so vertical guide scrolling never triggers it.
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { v in
                        guard abs(v.translation.width) > 70,
                              abs(v.translation.width) > abs(v.translation.height) * 1.5
                        else { return }
                        onShift(v.translation.width < 0 ? 90 : -90)
                    }
            )
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { onShift(-90) } label: {
                Image(systemName: "chevron.left").frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("Earlier")
            Text(windowLabel)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
            Button { onShift(90) } label: {
                Image(systemName: "chevron.right").frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("Later")
            if !isLive {
                Button("Now") { onJumpToNow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Brand.primary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var windowLabel: String {
        let f = Date.FormatStyle(date: .omitted, time: .shortened)
        return "\(windowStart.formatted(f)) – \(windowEnd.formatted(f))"
    }

    private func ruler(timelineW: CGFloat) -> some View {
        let ticks = Int(windowMinutes / 30)
        let tickW = timelineW / CGFloat(ticks)
        return HStack(spacing: 0) {
            Color.clear.frame(width: railW + 4)
            ForEach(0..<ticks, id: \.self) { i in
                let t = windowStart.addingTimeInterval(Double(i) * 1800)
                Text(isLive && i == 0 ? "NOW" : t.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isLive && i == 0 ? Brand.primary : .secondary)
                    .frame(width: tickW, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
                    }
            }
        }
        .frame(height: 24)
        .background(.background)   // pinned header must occlude rows beneath
    }

    @ViewBuilder
    private func rows(ppm: CGFloat, timelineW: CGFloat) -> some View {
        let now = Date()
        ForEach(channels) { ch in
            HStack(spacing: 4) {
                railCell(ch)
                timeline(ch, ppm: ppm, timelineW: timelineW, now: now)
            }
            .frame(height: rowH)
        }
        // One red now-line across every row, only when NOW is in the window.
        .overlay(alignment: .topLeading) {
            if now >= windowStart && now < windowEnd {
                Rectangle()
                    .fill(Brand.primary.opacity(0.8))
                    .frame(width: 2)
                    .offset(x: railW + 4 + CGFloat(now.timeIntervalSince(windowStart) / 60) * ppm)
                    .allowsHitTesting(false)
            }
        }
    }

    private func railCell(_ ch: GuideChannel) -> some View {
        Button { onRail(ch) } label: {
            VStack(spacing: 3) {
                Image(systemName: ch.icon)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(ch.accent.gradient, in: .rect(cornerRadius: 7))
                Text(ch.title)
                    .font(.system(size: 9, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: railW, height: rowH)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(ch.title) full schedule")
    }

    private func timeline(_ ch: GuideChannel, ppm: CGFloat, timelineW: CGFloat,
                          now: Date) -> some View {
        let visible = ch.slots.filter { $0.end > windowStart && $0.start < windowEnd }
        return HStack(spacing: 2) {
            // Lead-in gap when the first visible program starts inside the window.
            if let first = visible.first, first.start > windowStart {
                Color.clear
                    .frame(width: CGFloat(first.start.timeIntervalSince(windowStart) / 60) * ppm)
            }
            ForEach(visible) { slot in
                let visStart = max(slot.start, windowStart)
                let visEnd = min(slot.end, windowEnd)
                let w = max(20, CGFloat(visEnd.timeIntervalSince(visStart) / 60) * ppm - 2)
                programBlock(slot, channel: ch, width: w, airing: slot.contains(now))
            }
            Spacer(minLength: 0)
        }
        .frame(width: timelineW, height: rowH, alignment: .leading)
        .clipped()
    }

    private func programBlock(_ slot: ScheduledProgram, channel: GuideChannel,
                              width: CGFloat, airing: Bool) -> some View {
        Button { onTune(channel, slot) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.item.title)
                    .font(.caption.weight(airing ? .bold : .semibold))
                    .lineLimit(2)
                    .foregroundStyle(airing ? .white : .primary)
                Spacer(minLength: 0)
                Text(slot.start, style: .time)
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(airing ? .white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(width: width, height: rowH, alignment: .topLeading)
            .background(
                airing ? AnyShapeStyle(channel.accent.gradient)
                       : AnyShapeStyle(Color(.secondarySystemBackground)),
                in: .rect(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(channel.accent.opacity(airing ? 0 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Full-day schedule for one channel

struct ChannelScheduleRoute: Hashable { let channelID: String }

struct ChannelScheduleView: View {
    let channelID: String
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @State private var channel: GuideChannel?
    @State private var playing: ChannelLineup?

    var body: some View {
        List {
            if let ch = channel {
                ForEach(ch.slots) { slot in
                    Button {
                        let programs = ch.slots.drop { $0.id != slot.id }.map(\.item)
                        let now = Date()
                        let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
                        playing = ChannelLineup(items: Array(programs), startOffset: offset)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(slot.start, style: .time)
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot.item.title).font(.subheadline).foregroundStyle(.primary)
                                if slot.contains(Date()) {
                                    Text("On now").font(.caption2.weight(.bold))
                                        .foregroundStyle(Brand.primary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(channel?.title ?? "Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.dbVersion) { build() }
        .fullScreenCover(item: $playing) { box in
            if let player = PlayerView(lineup: box.items, startOffset: box.startOffset) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            }
        }
    }

    private func build() {
        let now = Date()
        if let preset = Channel.all.first(where: { $0.id == channelID }) {
            let pool = store.dbBrowse(contentType: preset.contentType, genre: preset.genre,
                                      sort: .popular, limit: 90)
                .filter { $0.videoURLParsed != nil }
            let slots = ChannelScheduler.schedule(channelID: preset.id, programs: pool, now: now)
            channel = GuideChannel(id: preset.id, number: 0, title: preset.title,
                                   accent: preset.accent, icon: preset.icon, slots: slots)
        } else if channelID.hasPrefix("user-") {
            let gid = channelID.replacingOccurrences(of: "user-", with: "")
            let ucs = (try? ctx.fetch(FetchDescriptor<UserChannel>())) ?? []
            guard let uc = ucs.first(where: { $0.id == gid }) else { return }
            let pool = store.dbBrowse(contentType: uc.contentType, decade: uc.decade,
                                      genre: uc.genre, sort: .popular, limit: 150)
                .filter { $0.videoURLParsed != nil }
            let slots = ChannelScheduler.schedule(channelID: channelID, programs: pool, now: now)
            channel = GuideChannel(id: channelID, number: 0, title: uc.name,
                                   accent: Color(hex: "#0047FF") ?? .blue,
                                   icon: "dot.radiowaves.left.and.right", slots: slots)
        }
    }
}

// MARK: - Create channel (native Form)

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
        NavigationStack {
            Form {
                Section {
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
                        ForEach(decades, id: \.self) {
                            Text(verbatim: "\($0)s").tag(Int?.some($0))
                        }
                    }
                } header: {
                    Text("Filters")
                } footer: {
                    Text("Pick any mix — your channel plays it straight through, all day.")
                }
                Section("Name") {
                    TextField(autoName, text: $name)
                }
            }
            .navigationTitle("Create a Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        ctx.insert(UserChannel(name: n.isEmpty ? autoName : n,
                                               genre: genre, contentType: type, decade: decade))
                        try? ctx.save()
                        SyncNudge.nudge(ctx)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#endif
