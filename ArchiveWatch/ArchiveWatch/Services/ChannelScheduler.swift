import Foundation

// Channels P2 (#90): a deterministic, date-seeded program schedule.
//
// Given a channel's program pool and a date, produce a reproducible timeline:
// the same channel shows the same program at the same wall-clock moment on every
// Apple TV, with no backend (Decision 009/010). The seed is hash(channelID +
// yyyy-mm-dd), so the grid is stable for the day and rolls over tomorrow.
//
// Commercials are a *playback* concern (woven into the lineup in ChannelsView);
// the schedule models PROGRAMS only, with a small inter-program buffer so times
// drift the way a real channel does. See docs/design/channels-tv-guide.md.

struct ScheduledProgram: Identifiable {
    let id = UUID()
    let item: Catalog.Item
    let start: Date
    let end: Date
    func contains(_ t: Date) -> Bool { t >= start && t < end }
}

enum ChannelScheduler {

    /// The broadcast day starts at 6:00 AM local and runs 24h. Tuning in before
    /// 6 AM still works — we just generate from the prior day's 6 AM anchor.
    static func dayAnchor(for now: Date, calendar: Calendar = .current) -> Date {
        let sixToday = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        return now < sixToday ? (calendar.date(byAdding: .day, value: -1, to: sixToday) ?? sixToday)
                              : sixToday
    }

    /// Default runtime when an item has none, by content type (seconds).
    private static func runtime(_ item: Catalog.Item) -> TimeInterval {
        if let s = item.runtimeSeconds, s > 120 { return TimeInterval(min(s, 3 * 3600)) }
        switch item.contentType {
        case "feature-film", "silent-film": return 90 * 60
        case "tv-special", "documentary":   return 50 * 60
        case "short-film", "animation", "newsreel", "ephemeral": return 12 * 60
        default: return 60 * 60
        }
    }

    /// Build the day's program timeline for a channel. `programs` is the channel's
    /// playable pool; it's deterministically ordered by the channel+date seed and
    /// packed from the day anchor, looping until it covers `coverUntil`.
    static func schedule(channelID: String,
                         programs: [Catalog.Item],
                         now: Date,
                         coverHours: Double = 26,
                         interProgramBuffer: TimeInterval = 120) -> [ScheduledProgram] {
        guard !programs.isEmpty else { return [] }
        let anchor = dayAnchor(for: now)
        let dayKey = Self.dayKey(anchor)
        var rng = SplitMix(seed: seed(channelID + dayKey))
        var ordered = programs
        ordered.shuffle(using: &rng)

        var slots: [ScheduledProgram] = []
        var cursor = anchor
        let coverUntil = now.addingTimeInterval(coverHours * 3600)
        var i = 0
        // Cap iterations so a pathologically short pool can't loop forever.
        let maxSlots = 2000
        while cursor < coverUntil && slots.count < maxSlots {
            let item = ordered[i % ordered.count]
            let end = cursor.addingTimeInterval(runtime(item))
            slots.append(ScheduledProgram(item: item, start: cursor, end: end))
            cursor = end.addingTimeInterval(interProgramBuffer)
            i += 1
        }
        return slots
    }

    /// The program airing at `t` (or the next upcoming one if `t` is in a buffer gap).
    static func program(in slots: [ScheduledProgram], at t: Date) -> ScheduledProgram? {
        slots.first { $0.contains(t) } ?? slots.first { $0.start >= t }
    }

    /// The lineup (items) to hand the player when tuning in at `t`: the current
    /// program first, then everything scheduled after it.
    static func lineup(from slots: [ScheduledProgram], at t: Date) -> [Catalog.Item] {
        guard let nowSlot = program(in: slots, at: t),
              let idx = slots.firstIndex(where: { $0.id == nowSlot.id }) else {
            return slots.map(\.item)
        }
        return slots[idx...].map(\.item)
    }

    // MARK: - Seed helpers

    private static func dayKey(_ d: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Stable FNV-1a hash → UInt64 seed (deterministic across launches/devices,
    /// unlike Swift's per-process Hashable).
    private static func seed(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }
}
