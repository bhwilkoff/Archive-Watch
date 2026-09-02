#if os(iOS) || os(macOS)
import Foundation
import SwiftData

// Keeps films on the device so they play with no network at all (Decision 099).
//
// WHY A BACKGROUND URLSession, and not AVAssetDownloadTask: Apple's asset
// downloader produces a `.movpkg` from an HLS playlist and does not accept a
// progressive MP4 at all — and every film here is a progressive MP4 on
// archive.org (Decision 021's whole subject). So the native path for this
// catalog is `URLSessionConfiguration.background`, which hands the transfer to
// `nsurlsessiond`: it keeps running while the app is suspended, and finishes
// even if the app is terminated, relaunching us in the background to be told.
// A 900 MB film over airport wifi outlives any foreground session.
//
// The session's delegate queue is `.main`, so every callback lands on the main
// thread and `MainActor.assumeIsolated` is sound — the alternative (a private
// serial queue plus hops) buys nothing here: the only heavy step is a rename.
//
// Task identity survives a relaunch through `taskDescription`, which the system
// restores with the task. Nothing else can be trusted across a process death —
// not an in-memory dictionary, and not a task identifier.
@MainActor
@Observable
final class DownloadManager {

    static let shared = DownloadManager()

    static let sessionIdentifier = "app.archivewatch.downloads"

    /// Live transfer figures, keyed by archiveID. The persisted counters on
    /// `DownloadedFilm` are what survive a relaunch; this is what moves a
    /// progress bar smoothly while the app is open.
    private(set) var progressByID: [String: Transfer] = [:]

    struct Transfer: Equatable, Sendable {
        var received: Int64
        var expected: Int64
        var fraction: Double { expected > 0 ? min(1, Double(received) / Double(expected)) : 0 }
    }

    /// Downloads only over wifi unless the viewer says otherwise. A feature
    /// film is hundreds of megabytes; spending someone's cellular plan on one
    /// without asking is not a default we get to pick for them.
    var allowsCellular: Bool = UserDefaults.standard.bool(forKey: "downloadOverCellular") {
        didSet { UserDefaults.standard.set(allowsCellular, forKey: "downloadOverCellular") }
    }

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private let shim = SessionShim()
    @ObservationIgnored private var lastPersist: [String: Date] = [:]
    @ObservationIgnored private var lastPublish: [String: Date] = [:]
    @ObservationIgnored private var backgroundEvents: CheckedContinuation<Void, Never>?

    @ObservationIgnored private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        // The viewer asked for this film by name and is watching a progress bar:
        // it is not discretionary work the system may defer to a good moment.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true      // per-REQUEST policy decides; see start()
        return URLSession(configuration: config, delegate: shim, delegateQueue: .main)
    }()

    private init() {}

    // MARK: - Lifecycle

    /// Called once at launch, before any UI reads a download. Re-attaches to
    /// transfers the system carried on without us and repairs rows whose file
    /// no longer matches what they claim.
    func configure(container: ModelContainer) {
        self.container = container
        _ = session                 // create it: this is what replays delegate callbacks
        Task { await reconcile() }
    }

    /// Rebuild in-memory state from what is actually true: the live tasks, and
    /// the files on disk. Both can have moved while the process was dead.
    private func reconcile() async {
        let tasks = await session.allTasks
        var live: Set<String> = []
        for task in tasks {
            guard let id = task.taskDescription else { continue }
            live.insert(id)
            if let dl = task as? URLSessionDownloadTask { indexTask(dl, for: id) }
            let expected = task.countOfBytesExpectedToReceive
            progressByID[id] = Transfer(received: task.countOfBytesReceived,
                                        expected: expected > 0 ? expected : 0)
        }
        guard let ctx = container?.mainContext,
              let rows = try? ctx.fetch(FetchDescriptor<DownloadedFilm>()) else { return }

        // ORPHAN SWEEP. A file whose row is gone (a reset store, a failed
        // migration, a removal that got half-way) is invisible in the UI and
        // counts against the viewer's storage forever — the one kind of leak
        // nobody can find and clear themselves.
        if let dir = OfflineLibrary.directory,
           let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            let known = Set(rows.map { OfflineLibrary.safeName($0.archiveID) })
            for name in names {
                let stem = (name as NSString).deletingPathExtension
                guard !known.contains(stem) else { continue }
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }

        for row in rows {
            let onDisk = OfflineLibrary.isDownloaded(row.archiveID)
            switch row.state {
            case .completed where !onDisk:
                // The file went away underneath the row (a restore onto a new
                // device, or a Mac user in Finder). Say so rather than offering
                // a Play button that dead-ends.
                row.state = .failed
                row.errorText = "The downloaded file is no longer on this device."
            case .queued, .downloading:
                // `where` on a multi-pattern case binds only to the LAST
                // pattern, so the liveness test is a statement, not a guard.
                guard !live.contains(row.archiveID) else { continue }
                // Nothing is transferring it. Resume data may exist from the
                // interruption; either way the viewer's move is to resume.
                if onDisk { row.state = .completed; row.completedAt = row.completedAt ?? Date() }
                else { row.state = .paused }
            default:
                if onDisk, row.state != .completed {
                    row.state = .completed
                    row.completedAt = row.completedAt ?? Date()
                }
            }
        }
        try? ctx.save()
    }

    /// The app was relaunched in the background because transfers finished.
    /// Hold until the session says it has delivered everything.
    func handleBackgroundEvents() async {
        _ = session
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            guard backgroundEvents == nil else { cont.resume(); return }
            backgroundEvents = cont
            // A session that never reports finished would hold the app in the
            // background until the watchdog kills it; 25s is well inside the
            // budget the system gives for this callback.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                self?.finishBackgroundEvents()
            }
        }
    }

    fileprivate func finishBackgroundEvents() {
        backgroundEvents?.resume()
        backgroundEvents = nil
    }

    // MARK: - Reads

    func progress(for archiveID: String) -> Transfer? { progressByID[archiveID] }

    func row(for archiveID: String) -> DownloadedFilm? {
        guard let ctx = container?.mainContext else { return nil }
        let d = FetchDescriptor<DownloadedFilm>(
            predicate: #Predicate<DownloadedFilm> { $0.archiveID == archiveID })
        return try? ctx.fetch(d).first
    }

    // MARK: - Commands

    /// Begin (or restart) a download. Returns a message to show the viewer when
    /// it could not start, nil on success.
    @discardableResult
    func start(item: Catalog.Item, version: ArchiveVersions.Version?) -> String? {
        guard let fallback = item.videoURLParsed else {
            return "This title has no downloadable video file."
        }
        let url = version?.url ?? ArchiveVersions.preferredURL(for: item.archiveID,
                                                              default: fallback)
        let expected = version?.sizeBytes ?? 0
        if expected > 0, !OfflineLibrary.hasRoom(for: expected) {
            let free = OfflineLibrary.availableBytes().map(OfflineLibrary.byteText) ?? "little"
            return "Not enough space — this copy needs \(OfflineLibrary.byteText(expected)) "
                 + "and \(free) is free."
        }
        guard let ctx = container?.mainContext else { return "Downloads are not ready yet." }

        // Starting over on a title that already has a partial transfer must not
        // leave the old bytes behind claiming space.
        cancelTask(for: item.archiveID)
        OfflineLibrary.removeFiles(for: item.archiveID)

        let row = self.row(for: item.archiveID) ?? {
            let r = DownloadedFilm(archiveID: item.archiveID, title: item.title,
                                   year: item.year, runtimeSeconds: item.runtimeSeconds,
                                   posterURLString: item.posterURL,
                                   remoteURLString: url.absoluteString,
                                   qualityLabel: version?.compactLabel,
                                   expectedBytes: expected)
            ctx.insert(r)
            return r
        }()
        row.remoteURLString = url.absoluteString
        row.qualityLabel = version?.compactLabel ?? row.qualityLabel
        row.expectedBytes = expected
        row.receivedBytes = 0
        row.errorText = nil
        row.hasSubtitles = false
        row.state = .queued
        try? ctx.save()

        resumeTask(archiveID: item.archiveID, url: url, resumeData: nil)
        progressByID[item.archiveID] = Transfer(received: 0, expected: expected)
        Task { await self.fetchCompanions(for: item) }
        return nil
    }

    /// Stop a transfer but keep the row, banking resume data so continuing does
    /// not re-download what is already here.
    func pause(_ archiveID: String) {
        guard let task = liveTask(for: archiveID) else { return }
        task.cancel(byProducingResumeData: { data in
            MainActor.assumeIsolated {
                if let data, let url = OfflineLibrary.resumeDataURL(for: archiveID) {
                    try? data.write(to: url, options: .atomic)
                }
                self.setState(.paused, for: archiveID)
            }
        })
    }

    func resume(_ archiveID: String) {
        guard let row = row(for: archiveID), let url = URL(string: row.remoteURLString) else { return }
        var resumeData: Data?
        if let ru = OfflineLibrary.resumeDataURL(for: archiveID) {
            resumeData = try? Data(contentsOf: ru)
            try? FileManager.default.removeItem(at: ru)
        }
        row.errorText = nil
        setState(.queued, for: archiveID)
        resumeTask(archiveID: archiveID, url: url, resumeData: resumeData)
    }

    /// Remove the title from Downloads entirely — files and row.
    ///
    /// A bare `ctx.delete` is correct here and nowhere else in this app:
    /// `DownloadedFilm` is device-local and never synced, so there is nothing
    /// for a tombstone to tell another device (iOS-DESIGN §9.7).
    func remove(_ archiveID: String) {
        cancelTask(for: archiveID)
        OfflineLibrary.removeFiles(for: archiveID)
        progressByID.removeValue(forKey: archiveID)
        guard let ctx = container?.mainContext, let row = row(for: archiveID) else { return }
        ctx.delete(row)
        try? ctx.save()
    }

    func removeAll() {
        // The FILES are what the viewer asked to reclaim, so they go first and
        // unconditionally. `container` is nil until `configure` runs, and the
        // old guard returned SILENTLY in that window — measured: an audit's
        // cleanup reported success while 67.5 MB stayed on disk, because it and
        // `configure` were sibling `.task`s with no ordering between them.
        if let dir = OfflineLibrary.directory,
           let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        progressByID.removeAll()
        guard let ctx = container?.mainContext,
              let rows = try? ctx.fetch(FetchDescriptor<DownloadedFilm>()) else { return }
        for row in rows { remove(row.archiveID) }
        try? ctx.save()
    }

    // MARK: - Task plumbing

    private func resumeTask(archiveID: String, url: URL, resumeData: Data?) {
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            var req = URLRequest(url: url)
            req.timeoutInterval = 60
            req.allowsCellularAccess = allowsCellular
            req.allowsExpensiveNetworkAccess = allowsCellular
            task = session.downloadTask(with: req)
        }
        task.taskDescription = archiveID
        indexTask(task, for: archiveID)
        task.resume()
    }

    private func liveTask(for archiveID: String) -> URLSessionDownloadTask? {
        // `allTasks` is async; the synchronous callers here (pause/cancel from a
        // button) need the task now, so keep a weak index alongside the session.
        taskIndex[archiveID]
    }

    @ObservationIgnored private var taskIndex: [String: URLSessionDownloadTask] = [:]

    fileprivate func indexTask(_ task: URLSessionDownloadTask, for archiveID: String) {
        taskIndex[archiveID] = task
    }

    private func cancelTask(for archiveID: String) {
        taskIndex[archiveID]?.cancel()
        taskIndex.removeValue(forKey: archiveID)
        if let ru = OfflineLibrary.resumeDataURL(for: archiveID) {
            try? FileManager.default.removeItem(at: ru)
        }
    }

    private func setState(_ state: DownloadState, for archiveID: String) {
        guard let ctx = container?.mainContext, let row = row(for: archiveID) else { return }
        row.state = state
        if state == .completed { row.completedAt = Date() }
        try? ctx.save()
    }

    // MARK: - Delegate handling (called on the main queue by SessionShim)

    fileprivate func handleProgress(archiveID: String, task: URLSessionDownloadTask,
                                    received: Int64, expected: Int64) {
        indexTask(task, for: archiveID)
        let known = expected > 0 ? expected : (progressByID[archiveID]?.expected ?? 0)
        let now = Date()
        // TWO throttles, because the callback arrives per CHUNK — hundreds a
        // second on a fast connection, all of it on the main queue.
        //
        // `progressByID` is observed by SwiftUI, so writing it every callback
        // would invalidate the Library list hundreds of times a second to move
        // a bar by a pixel. 4 Hz is smoother than the eye needs.
        if let last = lastPublish[archiveID], now.timeIntervalSince(last) < 0.25,
           received < known {
            return
        }
        lastPublish[archiveID] = now
        progressByID[archiveID] = Transfer(received: received, expected: known)
        // The persisted counters only have to be right across a relaunch, and a
        // SwiftData save is far more expensive again.
        if let last = lastPersist[archiveID], now.timeIntervalSince(last) < 2 { return }
        lastPersist[archiveID] = now
        guard let ctx = container?.mainContext, let row = row(for: archiveID) else { return }
        row.receivedBytes = received
        if known > 0 { row.expectedBytes = known }
        if row.state != .downloading { row.state = .downloading }
        try? ctx.save()
    }

    fileprivate func handleFinished(archiveID: String, movedTo url: URL?, error: String?) {
        taskIndex.removeValue(forKey: archiveID)
        lastPersist.removeValue(forKey: archiveID)
        lastPublish.removeValue(forKey: archiveID)
        guard let ctx = container?.mainContext, let row = row(for: archiveID) else { return }
        if url != nil {
            let size = OfflineLibrary.bytesUsed(by: archiveID)
            row.receivedBytes = size
            if row.expectedBytes == 0 { row.expectedBytes = size }
            row.state = .completed
            row.completedAt = Date()
            row.errorText = nil
            progressByID.removeValue(forKey: archiveID)
        } else {
            row.state = .failed
            row.errorText = error ?? "The download did not finish."
        }
        try? ctx.save()
    }

    fileprivate func handleError(archiveID: String, message: String?, hasResumeData: Bool) {
        taskIndex.removeValue(forKey: archiveID)
        guard let ctx = container?.mainContext, let row = row(for: archiveID) else { return }
        // A cancel produces an error too; a row already finished or deliberately
        // paused must not be overwritten with a failure.
        guard row.state.isActive else { return }
        if hasResumeData {
            row.state = .paused
            row.errorText = message
        } else {
            row.state = .failed
            row.errorText = message ?? "The download stopped."
        }
        try? ctx.save()
    }

    // MARK: - Companions (poster + subtitles)

    /// Fetch the small files that make a downloaded film usable with no
    /// network: its poster (so the Downloads list is not a wall of grey) and
    /// the published WebVTT (so its human subtitles come along).
    private func fetchCompanions(for item: Catalog.Item) async {
        if let poster = item.posterURLParsed, let dest = OfflineLibrary.posterWriteURL(for: item.archiveID) {
            _ = await Self.download(poster, to: dest, limit: 8_000_000)
        }
        if let vtt = item.publishedVTTURL, let dest = OfflineLibrary.subtitleWriteURL(for: item.archiveID) {
            if await Self.download(vtt, to: dest, limit: 4_000_000) {
                row(for: item.archiveID)?.hasSubtitles = true
                try? container?.mainContext.save()
            }
        }
    }

    /// Ordinary foreground fetch — these are kilobytes, not a film, and a
    /// missing poster must never fail the download it belongs to.
    private nonisolated static func download(_ url: URL, to dest: URL, limit: Int) async -> Bool {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode ?? 200 < 400,
              !data.isEmpty, data.count <= limit
        else { return false }
        return (try? data.write(to: dest, options: .atomic)) != nil
    }
}

// The session's delegate. Kept separate from the manager so the manager can be
// `@MainActor` (SwiftUI reads it directly) while these callbacks satisfy a
// non-isolated protocol. Every method here runs on the main queue, because the
// session was created with `delegateQueue: .main`.
private final class SessionShim: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        MainActor.assumeIsolated {
            DownloadManager.shared.handleProgress(archiveID: id, task: downloadTask,
                                                  received: totalBytesWritten,
                                                  expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // The temp file is deleted the moment this returns, so the move happens
        // HERE, synchronously — not after a hop onto another queue. It is a
        // rename within the container, so it costs nothing on the main thread.
        var moved: URL?
        var failure: String?
        if let status = (downloadTask.response as? HTTPURLResponse)?.statusCode, status >= 400 {
            failure = "archive.org answered \(status) for this copy."
        } else if let dest = OfflineLibrary.directory?
            .appendingPathComponent("\(OfflineLibrary.safeName(id)).mp4") {
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.moveItem(at: location, to: dest)
                moved = dest
            } catch {
                failure = "Could not save the film: \(error.localizedDescription)"
            }
        } else {
            failure = "No place to save downloads on this device."
        }
        MainActor.assumeIsolated {
            DownloadManager.shared.handleFinished(archiveID: id, movedTo: moved, error: failure)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, let error else { return }
        let ns = error as NSError
        let hasResume = ns.userInfo[NSURLSessionDownloadTaskResumeData] != nil
        if let data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
           let url = OfflineLibrary.resumeDataURL(for: id) {
            try? data.write(to: url, options: .atomic)
        }
        // A deliberate cancel is not a failure to report — and `pause` cancels
        // WITH resume data, so the presence of resume data cannot be part of
        // this test or every pause would land in the row as an error string.
        let cancelled = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
        MainActor.assumeIsolated {
            guard !cancelled else { return }
            DownloadManager.shared.handleError(archiveID: id,
                                               message: error.localizedDescription,
                                               hasResumeData: hasResume)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated { DownloadManager.shared.finishBackgroundEvents() }
    }
}
#endif
