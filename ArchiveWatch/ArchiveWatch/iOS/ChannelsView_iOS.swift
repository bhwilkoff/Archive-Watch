#if os(iOS)
import SwiftUI
import SwiftData

// Channels (PARITY §5) — the touch guide for the tvOS EPG. Same deterministic
// date-seeded schedule (shared ChannelScheduler) and the same presets
// (Models/Channels.swift), rendered as a native list: each row shows what's
// airing NOW with time remaining; tap to tune in joined-in-progress (#92) with
// vintage commercial breaks woven between programs (#89). A row's chevron opens
// today's full schedule; future slots start the lineup from there.

struct ChannelsRoute: Hashable {}

struct ChannelsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.modelContext) private var ctx
    @Query(sort: \UserChannel.createdAt, order: .reverse) private var userChannels: [UserChannel]
    @State private var guide: [GuideChannel] = []
    @State private var builtAt = Date()
    @State private var playing: ChannelLineup?
    @State private var showCreate = false

    var body: some View {
        List {
            if !userChannels.isEmpty {
                Section("Your Channels") {
                    ForEach(guide.filter { $0.id.hasPrefix("user-") }) { ch in
                        channelRow(ch)
                    }
                    .onDelete(perform: deleteUserChannels)
                }
            }
            Section(userChannels.isEmpty ? "" : "Channels") {
                ForEach(guide.filter { !$0.id.hasPrefix("user-") }) { ch in
                    channelRow(ch)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus").accessibilityLabel("Create channel")
                }
            }
        }
        .overlay {
            if guide.isEmpty {
                ProgressView("Building the guide…")
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

    // MARK: rows

    private func channelRow(_ ch: GuideChannel) -> some View {
        let now = Date()
        let current = ch.slots.first { $0.contains(now) }
        let next = ch.slots.first { $0.start > now }
        return HStack(spacing: 12) {
            Button { tune(ch, from: current ?? ch.slots[0]) } label: {
                HStack(spacing: 12) {
                    Image(systemName: ch.icon)
                        .font(.headline).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(ch.accent.gradient, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ch.title).font(.headline).foregroundStyle(.primary)
                        if let cur = current {
                            Text("Now: \(cur.item.title)")
                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            if let nx = next {
                                Text("Next: \(nx.item.title)")
                                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                    }
                    Spacer()
                    if let cur = current {
                        Text(minutesLeft(cur, now: now))
                            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.borderless).tint(.primary)
            Button { router.push(ChannelScheduleRoute(channelID: ch.id)) } label: {
                Image(systemName: "calendar")
                    .accessibilityLabel("\(ch.title) schedule")
            }
            .buttonStyle(.borderless)
        }
    }

    private func minutesLeft(_ slot: ScheduledProgram, now: Date) -> String {
        let mins = max(0, Int(slot.end.timeIntervalSince(now) / 60))
        return "\(mins)m left"
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

    /// #89: drop a vintage PD commercial between programs.
    private func weaveCommercials(into programs: [Catalog.Item]) -> [Catalog.Item] {
        guard programs.count > 1 else { return programs }
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
