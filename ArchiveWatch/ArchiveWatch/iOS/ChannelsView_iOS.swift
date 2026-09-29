#if os(iOS)
import SwiftUI
import SwiftData

// Channels (PARITY §5) — the touch guide for the tvOS EPG, reworked 2026-06-12
// as a TRUE TV-listing grid (owner: "a series of tiles rather than the true
// grid that is essential for it to feel like you are looking at a tv listing").
// Preset channels play the ONE UTC timeline the pipeline publishes
// (ChannelSchedule, iOS-DESIGN §8.6); user channels keep ChannelScheduler. Anatomy mirrors tvOS's proportional EPG: a pinned
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
    @State private var scheduleMissing = false
    /// iOS-DESIGN §2.5c: a phone opens on the On Now list; the grid is one tap
    /// away. Regular width has room for the grid and shows only the grid.
    @AppStorage("channels.phoneMode") private var phoneMode = PhoneMode.onNow.rawValue

    private enum PhoneMode: String { case onNow, guide }
    private var windowMinutes: Double { hSize == .regular ? 180 : 120 }
    private var showsList: Bool { hSize != .regular && phoneMode == PhoneMode.onNow.rawValue }

    var body: some View {
        Group {
            if scheduleMissing {
                ChannelGuideUnavailable { Task { await load() } }
            } else if guide.isEmpty {
                ProgressView("Building the guide…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    if hSize != .regular {
                        Picker("View", selection: $phoneMode) {
                            Text("On Now").tag(PhoneMode.onNow.rawValue)
                            Text("Guide").tag(PhoneMode.guide.rawValue)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    if showsList {
                        OnNowList(channels: guide,
                                  onTune: tune(_:from:),
                                  onSchedule: { router.push(ChannelScheduleRoute(channelID: $0.id)) })
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
            }
        }
        .navigationTitle("Channels")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // A real toggle (the Mac loop, v1.42.816): an icon that swaps
                // pictures does not read as on/off; a toggle button shows its
                // state, and VoiceOver says "Commercial Breaks, on".
                @Bindable var store = store
                Toggle(isOn: $store.channelCommercialBreaks) {
                    Label("Commercial Breaks", systemImage: "tv")
                }
                .toggleStyle(.button)
                .help("Commercial Breaks")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").accessibilityLabel("Create channel")
                }
            }
        }
        .task(id: store.dbVersion) { await load() }
        #if DEBUG
        // Harness door: AW_CHANNELS_MODE=guide|onNow opens that view, so the
        // device sweep can photograph both without a tap.
        .onAppear {
            if let m = ProcessInfo.processInfo.environment["AW_CHANNELS_MODE"],
               PhoneMode(rawValue: m) != nil { phoneMode = m }
        }
        #endif
        .onChange(of: userChannels.count) { rebuild() }
        .fullScreenCover(item: $playing) { box in
            if let cid = box.channelID, let start = guide.firstIndex(where: { $0.id == cid }) {
                SurfPlayer(channels: guide, index: start, first: box,
                           weave: weaveCommercials(into:))
            } else if let player = PlayerView(lineup: box.items, startOffset: box.startOffset) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            }
        }
        .sheet(isPresented: $showCreate, onDismiss: rebuild) { CreateChannelSheet() }
    }

    /// Shift the visible window, clamped to the broadcast day (anchor → +20h),
    /// never earlier than the published schedule's first program.
    /// Landing within 5 minutes of NOW snaps back to live mode.
    private func shift(by minutes: Double) {
        let now = Date()
        let proposed = (windowStart ?? now).addingTimeInterval(minutes * 60)
        let floor = max(ChannelScheduler.dayAnchor(for: now),
                        ChannelSchedule.current?.firstStart ?? .distantPast)
        let ceiling = now.addingTimeInterval(20 * 3600)
        let clamped = min(max(proposed, floor), ceiling)
        windowStart = abs(clamped.timeIntervalSince(now)) < 300 ? nil : clamped
    }

    // MARK: schedule build (mirrors tvOS ChannelsView.rebuild)

    private func load() async {
        scheduleMissing = false
        scheduleMissing = await ChannelSchedule.load() == nil
        rebuild()
        #if DEBUG
        // Harness door: AW_TUNE_CHANNEL=<id> tunes that channel on launch.
        if let cid = ProcessInfo.processInfo.environment["AW_TUNE_CHANNEL"], playing == nil {
            // After the screen is up: a cover set during the first task is
            // dropped by the presentation machinery.
            try? await Task.sleep(for: .seconds(2))
            if let ch = guide.first(where: { $0.id == cid }),
               let slot = ch.slots.first(where: { $0.contains(Date()) })
                   ?? ch.slots.first(where: { $0.start > Date() }) {
                tune(ch, from: slot)
            }
        }
        #endif
    }

    private func rebuild() {
        let now = Date()
        var out: [GuideChannel] = []
        var number = 2
        for uc in userChannels {
            let pool = playable(store.dbBrowse(contentType: uc.contentType, decade: uc.decade,
                                               genre: uc.genre, sort: .popular, limit: 150).filter(\.isRecommendable))
            let slots = ChannelScheduler.schedule(channelID: "user-\(uc.id)", programs: pool, now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: "user-\(uc.id)", number: number, title: uc.name,
                                    accent: Color(hex: "#0047FF") ?? .blue,
                                    icon: "dot.radiowaves.left.and.right", slots: slots))
            number += 1
        }
        if let file = ChannelSchedule.current {
            out += ChannelSchedule.guide(file, store: store, firstNumber: number, now: now)
        }
        builtAt = now
        guide = out
    }

    private func playable(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter { $0.videoURLParsed != nil }
    }

    // MARK: tune in

    private func tune(_ channel: GuideChannel, from slot: ScheduledProgram) {
        let programs = channel.slots.drop { $0.id != slot.id }.map(\.item)
        let now = Date()
        let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
        playing = ChannelLineup(items: weaveCommercials(into: Array(programs)), startOffset: offset,
                                channelID: channel.id)
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
    /// The guide channel this was tuned from — set when surfing is possible
    /// (iOS-DESIGN §2.5d).
    var channelID: String? = nil
}

// MARK: - On Now (iOS-DESIGN §2.5c): the phone's first view of Channels
//
// One row per channel, readable at any Dynamic Type size: the program airing
// now in full, how far in it is, when it ends, and what follows. The row tunes
// in; the calendar button opens the channel's day. A List reflows where a
// fixed-height grid row cannot, and it never cuts a five-minute cartoon down to
// a sliver of letters.

private struct OnNowList: View {
    /// The icon's square grows with Dynamic Type, or the symbol outgrows it.
    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 44
    let channels: [GuideChannel]
    let onTune: (GuideChannel, ScheduledProgram) -> Void
    let onSchedule: (GuideChannel) -> Void

    var body: some View {
        // Redrawn every minute so progress and "ends" stay true while the
        // screen is open.
        TimelineView(.everyMinute) { context in
            List(channels) { ch in
                row(ch, now: context.date)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func row(_ ch: GuideChannel, now: Date) -> some View {
        let current = ch.slots.first { $0.contains(now) }
        let next = ch.slots.first { $0.start >= (current?.end ?? now) }
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let slot = current ?? next { onTune(ch, slot) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: ch.icon)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: iconSide, height: iconSide)
                        .background(ch.accent.gradient, in: .rect(cornerRadius: 10))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ch.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let slot = current {
                            Text(slot.item.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            ProgressView(value: now.timeIntervalSince(slot.start),
                                         total: max(1, slot.end.timeIntervalSince(slot.start)))
                                .tint(ch.accent)
                            Text("Ends \(slot.end.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if let slot = next {
                            Text(slot.item.title)
                                .font(.headline)
                                .lineLimit(2)
                            Text("Starts \(slot.start.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if current != nil, let slot = next {
                            Text("Next: \(slot.item.title) · \(slot.start.formatted(date: .omitted, time: .shortened))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(current.map { "\(ch.title), on now: \($0.item.title)" } ?? ch.title)
            .accessibilityHint("Tunes in")

            Button { onSchedule(ch) } label: {
                Image(systemName: "calendar")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("\(ch.title) schedule")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Channel surfing in the player (iOS-DESIGN §2.5d)
//
// Owner, 2026-09-27: "allowing users to navigate easily around the channels."
// The phone guides people keep using let you change channel without leaving
// the picture (Pluto's 2026 redesign removed it and its rating fell from 3.15
// to 2.32). AVPlayerViewController takes no custom transport buttons on iOS, so
// a strip over the video — previous channel, the channel and what is on,
// next channel — shows on tune-in and with the player's own controls on a tap,
// then fades. Changing channel joins that channel's program where it is now.

private struct SurfPlayer: View {
    let channels: [GuideChannel]
    @State var index: Int
    @State private var lineup: ChannelLineup
    @State private var stripVisible = true
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var hideTask: Task<Void, Never>?
    let weave: ([Catalog.Item]) -> [Catalog.Item]

    init(channels: [GuideChannel], index: Int, first: ChannelLineup,
         weave: @escaping ([Catalog.Item]) -> [Catalog.Item]) {
        self.channels = channels
        _index = State(initialValue: index)
        _lineup = State(initialValue: first)
        self.weave = weave
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let player = PlayerView(lineup: lineup.items, startOffset: lineup.startOffset) {
                player.onTapVideo { showStrip() }
                    .id(lineup.id)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            }
            if stripVisible { strip.transition(.opacity) }
        }
        .onAppear { showStrip() }
        #if DEBUG
        // Harness door: AW_SURF=N changes channel N times, 6 s apart.
        .task {
            let n = Int(ProcessInfo.processInfo.environment["AW_SURF"] ?? "") ?? 0
            for _ in 0..<n {
                try? await Task.sleep(for: .seconds(6))
                surf(1)
            }
        }
        #endif
    }

    private var channel: GuideChannel { channels[index] }

    private var strip: some View {
        let now = Date()
        let onNow = channel.slots.first { $0.contains(now) }
        // Regular width (IPAD-DESIGN §5c): a finger-sized capsule on a 13-inch
        // screen, where the phone's 44pt chevrons were the smallest thing on it.
        let wide = hSize == .regular
        let button: CGFloat = wide ? 60 : 44
        return HStack(spacing: wide ? 16 : 10) {
            Button { surf(-1) } label: {
                Image(systemName: "chevron.up").font(wide ? .title2.weight(.semibold) : .headline)
                    .frame(width: button, height: button)
            }
            .accessibilityLabel("Previous channel, \(channels[(index - 1 + channels.count) % channels.count].title)")
            VStack(spacing: 2) {
                Text(channel.title).font(wide ? .headline : .subheadline.weight(.semibold))
                if let onNow {
                    Text(onNow.item.title).font(wide ? .subheadline : .caption)
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(minWidth: wide ? 220 : 140)
            Button { surf(1) } label: {
                Image(systemName: "chevron.down").font(wide ? .title2.weight(.semibold) : .headline)
                    .frame(width: button, height: button)
            }
            .accessibilityLabel("Next channel, \(channels[(index + 1) % channels.count].title)")
        }
        .padding(.horizontal, 6)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial, in: .capsule)
        .environment(\.colorScheme, .dark)
        .padding(.top, 64)
    }

    private func showStrip() {
        withAnimation(.easeInOut(duration: 0.2)) { stripVisible = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { stripVisible = false }
        }
    }

    /// Tune the neighboring channel where it is now: the program airing, from
    /// its current second, or the next one if the channel is between programs.
    private func surf(_ step: Int) {
        let now = Date()
        for k in 1...channels.count {
            let i = (index + step * k + channels.count * k) % channels.count
            let ch = channels[i]
            guard let slot = ch.slots.first(where: { $0.contains(now) })
                ?? ch.slots.first(where: { $0.start > now }) else { continue }
            let programs = ch.slots.drop { $0.id != slot.id }.map(\.item)
            let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
            index = i
            lineup = ChannelLineup(items: weave(Array(programs)), startOffset: offset, channelID: ch.id)
            showStrip()
            return
        }
    }
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

    // The window's start (NOW when live), then the clock's own :00 and :30 at
    // their true positions; labels at start + 30 min read "12:31, 1:01…".
    private func ruler(timelineW: CGFloat) -> some View {
        let ppm = timelineW / CGFloat(windowMinutes)
        let cal = Calendar.current
        let toNext = Double(30 - cal.component(.minute, from: windowStart) % 30) * 60
            - Double(cal.component(.second, from: windowStart))
        // No mark in the last quarter hour: its label would run off the edge.
        let marks = stride(from: toNext, to: windowMinutes * 60 - 900, by: 1800)
            .map { windowStart.addingTimeInterval($0) }
        return ZStack(alignment: .topLeading) {
            tick(isLive ? "NOW" : windowStart.formatted(date: .omitted, time: .shortened),
                 strong: isLive)
                .offset(x: railW + 4)
            ForEach(marks, id: \.self) { t in
                let x = CGFloat(t.timeIntervalSince(windowStart) / 60) * ppm
                if x > 56 {   // one too close to the start would print over it
                    tick(t.formatted(date: .omitted, time: .shortened), strong: false)
                        .offset(x: railW + 4 + x)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        .background(.background)   // pinned header must occlude rows beneath
    }

    private func tick(_ label: String, strong: Bool) -> some View {
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(strong ? Brand.primary : .secondary)
            .padding(.leading, 4)
            .overlay(alignment: .leading) {
                Rectangle().fill(.secondary.opacity(0.25)).frame(width: 1)
            }
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
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
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
                let w = max(8, CGFloat(visEnd.timeIntervalSince(visStart) / 60) * ppm - 2)
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
            // A block too narrow for words draws none: at 390pt a five-minute
            // cartoon is ~12pt wide, and its title broke into a column of
            // single letters. Its name is in the accessibility label and in
            // the channel's schedule.
            VStack(alignment: .leading, spacing: 2) {
                // 84pt, not 44: between the two a title still broke mid-word
                // ("Moo / nbird") on the iPad guide.
                if width >= 84 {
                    Text(slot.item.title)
                        .font(.caption.weight(airing ? .bold : .semibold))
                        .lineLimit(2)
                        .foregroundStyle(airing ? .white : .primary)
                }
                Spacer(minLength: 0)
                if width >= 72 {
                    Text(slot.start, style: .time)
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                        .foregroundStyle(airing ? .white.opacity(0.85) : .secondary)
                }
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
        .hoverEffect(.highlight)   // IPAD-DESIGN §11.1
        .help(slot.item.title)   // with a pointer, a block too narrow for words still names itself
        .filmContextMenu(slot.item.archiveID)   // the poster's menu (IPAD-DESIGN §11.2)
        .accessibilityLabel("\(slot.item.title), \(slot.start.formatted(date: .omitted, time: .shortened))")
    }
}

// MARK: - Full-day schedule for one channel

struct ChannelScheduleRoute: Hashable { let channelID: String }

/// A schedule's time column: as wide as the widest time in this locale at this
/// text size, on one line. A fixed 76pt broke "12:01 PM" in two on the iPad.
private struct ScheduleTime: View {
    let date: Date
    private static let widest: [String] = [0, 12].map { h in
        let d = Calendar.current.date(bySettingHour: h, minute: 58, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(Self.widest, id: \.self) { Text($0).hidden() }
            Text(date, style: .time)
        }
        .lineLimit(1)
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

struct ChannelScheduleView: View {
    let channelID: String
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @State private var channel: GuideChannel?
    @State private var playing: ChannelLineup?

    var body: some View {
        ScrollViewReader { proxy in
        List {
            if let ch = channel {
                ForEach(runs(ch.slots), id: \.first!.id) { run in
                    if run.count >= 3 {
                        // Three or more shorts in a row fold into one line
                        // (iOS-DESIGN §2.5c): a cartoon channel is otherwise a
                        // wall of five-minute rows.
                        DisclosureGroup {
                            ForEach(run) { slot in slotRow(ch, slot) }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                ScheduleTime(date: run.first!.start)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(run.count) short films")
                                        .font(.body)
                                    Text("Until \(run.last!.end.formatted(date: .omitted, time: .shortened))")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    if run.contains(where: { $0.contains(Date()) }) {
                                        Text("On now").font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Brand.primary)
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(run) { slot in slotRow(ch, slot) }
                    }
                }
            }
        }
        .readableListWidth()
        // Opens on what is airing (§2.5c): the day starts at the broadcast
        // anchor, hours before now, and the viewer came for now.
        .onChange(of: channel?.id) {
            guard let ch = channel,
                  let run = runs(ch.slots).first(where: { r in r.contains { $0.contains(Date()) } })
            else { return }
            proxy.scrollTo(run.first!.id, anchor: .top)
        }
        }
        .navigationTitle(channel?.title ?? "Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.dbVersion) {
            if Channel.all.contains(where: { $0.id == channelID }) { _ = await ChannelSchedule.load() }
            build()
        }
        .fullScreenCover(item: $playing) { box in
            if let player = PlayerView(lineup: box.items, startOffset: box.startOffset) {
                player.ignoresSafeArea()
            } else {
                ContentUnavailableView("Channel unavailable", systemImage: "tv.slash")
            }
        }
    }

    /// Consecutive programs under fifteen minutes form one run; every other
    /// program is a run of one.
    private func runs(_ slots: [ScheduledProgram]) -> [[ScheduledProgram]] {
        var out: [[ScheduledProgram]] = []
        for slot in slots {
            let short = slot.end.timeIntervalSince(slot.start) < 15 * 60
            if short, let last = out.last?.last, last.end.timeIntervalSince(last.start) < 15 * 60 {
                out[out.count - 1].append(slot)
            } else {
                out.append([slot])
            }
        }
        return out
    }

    private func slotRow(_ ch: GuideChannel, _ slot: ScheduledProgram) -> some View {
        Button {
            let programs = ch.slots.drop { $0.id != slot.id }.map(\.item)
            let now = Date()
            let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
            playing = ChannelLineup(items: Array(programs), startOffset: offset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ScheduleTime(date: slot.start)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.item.title).font(.body).foregroundStyle(.primary)
                    if slot.contains(Date()) {
                        Text("On now").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.primary)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func build() {
        let now = Date()
        if Channel.all.contains(where: { $0.id == channelID }) {
            // The same published timeline as the guide, so the list and the
            // grid can never disagree about what is on.
            channel = ChannelSchedule.current.flatMap {
                ChannelSchedule.guide($0, store: store, firstNumber: 0, now: now)
                    .first { $0.id == channelID }
            }
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
        ContentType.label(t)
    }
    private var autoName: String {
        let parts = [decade.map { "\(String($0))s" }, genre, type.map(typeLabel)].compactMap { $0 }
        return parts.isEmpty ? "My Channel" : parts.joined(separator: " ")
    }
    private var canSave: Bool { UserChannel.canCreate(genre: genre, contentType: type, decade: decade) }

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
                    // A refusal, the only caption this form carries: Create
                    // is off until a filter is chosen (the Mac says the same).
                    if !canSave { Text("Choose at least one filter.") }
                }
                Section("Name") {
                    TextField(autoName, text: $name)
                }
            }
            .navigationTitle("Create a Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
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
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
    }
}

#endif
