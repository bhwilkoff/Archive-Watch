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
    @State private var guide: [GuideChannel] = []
    @State private var builtAt = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
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
            if let screen = PlayerScreen(lineup: box.items) { screen } else { ChannelUnavailable() }
        }
        .sheet(isPresented: $showCreate, onDismiss: rebuild) { CreateChannelSheet() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Channels")
                    .font(.system(size: 48, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                Text("What's on now — tune in and it plays straight through.")
                    .font(.title3).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Button { showCreate = true } label: {
                Label("Create Channel", systemImage: "plus.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 80)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }

    // MARK: - Schedule build

    private func rebuild() {
        let now = Date()
        var out: [GuideChannel] = []
        var number = 2
        for uc in userChannels {
            let pool = playable(store.dbBrowse(contentType: uc.contentType, decade: uc.decade,
                                               genre: uc.genre, sort: .popular, limit: 250))
            let slots = ChannelScheduler.schedule(channelID: "user-\(uc.id)", programs: pool, now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: "user-\(uc.id)", number: number, title: uc.name,
                                    accent: Color(hex: "#0047FF") ?? .blue,
                                    icon: "dot.radiowaves.left.and.right", slots: slots))
            number += 1
        }
        for ch in Channel.all {
            let raw = ch.genre.map { store.dbBrowse(genre: $0, sort: .popular, limit: 200) }
                ?? store.dbBrowse(contentType: ch.contentType, sort: .popular, limit: 200)
            let slots = ChannelScheduler.schedule(channelID: ch.id, programs: playable(raw), now: now)
            guard !slots.isEmpty else { continue }
            out.append(GuideChannel(id: ch.id, number: number, title: ch.title,
                                    accent: ch.accent, icon: ch.icon, slots: slots))
            number += 1
        }
        builtAt = now
        guide = out
    }

    private func playable(_ items: [Catalog.Item]) -> [Catalog.Item] {
        items.filter { $0.videoURLParsed != nil && $0.hasDesignedArtwork }
    }

    // MARK: - Tune in

    private func tune(_ channel: GuideChannel, from slot: ScheduledProgram) {
        let programs = channel.slots.drop { $0.id != slot.id }.map(\.item)
        playing = ChannelLineup(items: weaveCommercials(into: Array(programs)))
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

struct ChannelLineup: Identifiable { let id = UUID(); let items: [Catalog.Item] }

// MARK: - The guide grid (retro EPG)

private struct ChannelGuide: View {
    let channels: [GuideChannel]
    let now: Date
    let onTune: (GuideChannel, ScheduledProgram) -> Void

    // 4 half-hour columns starting at the current half-hour floor.
    private var columnTimes: [Date] {
        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        let floored = cal.date(bySettingHour: cal.component(.hour, from: now),
                               minute: minute < 30 ? 0 : 30, second: 0, of: now) ?? now
        return (0..<4).map { floored.addingTimeInterval(Double($0) * 1800) }
    }

    private let railW: CGFloat = 240
    private let colW: CGFloat = 360
    private let rowH: CGFloat = 116

    var body: some View {
        ScrollView([.vertical], showsIndicators: false) {
            VStack(spacing: 6) {
                timeHeader
                ForEach(channels) { ch in
                    ChannelRow(channel: ch, columnTimes: columnTimes, now: now,
                               railW: railW, colW: colW, rowH: rowH, onTune: onTune)
                }
            }
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
    }

    private var timeHeader: some View {
        HStack(spacing: 6) {
            Text("NOW")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: railW, alignment: .leading)
            ForEach(columnTimes, id: \.self) { t in
                Text(t.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: colW, alignment: .leading)
            }
        }
    }
}

private struct ChannelRow: View {
    let channel: GuideChannel
    let columnTimes: [Date]
    let now: Date
    let railW: CGFloat
    let colW: CGFloat
    let rowH: CGFloat
    let onTune: (GuideChannel, ScheduledProgram) -> Void

    var body: some View {
        HStack(spacing: 6) {
            // Channel rail
            HStack(spacing: 12) {
                Image(systemName: channel.icon).font(.system(size: 26))
                    .foregroundStyle(channel.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title).font(.system(size: 21, weight: .bold))
                        .foregroundStyle(.white).lineLimit(1)
                    Text("CH \(channel.number)").font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: railW, height: rowH, alignment: .leading)
            .background(channel.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            ForEach(Array(columnTimes.enumerated()), id: \.offset) { idx, t in
                let slot = ChannelScheduler.program(in: channel.slots, at: t)
                let prevSlot = idx > 0 ? ChannelScheduler.program(in: channel.slots, at: columnTimes[idx - 1]) : nil
                GuideCell(slot: slot,
                          continues: slot != nil && slot?.id == prevSlot?.id,
                          isNow: idx == 0,
                          accent: channel.accent,
                          width: colW, height: rowH) {
                    if let slot { onTune(channel, slot) }
                }
            }
        }
    }
}

private struct GuideCell: View {
    let slot: ScheduledProgram?
    let continues: Bool
    let isNow: Bool
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isFocused ? accent.opacity(0.9) : Color.white.opacity(0.08))
                if let slot {
                    if continues {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.compact.right")
                            Text(slot.item.title).lineLimit(1)
                        }
                        .font(.system(size: 17))
                        .foregroundStyle((isFocused ? Color.white : .white.opacity(0.45)))
                        .padding(.horizontal, 16)
                    } else {
                        VStack(alignment: .leading, spacing: 5) {
                            if isNow {
                                Text("ON NOW").font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(isFocused ? .white : accent)
                            }
                            Text(slot.item.title)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(2)
                            if let y = slot.item.year {
                                Text(verbatim: String(y))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text("—").font(.system(size: 18)).foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 16)
                }
            }
        }
        .buttonStyle(.card)
        .frame(width: width, height: height)
        .disabled(slot == nil)
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
    @State private var genre = "Any"
    @State private var type = "Any"
    @State private var decade = 0   // 0 = Any
    @FocusState private var nameFocused: Bool

    private let genres = ["Any", "Drama", "Comedy", "Crime", "Thriller", "Romance",
                          "Action", "Horror", "Mystery", "Western", "Documentary",
                          "Adventure", "War", "Fantasy", "Family", "Music", "Science Fiction"]
    private let types = ["Any", "feature-film", "animation", "silent-film",
                         "short-film", "newsreel", "documentary"]
    private let decades = [0, 1900, 1910, 1920, 1930, 1940, 1950, 1960, 1970, 1980, 1990, 2000, 2010]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        (genre != "Any" || type != "Any" || decade != 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Create a Channel").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
            TextField("Channel name", text: $name)
                .textFieldStyle(.plain).padding(14)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .focused($nameFocused)
            Picker("Genre", selection: $genre) { ForEach(genres, id: \.self) { Text($0) } }
            Picker("Type", selection: $type) {
                ForEach(types, id: \.self) { Text($0 == "Any" ? "Any" : $0.replacingOccurrences(of: "-", with: " ").capitalized) }
            }
            Picker("Era", selection: $decade) {
                ForEach(decades, id: \.self) { Text($0 == 0 ? "Any" : "\(String($0))s") }
            }
            HStack(spacing: 20) {
                Button("Create") {
                    ctx.insert(UserChannel(
                        name: name.trimmingCharacters(in: .whitespaces),
                        genre: genre == "Any" ? nil : genre,
                        contentType: type == "Any" ? nil : type,
                        decade: decade == 0 ? nil : decade))
                    try? ctx.save(); dismiss()
                }
                .buttonStyle(.borderedProminent).disabled(!canSave)
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
            }
            .padding(.top, 8)
        }
        .padding(60)
        .frame(maxWidth: 1000, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.93).ignoresSafeArea())
        .onAppear { nameFocused = true }
    }
}
