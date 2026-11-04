#if DEBUG
import Foundation
import SwiftData

/// Launch doors for the device pass over iOS-DESIGN §4.3b. An Apple TV has no
/// keyboard a harness can reach, so a test list is made here; everything after
/// it is pressed on the remote. These run on the owner's own devices, so a run
/// never reaches their cloud and takes its own traces away again:
///
///   AW_NO_SYNC=1                 nothing leaves the device for this launch
///   AW_TEST_LIST=<name>|id,id    makes that list
///   AW_TEST_SWEEP=id,id          removes every "Play audit" list and those
///                                titles' watch history, and logs what is left
@MainActor
enum PlaylistTestDoor {
    nonisolated static var offline: Bool {
        ProcessInfo.processInfo.environment["AW_NO_SYNC"] == "1"
    }

    static func sweep(_ ctx: ModelContext) {
        guard let raw = ProcessInfo.processInfo.environment["AW_TEST_SWEEP"] else { return }
        let lists = ((try? ctx.fetch(FetchDescriptor<Playlist>())) ?? [])
            .filter { $0.name.hasPrefix("Play audit") }
        lists.forEach(ctx.delete)
        let ids = Set(raw.split(separator: ",").map(String.init))
        let history = ((try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? [])
            .filter { ids.contains($0.archiveID) }
        history.forEach(ctx.delete)
        try? ctx.save()
        let listsLeft = ((try? ctx.fetch(FetchDescriptor<Playlist>())) ?? [])
            .filter { $0.name.hasPrefix("Play audit") }.count
        let historyLeft = ((try? ctx.fetch(FetchDescriptor<WatchProgress>())) ?? [])
            .filter { ids.contains($0.archiveID) }.count
        awdiag("AWLIST sweep removedLists=%d removedHistory=%d listsLeft=%d historyLeft=%d",
               lists.count, history.count, listsLeft, historyLeft)
    }

    /// The list's id, for the caller to open.
    static func makeList(_ ctx: ModelContext) -> String? {
        guard let raw = ProcessInfo.processInfo.environment["AW_TEST_LIST"] else { return nil }
        let parts = raw.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].hasPrefix("Play audit") else { return nil }
        let all = (try? ctx.fetch(FetchDescriptor<Playlist>())) ?? []
        if let existing = all.first(where: { $0.name == parts[0] }) { return existing.id }
        let list = Playlist(name: parts[0], archiveIDs: parts[1].split(separator: ",").map(String.init))
        ctx.insert(list)
        try? ctx.save()
        awdiag("AWLIST made %@ titles=%d", list.name, list.archiveIDs.count)
        return list.id
    }
}
#endif
