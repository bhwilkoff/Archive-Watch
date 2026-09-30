#if os(macOS)
// §D39 — a YouTube watch-along scheduled ahead of time, in the Studio's Output
// column: Schedule… beside Go Live, the Upcoming list under it, and the
// go-live choice between a scheduled show and a new broadcast.
import SwiftUI

/// The scheduled shows, and the three platform writes that change them.
@MainActor
@Observable
final class StudioMacSchedule {
    static let shared = StudioMacSchedule()

    private(set) var shows: [StudioScheduledShow] = StudioSchedule.prune()
    /// One line after a write: a refused thumbnail, a failed cancel.
    var note: String?

    private init() {}

    /// On opening the Studio: drops shows more than 12 h past their start.
    func reload() { shows = StudioSchedule.prune() }

    func matching(_ archiveID: String?) -> [StudioScheduledShow] {
        guard let archiveID else { return [] }
        return StudioSchedule.matching(archiveID: archiveID, in: shows)
    }

    func forget(_ broadcastID: String) {
        StudioSchedule.remove(broadcastID: broadcastID)
        shows = StudioSchedule.load()
    }

    /// liveStreams.insert + liveBroadcasts.insert + bind + thumbnails.set —
    /// 200 units (Decision 136).
    func schedule(film: Catalog.Item, title: String, privacy: YouTubePrivacy,
                  start: Date, copy: String?) async throws {
        let renderer = StudioOverlayRenderer(size: CGSize(width: 1280, height: 720))
        let thumb = renderer.scheduledCardJPEG(
            film: film.title,
            detail: StudioRights.lowerThirdSubtitle(year: film.year, director: film.director))
        let description = StudioGoLive.description(for: film)
        let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
        let made = try await yt.schedule(title: title, description: description,
                                         privacy: privacy.rawValue, start: start,
                                         thumbnail: thumb)
        StudioSchedule.upsert(StudioScheduledShow(
            broadcastID: made.broadcastID, streamID: made.streamID,
            archiveID: film.archiveID, copy: copy, title: title,
            description: description, start: start, privacy: privacy.rawValue))
        shows = StudioSchedule.load()
        note = made.thumbnailRefusal.map {
            "Scheduled without the card as its thumbnail — \(studioSentence(raw: $0))"
        }
        awdiag("AWSCHED scheduled %@ film=%@ thumb=%@", made.broadcastID, film.archiveID,
               made.thumbnailRefusal == nil ? "set" : "refused")
    }

    /// liveBroadcasts.update — 50 units.
    func reschedule(_ show: StudioScheduledShow, title: String, start: Date) async throws {
        let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
        try await yt.reschedule(broadcastID: show.broadcastID, title: title,
                                description: show.description, start: start)
        var moved = show
        moved.title = title
        moved.start = start
        StudioSchedule.upsert(moved)
        shows = StudioSchedule.load()
        note = nil
    }

    /// liveBroadcasts.delete — 50 units. Deletes the public listing and its
    /// reminders; the caller has already asked.
    func cancel(_ show: StudioScheduledShow) async {
        do {
            let yt = YouTubeLive(token: try await StudioPlatformAuth.token(for: .youtube))
            try await yt.delete(broadcastID: show.broadcastID)
            forget(show.broadcastID)
            note = nil
        } catch StudioPlatformError.http(404, _) {
            // Already gone on YouTube: nothing left to cancel.
            forget(show.broadcastID)
        } catch {
            note = "Could not cancel — \(studioSentence(for: error))"
        }
    }
}

/// A new scheduled show, for the film in the Studio.
struct StudioScheduleSheet: View {
    let film: Catalog.Item
    let copy: String?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var privacy: YouTubePrivacy
    @State private var working = false
    @State private var problem: String?

    init(film: Catalog.Item, copy: String?, privacy: YouTubePrivacy) {
        self.film = film
        self.copy = copy
        _title = State(initialValue: film.title)
        _start = State(initialValue: StudioScheduleSheet.nextHour())
        _privacy = State(initialValue: privacy)
    }

    /// The top of the next hour at least an hour away — a round time, and far
    /// enough ahead that a reminder is worth sending.
    static func nextHour(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let later = now.addingTimeInterval(3600)
        return cal.nextDate(after: later, matching: DateComponents(minute: 0),
                            matchingPolicy: .nextTime) ?? later
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Schedule a Watch-Along").font(.headline)
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $start, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
                Picker("Privacy", selection: $privacy) {
                    ForEach(YouTubePrivacy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await submit() }
                } label: {
                    if working {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Scheduling…") }
                    } else {
                        Text("Schedule")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working || trimmed.isEmpty || start <= Date())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }

    private func submit() async {
        working = true
        problem = nil
        defer { working = false }
        do {
            try await StudioMacSchedule.shared.schedule(
                film: film, title: trimmed, privacy: privacy, start: start, copy: copy)
            dismiss()
        } catch {
            problem = "YouTube did not schedule it — \(studioSentence(for: error))"
        }
    }
}

/// Moving a scheduled show: its time and title.
struct StudioRescheduleSheet: View {
    let show: StudioScheduledShow
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var start: Date
    @State private var working = false
    @State private var problem: String?

    init(show: StudioScheduledShow) {
        self.show = show
        _title = State(initialValue: show.title)
        _start = State(initialValue: max(show.start, Date().addingTimeInterval(300)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reschedule").font(.headline)
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $start, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute])
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await submit() }
                } label: {
                    if working {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Saving…") }
                    } else {
                        Text("Save")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(working || trimmed.isEmpty || start <= Date())
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }

    private func submit() async {
        working = true
        problem = nil
        defer { working = false }
        do {
            try await StudioMacSchedule.shared.reschedule(show, title: trimmed, start: start)
            dismiss()
        } catch {
            problem = "YouTube did not move it — \(studioSentence(for: error))"
        }
    }
}

/// UPCOMING — every show this Mac scheduled, with Reschedule and Cancel.
struct StudioUpcomingList: View {
    private var schedule: StudioMacSchedule { StudioMacSchedule.shared }
    @State private var moving: StudioScheduledShow?
    @State private var cancelling: StudioScheduledShow?

    var body: some View {
        if !schedule.shows.isEmpty || schedule.note != nil {
            VStack(alignment: .leading, spacing: 6) {
                Text("Upcoming").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(schedule.shows) { show in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(show.title).font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(show.start.formatted(date: .abbreviated, time: .shortened)
                             + " \u{00B7} " + (YouTubePrivacy(rawValue: show.privacy)?.label ?? show.privacy))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Reschedule…") { moving = show }.fixedSize()
                            Button("Cancel Show…", role: .destructive) { cancelling = show }.fixedSize()
                        }
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                }
                if let note = schedule.note {
                    Text(note).font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheet(item: $moving) { StudioRescheduleSheet(show: $0) }
            .confirmationDialog("Cancel this scheduled show?",
                                isPresented: Binding(get: { cancelling != nil },
                                                     set: { if !$0 { cancelling = nil } }),
                                presenting: cancelling) { show in
                Button("Delete from YouTube", role: .destructive) {
                    Task { await schedule.cancel(show) }
                }
                Button("Keep It", role: .cancel) {}
            } message: { _ in
                Text("The listing and its reminders are deleted from YouTube.")
            }
        }
    }
}
#endif
