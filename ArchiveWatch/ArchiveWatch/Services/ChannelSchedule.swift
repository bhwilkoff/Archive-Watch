import SwiftUI

/// Channels on ONE clock (ORPHANED-FILMS #2; tvOS-DESIGN §9.1, iOS-DESIGN §8.6,
/// macOS-DESIGN Rule B8a). Owner, 2026-09-27: "Move forward with a single clock.
/// If you need a time zone to organize around, you can choose UTC, but all
/// times should show as their local times when they look at channels."
///
/// The pipeline (`tools/build_channel_schedule.py`) publishes every preset
/// channel's programs as one UTC timeline; every platform plays and draws from
/// that file, so a channel shows the same program at the same instant
/// everywhere. Times are only DISPLAYED in the viewer's zone. User channels are
/// personal and keep the local `ChannelScheduler`.
@MainActor
enum ChannelSchedule {
    struct Program { let title: String; let runtime: Int?; let url: String?; let type: String? }
    struct Day { let start: Int; let slots: [(id: String, seconds: Int)] }
    struct Published {
        let gap: Int
        let programs: [String: Program]
        let channels: [(id: String, title: String, days: [String: Day])]

        /// The first and last instants the file covers.
        var firstStart: Date? {
            channels.flatMap { $0.days.values.map(\.start) }.min().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
        var lastEnd: Date? {
            channels.compactMap { ch -> Int? in
                guard let key = ch.days.keys.max(), let d = ch.days[key] else { return nil }
                return d.slots.reduce(d.start) { $0 + $1.seconds + gap }
            }.min().map { Date(timeIntervalSince1970: TimeInterval($0)) }
        }
    }

    private(set) static var current: Published?
    private static let url = URL(string: "https://archivewatch.org/channel-schedule.json")!
    private static var cacheFile: URL? {
        // Caches: the one writable directory tvOS keeps (the writable-directory trap).
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("channel-schedule.json")
    }

    /// The schedule to draw from: the cached file, refreshed when it is older
    /// than six hours or ends within a day. nil only when there has never been
    /// a file on this device and the network cannot supply one.
    static func load(now: Date = .now) async -> Published? {
        if current == nil, let f = cacheFile, let data = try? Data(contentsOf: f) {
            current = parse(data)
        }
        let age = cacheFile.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]) }?
            .contentModificationDate.map { now.timeIntervalSince($0) } ?? .infinity
        let endingSoon = current?.lastEnd.map { $0.timeIntervalSince(now) < 24 * 3600 } ?? true
        if current == nil || age > 6 * 3600 || endingSoon {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let parsed = parse(data) {
                current = parsed
                if let f = cacheFile { try? data.write(to: f, options: .atomic) }
            }
        }
        return current
    }

    /// The preset channels as guide rows, numbered from `firstNumber`, covering
    /// the local broadcast day through the next 26 hours.
    static func guide(_ file: Published, store: AppStore, firstNumber: Int, now: Date = .now) -> [GuideChannel] {
        let from = max(ChannelScheduler.dayAnchor(for: now), file.firstStart ?? .distantPast)
        let until = now.addingTimeInterval(26 * 3600)
        var windows: [(id: String, title: String, slots: [(String, Date, Date)])] = []
        var ids = Set<String>()
        for ch in file.channels {
            var slots: [(String, Date, Date)] = []
            for key in ch.days.keys.sorted() {
                guard let day = ch.days[key] else { continue }
                var t = day.start
                for s in day.slots {
                    let start = Date(timeIntervalSince1970: TimeInterval(t))
                    let end = start.addingTimeInterval(TimeInterval(s.seconds))
                    if end > from && start < until { slots.append((s.id, start, end)); ids.insert(s.id) }
                    t += s.seconds + file.gap
                }
            }
            windows.append((ch.id, ch.title, slots))
        }
        #if os(tvOS)
        let known = store.dbItemsByIDs(Array(ids))
        #else
        let known = store.itemsByIDs(Array(ids))
        #endif
        var byID = Dictionary(known.map { ($0.archiveID, $0) },
                              uniquingKeysWith: { a, _ in a })
        var out: [GuideChannel] = []
        var number = firstNumber
        // Presets keep their app order and identity; a channel the file adds
        // later still appears, after them.
        let order = Channel.all.map(\.id)
        let sorted = windows.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
        for w in sorted where !w.slots.isEmpty {
            let slots = w.slots.compactMap { id, start, end -> ScheduledProgram? in
                guard let item = byID[id] ?? fallbackItem(id, file.programs[id]) else { return nil }
                byID[id] = item
                return ScheduledProgram(item: item, start: start, end: end)
            }
            let preset = Channel.all.first { $0.id == w.id }
            out.append(GuideChannel(id: w.id, number: number, title: preset?.title ?? w.title,
                                    accent: preset?.accent ?? .accentColor,
                                    icon: preset?.icon ?? "tv.fill", slots: slots))
            number += 1
        }
        return out
    }

    /// A program this device's catalog does not carry still airs, from the
    /// file's own title and address — a slot is never dropped and no time moves.
    private static func fallbackItem(_ id: String, _ p: Program?) -> Catalog.Item? {
        var json: [String: Any] = ["archiveID": id, "title": p?.title ?? id,
                                   "artworkSource": "generated", "contentType": p?.type ?? "feature-film"]
        if let u = p?.url { json["downloadURL"] = u }
        if let r = p?.runtime { json["runtimeSeconds"] = r }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(Catalog.Item.self, from: data)
    }

    static func parse(_ data: Data) -> Published? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["schema"] as? Int) == 1,
              let chans = root["channels"] as? [[String: Any]] else { return nil }
        var programs: [String: Program] = [:]
        for (id, v) in root["programs"] as? [String: [Any]] ?? [:] {
            func at(_ i: Int) -> Any? { i < v.count && !(v[i] is NSNull) ? v[i] : nil }
            programs[id] = Program(title: at(0) as? String ?? id, runtime: (at(1) as? NSNumber)?.intValue,
                                   url: at(2) as? String, type: at(3) as? String)
        }
        let channels = chans.compactMap { c -> (id: String, title: String, days: [String: Day])? in
            guard let id = c["id"] as? String, let days = c["days"] as? [String: [String: Any]] else { return nil }
            var out: [String: Day] = [:]
            for (key, d) in days {
                guard let start = (d["start"] as? NSNumber)?.intValue, let raw = d["slots"] as? [[Any]] else { continue }
                let slots = raw.compactMap { s -> (id: String, seconds: Int)? in
                    guard s.count >= 2, let sid = s[0] as? String, let secs = (s[1] as? NSNumber)?.intValue else { return nil }
                    return (sid, secs)
                }
                out[key] = Day(start: start, slots: slots)
            }
            return (id, c["title"] as? String ?? id, out)
        }
        guard !channels.isEmpty else { return nil }
        return Published(gap: root["gap"] as? Int ?? 120, programs: programs, channels: channels)
    }
}

/// The guide's error state (universal-feature-states): no schedule has ever
/// reached this device and the network cannot supply one.
struct ChannelGuideUnavailable: View {
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.slash").font(.largeTitle).foregroundStyle(.secondary)
            Text("The channel guide could not be loaded.").font(.headline)
            Text("Check your connection and try again.").font(.subheadline).foregroundStyle(.secondary)
            Button("Retry", action: retry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
