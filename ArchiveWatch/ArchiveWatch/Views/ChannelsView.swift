import SwiftUI
import SwiftData

// #1 / Channels P2+P3: a real TV guide. Each channel is a deterministic,
// date-seeded program schedule (ChannelScheduler) rendered as an old-school EPG
// grid — channel rows × half-hour time columns, program titles filling the slots.
// Tuning in tunes the channel from whatever's airing now and plays straight
// through (the F4 ContinuousPlayback path), with vintage PD commercials between
// programs (#89). See docs/design/channels-tv-guide.md.
struct Channel: Identifiable, Hashable {
    let id: String
    let title: String
    let tagline: String
    let hex: String
    let icon: String
    var contentType: String? = nil
    var genre: String? = nil
    var accent: Color { Color(hex: hex) ?? .accentColor }

    static let all: [Channel] = [
        .init(id: "drama",   title: "Drama Theater",   tagline: "The big stories", hex: "#FF5C35", icon: "theatermasks.fill", genre: "Drama"),
        .init(id: "comedy",  title: "Comedy Hour",     tagline: "Laughs around the clock", hex: "#E8A317", icon: "face.smiling.fill", genre: "Comedy"),
        .init(id: "noir",    title: "Crime & Mystery", tagline: "Shadows and suspects", hex: "#2D5BFF", icon: "magnifyingglass", genre: "Crime"),
        .init(id: "thrill",  title: "Thriller",        tagline: "Edge of your seat", hex: "#0047FF", icon: "bolt.fill", genre: "Thriller"),
        .init(id: "horror",  title: "Horror",          tagline: "After dark", hex: "#7C5BBA", icon: "moon.stars.fill", genre: "Horror"),
        .init(id: "western", title: "Western Trail",   tagline: "The frontier rolls on", hex: "#C9A66B", icon: "hare.fill", genre: "Western"),
        .init(id: "scifi",   title: "Sci-Fi Theater",  tagline: "Worlds beyond", hex: "#3FA796", icon: "atom", genre: "Science Fiction"),
        .init(id: "silent",  title: "Silent Cinema",   tagline: "The age before sound", hex: "#C9A66B", icon: "film.stack.fill", contentType: "silent-film"),
        .init(id: "cartoon", title: "Cartoon Classics",tagline: "Animation all day", hex: "#FF4D8D", icon: "paintbrush.fill", contentType: "animation"),
        .init(id: "news",    title: "Newsreel Desk",   tagline: "History as it broke", hex: "#8A8F98", icon: "newspaper.fill", contentType: "newsreel"),
        .init(id: "docs",    title: "Documentary",     tagline: "Real stories", hex: "#3FA796", icon: "globe.americas.fill", contentType: "documentary"),
        // TV channels (not just movies) — built from playable classic-TV items.
        .init(id: "tv",        title: "Classic TV",   tagline: "Vintage television", hex: "#2D5BFF", icon: "tv.fill", contentType: "tv-special"),
        .init(id: "tv-comedy", title: "TV Comedy",    tagline: "Sitcoms & sketch", hex: "#E8A317", icon: "tv.fill", contentType: "tv-special", genre: "Comedy"),
        .init(id: "tv-drama",  title: "TV Drama",     tagline: "Series drama", hex: "#FF5C35", icon: "tv.fill", contentType: "tv-special", genre: "Drama"),
        .init(id: "tv-western",title: "TV Westerns",  tagline: "Saddle up, every hour", hex: "#C9A66B", icon: "tv.fill", contentType: "tv-special", genre: "Western"),
    ]
}

/// A channel as the guide sees it: identity + its program pool + its schedule.
struct GuideChannel: Identifiable {
    let id: String
    let number: Int
    let title: String
    let accent: Color
    let icon: String
    let slots: [ScheduledProgram]
}

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserChannel.createdAt, order: .reverse) private var userChannels: [UserChannel]
    @State private var playing: ChannelLineup?
    @State private var showCreate = false
    @State private var showCommercialOptions = false
    @State private var guide: [GuideChannel] = []
    @State private var builtAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showCommercialOptions {
                CommercialBreakControl()
                    .padding(.horizontal, 80)
                    .padding(.bottom, 14)
                    .focusSection()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if guide.isEmpty {
                Spacer()
                Text("Building the guide…")
                    .font(.title2).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ChannelGuide(channels: guide, now: builtAt) { ch, slot in
                    tune(ch, from: slot)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { if guide.isEmpty { rebuild() } }
        .fullScreenCover(item: $playing) { box in
            if let screen = PlayerScreen(lineup: box.items, startOffset: box.startOffset) {
                screen
            } else { ChannelUnavailable() }
        }
        // fullScreenCover (not .sheet): a tvOS sheet leaves the TabView sidebar
        // visible at the edge, overlapping the modal's title (#4).
        .fullScreenCover(isPresented: $showCreate, onDismiss: rebuild) { CreateChannelSheet() }
    }

    private var header: some View {
        @Bindable var store = store
        return HStack(alignment: .center, spacing: 16) {
            Text("Channels")
                .font(.system(size: 54, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
            Spacer()
            // #3e: set commercial breaks (on/off + length) right from the guide,
            // without digging into Settings. Reveals the length pills below.
            Button { withAnimation(Motion.chrome) { showCommercialOptions.toggle() } } label: {
                Label("Commercials: \(commercialLabel)",
                      systemImage: store.channelCommercialBreaks ? "tv.fill" : "tv.slash")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.bordered)
            Button { showCreate = true } label: {
                Label("Create Channel", systemImage: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 20)
        // #2: reach the header controls by pressing Up from any program in the
        // top channel row, not just the program beneath them (tvOS focus section).
        .focusSection()
    }

    private var commercialLabel: String {
        CommercialBreakControl.shortLabel(on: store.channelCommercialBreaks,
                                          seconds: store.commercialBreakMaxSeconds)
    }

    // MARK: - Schedule build

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
            // contentType + genre together (TV channels use both; movie genre
            // channels pass contentType nil, type channels pass genre nil).
            // #2: a tighter top-N pool so channels skew to higher-interest titles
            // (the scheduler shuffles the WHOLE pool, so a big limit dilutes it).
            let raw = store.dbBrowse(contentType: ch.contentType, genre: ch.genre,
                                     sort: .popular, limit: 90)
            let slots = ChannelScheduler.schedule(channelID: ch.id, programs: playable(raw), now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: ch.id, number: number, title: ch.title,
                                    accent: ch.accent, icon: ch.icon, slots: slots))
            number += 1
        }
        builtAt = now
        guide = out
    }

    // The EPG shows program TITLES, not posters, so a channel needs PLAYABLE
    // items, not arty ones — requiring designed artwork needlessly emptied
    // channels (especially TV, whose art is sparse).
    private func playable(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter { $0.videoURLParsed != nil }
    }

    // MARK: - Tune in

    private func tune(_ channel: GuideChannel, from slot: ScheduledProgram) {
        let programs = channel.slots.drop { $0.id != slot.id }.map(\.item)
        // #92: if the tapped slot is the one airing NOW, join it in progress.
        let now = Date()
        let offset = slot.contains(now) ? max(0, now.timeIntervalSince(slot.start)) : 0
        playing = ChannelLineup(items: weaveCommercials(into: Array(programs)), startOffset: offset)
    }

    /// #89: drop a vintage PD commercial between programs (gated by setting).
    private func weaveCommercials(into programs: [Catalog.Item]) -> [Catalog.Item] {
        guard store.channelCommercialBreaks, programs.count > 1 else { return programs }
        let ads = store.dbRandomCommercials(limit: 60).filter { $0.videoURLParsed != nil }
        guard !ads.isEmpty else { return programs }
        var out: [Catalog.Item] = []
        out.reserveCapacity(programs.count * 2)
        for (i, program) in programs.enumerated() {
            out.append(program)
            if i < programs.count - 1 { out.append(ads[i % ads.count]) }
        }
        return out
    }
}

struct ChannelLineup: Identifiable {
    let id = UUID()
    let items: [Catalog.Item]
    var startOffset: TimeInterval = 0
}

// MARK: - Commercial-break length control (Channels view + Settings)

/// User-selectable commercial-break behavior shown as a pill row: Off, or a max
/// length the player caps each ad at (0 = play in full). Drives
/// `AppStore.channelCommercialBreaks` + `commercialBreakMaxSeconds`. Reused by
/// the Channels header reveal and by Settings.
struct CommercialBreakControl: View {
    @Environment(AppStore.self) private var store

    private struct Opt: Identifiable { let id: Int; let label: String; let on: Bool; let secs: Int }
    private let opts: [Opt] = [
        .init(id: 0, label: "Off",         on: false, secs: 0),
        .init(id: 1, label: "30 sec",      on: true,  secs: 30),
        .init(id: 2, label: "1 min",       on: true,  secs: 60),
        .init(id: 3, label: "2 min",       on: true,  secs: 120),
        .init(id: 4, label: "3 min",       on: true,  secs: 180),
        .init(id: 5, label: "Full length", on: true,  secs: 0),
    ]

    private func isActive(_ o: Opt) -> Bool {
        o.on ? (store.channelCommercialBreaks && store.commercialBreakMaxSeconds == o.secs)
             : !store.channelCommercialBreaks
    }

    /// Short label for the toggle button ("Off" / "1 min" / "Full").
    static func shortLabel(on: Bool, seconds: Int) -> String {
        guard on else { return "Off" }
        if seconds == 0 { return "Full" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) sec"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commercial breaks between titles")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(opts) { o in
                        Chip(label: o.label, isOn: isActive(o),
                             accent: Color(hex: "#FF5C35") ?? .orange) {
                            store.channelCommercialBreaks = o.on
                            if o.on { store.commercialBreakMaxSeconds = o.secs }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - The guide grid (proportional EPG)
//
// A real channel guide: a fixed time WINDOW (now → now + 3h) mapped across the
// width, with each program a block sized to its actual runtime (width ∝ minutes)
// on a shared time ruler — so programs start and end at their true times and
// stagger across channels instead of snapping to uniform columns.
//
// tvOS-native by construction: only the vertical axis scrolls (the reliable
// one), so the focus engine + automatic scroll-to-focus handle navigation —
// left/right walks a channel's programs, up/down lands on the temporally
// overlapping program in the adjacent channel (geometry-based focus). No fragile
// two-axis synchronized scrolling or offset-tracking required.

private struct ChannelGuide: View {
    let channels: [GuideChannel]
    let now: Date
    let onTune: (GuideChannel, ScheduledProgram) -> Void

    private let railW: CGFloat = 220
    private let rowH: CGFloat = 92
    private let windowMinutes: Double = 180   // 3-hour glanceable window
    private var windowEnd: Date { now.addingTimeInterval(windowMinutes * 60) }

    var body: some View {
        GeometryReader { geo in
            let timelineW = max(600, geo.size.width - railW - 120)   // 60pt padding each side
            let ppm = timelineW / windowMinutes
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ruler(timelineW: timelineW)
                    ForEach(channels) { ch in
                        ChannelRow(channel: ch, now: now, windowEnd: windowEnd,
                                   railW: railW, rowH: rowH, ppm: ppm, timelineW: timelineW,
                                   onTune: onTune)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.bottom, 40)
            }
        }
    }

    // Half-hour tick labels aligned to the timeline (first tick = NOW).
    private func ruler(timelineW: CGFloat) -> some View {
        let tickW = timelineW / CGFloat(windowMinutes / 30)
        return HStack(spacing: 0) {
            Color.clear.frame(width: railW)
            ForEach(0..<Int(windowMinutes / 30), id: \.self) { i in
                let t = now.addingTimeInterval(Double(i) * 1800)
                Text(i == 0 ? "NOW" : t.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(i == 0 ? Color(hex: "#FF5C35") ?? .orange : .white.opacity(0.6))
                    .frame(width: tickW, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.white.opacity(i == 0 ? 0.35 : 0.12)).frame(width: i == 0 ? 2 : 1)
                    }
            }
        }
        .frame(height: 30)
    }
}

private struct ChannelRow: View {
    let channel: GuideChannel
    let now: Date
    let windowEnd: Date
    let railW: CGFloat
    let rowH: CGFloat
    let ppm: CGFloat
    let timelineW: CGFloat
    let onTune: (GuideChannel, ScheduledProgram) -> Void

    private var visible: [ScheduledProgram] {
        channel.slots.filter { $0.end > now && $0.start < windowEnd }
    }

    var body: some View {
        HStack(spacing: 8) {
            rail
            HStack(spacing: 3) {
                ForEach(visible) { slot in
                    let visStart = max(slot.start, now)
                    let visEnd = min(slot.end, windowEnd)
                    let w = max(28, CGFloat(visEnd.timeIntervalSince(visStart) / 60) * ppm - 3)
                    ProgramBlock(slot: slot,
                                 isNow: slot.start <= now && slot.end > now,
                                 accent: channel.accent, width: w, height: rowH) {
                        onTune(channel, slot)
                    }
                }
                Spacer(minLength: 0)
            }
            // No .clipped(): clipping cut the focus-expanded block (#3b/#3d). The
            // blocks already sum to ~timelineW (slots are capped at windowEnd), so
            // only a focused block briefly overflows — which is what we want.
            .frame(width: timelineW, height: rowH, alignment: .leading)
        }
    }

    private var rail: some View {
        HStack(spacing: 12) {
            Image(systemName: channel.icon).font(.system(size: 24))
                .foregroundStyle(channel.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(channel.title).font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)                       // #3a: don't truncate channel names
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text("CH \(channel.number)").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: railW, height: rowH, alignment: .leading)
        .background(channel.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProgramBlock: View {
    let slot: ScheduledProgram
    let isNow: Bool
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    // #1: drive focus visuals from @FocusState (the BUTTON's focus), not
    // @Environment(\.isFocused) read at this parent level — that stayed false, so
    // the width expansion / opaque fill never fired (only .card's own highlight
    // showed). With this, short programs actually expand on highlight.
    @FocusState private var focused: Bool

    // #3d: a focused block expands rightward to a readable width so even very
    // short programs (cartoons, ad breaks) reveal their full title + info.
    private var renderWidth: CGFloat { focused ? max(width, 360) : width }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                if isNow {
                    Text("ON NOW").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(focused ? .white : accent)
                }
                Text(slot.item.title)                         // #3a: wraps, never clipped when focused
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(focused ? 4 : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if focused || width > 150, let y = slot.item.year {   // year restored
                    Text(verbatim: String(y)).font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(width: renderWidth, height: height, alignment: .topLeading)
            // Fully opaque fill (#3b: never let neighbors show through the
            // focused block — the old accent.opacity(0.9) was the culprit).
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(focused ? accent : Color(white: 0.12)))
            .animation(Motion.focus, value: focused)
        }
        .buttonStyle(.card)
        .focused($focused)
        .zIndex(focused ? 1 : 0)
    }
}

private struct ChannelUnavailable: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 24) {
            Text("This channel has no playable titles yet.")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            Button("Back") { dismiss() }
                .buttonStyle(.borderedProminent)
                .focused($focused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear { focused = true }
    }
}

// MARK: - #1b user channels: create sheet

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

    /// Name the channel from its filters when the curator doesn't type one.
    private var autoName: String {
        let parts = [decade.map { "\(String($0))s" }, genre, type.map(typeLabel)].compactMap { $0 }
        return parts.isEmpty ? "My Channel" : parts.joined(separator: " ")
    }

    private var canSave: Bool { genre != nil || type != nil || decade != nil }

    var body: some View {
        ScrollView {
            // Centered, fixed-width column so the modal reads as a native tvOS
            // form and never collides with the screen edges (#4).
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create a Channel")
                        .font(.system(size: 48, weight: .heavy, design: .serif))
                        .foregroundStyle(.white)
                    Text("Pick any mix of filters — it plays straight through, all day.")
                        .font(.title3).foregroundStyle(.white.opacity(0.6))
                }

                PillSelectRow(title: "Genre", options: genres, label: { $0 },
                              selection: $genre, accent: Color(hex: "#FF5C35") ?? .orange)
                PillSelectRow(title: "Type", options: types, label: typeLabel,
                              selection: $type, accent: Color(hex: "#2D5BFF") ?? .blue)
                PillSelectRow(title: "Era", options: decades, label: { "\(String($0))s" },
                              selection: $decade, accent: Color(hex: "#C9A66B") ?? .brown)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name").font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                    TextField(autoName, text: $name)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .padding(.horizontal, 24).padding(.vertical, 18)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    Text("Leave blank to use “\(autoName)”.")
                        .font(.callout).foregroundStyle(.white.opacity(0.45))
                }

                // Uniform full-width primary + secondary buttons (#4).
                VStack(spacing: 16) {
                    Button {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        ctx.insert(UserChannel(name: n.isEmpty ? autoName : n,
                                               genre: genre, contentType: type, decade: decade))
                        try? ctx.save(); dismiss()
                    } label: {
                        Label("Create Channel", systemImage: "plus.circle.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).disabled(!canSave)

                    Button { dismiss() } label: {
                        Text("Cancel").font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)   // center the column
            .padding(.horizontal, 80)
            .padding(.vertical, 80)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
