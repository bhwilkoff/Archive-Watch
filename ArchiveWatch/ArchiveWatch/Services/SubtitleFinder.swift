import AVFoundation
import Foundation

// The "Get subtitles" action: everything the viewer can do when a film arrives
// with no captions, in one place, shared by tvOS, iOS and macOS.
//
// TWO SOURCES, DELIBERATELY NOT ONE LADDER THAT RUNS ITSELF.
//
// Looking a film up on OpenSubtitles is cheap, instant, and gives a HUMAN
// transcript — it is offered first and run on a tap. Transcribing on the device
// is the fallback, and it is a separate, explicitly-confirmed action because it
// is not cheap: AVFoundation refuses to read a remote asset for anything but
// playback (`AVAssetReader`: "Cannot initialize … with an asset at non-local
// URL"; `AVAssetExportSession`: -11838), so the film must be downloaded in full
// before a word can be transcribed. Spending a gigabyte of somebody's data plan
// is not a thing to do quietly on their behalf — the size is measured and shown
// before anything starts.
//
// Both sources converge on `SubtitleStore` + `LocalSubtitleHLSLoader`, so the
// player needs no knowledge of where a track came from.
@MainActor
@Observable
final class SubtitleFinder {

    enum Phase: Equatable {
        case idle
        case searching
        case sizing
        case downloading(Double)     // 0...1
        case transcribing
        case ready(String)           // what the viewer got, in words
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var task: Task<Void, Never>?
    private var downloadTask: URLSessionDownloadTask?

    var isBusy: Bool {
        switch phase {
        case .searching, .sizing, .downloading, .transcribing: return true
        default: return false
        }
    }

    /// Subtitles already on this device for the title.
    static func localHLS(for archiveID: String) -> URL? { SubtitleStore.cachedHLS(for: archiveID) }

    /// Whether to offer the action at all: only for a playable film that has no
    /// captions from the pipeline and none already fetched here.
    static func shouldOffer(for item: Catalog.Item) -> Bool {
        item.subtitleHLSURL == nil
            && localHLS(for: item.archiveID) == nil
            && item.videoURLParsed != nil
    }

    /// Can we even look this title up? OpenSubtitles matches on the IMDb id —
    /// never the title, which is how a subtitle for a different cut lands on a
    /// film (Decision 026's failure).
    static func canSearch(_ item: Catalog.Item) -> Bool {
        item.imdbID?.isEmpty == false && SubtitleAccount.isAvailable
    }

    static func canTranscribe(_ item: Catalog.Item) -> Bool {
        AutoCaptions.isSupported && !item.isSilent && item.videoURLParsed != nil
    }

    func cancel() {
        task?.cancel()
        downloadTask?.cancel()
        task = nil
        downloadTask = nil
        phase = .idle
    }

    func reset() { if !isBusy { phase = .idle } }

    // MARK: - Source 1: the viewer's OpenSubtitles account

    func search(_ item: Catalog.Item) {
        guard !isBusy else { return }
        guard let imdb = item.imdbID, !imdb.isEmpty else {
            phase = .failed("This title has no IMDb match, so there's nothing reliable to look up.")
            return
        }
        guard let video = item.videoURLParsed else {
            phase = .failed("This title has no playable video.")
            return
        }
        guard SubtitleAccount.shared.isConnected else {
            phase = .failed("Connect a free OpenSubtitles account in Settings to search for subtitles.")
            return
        }
        phase = .searching
        task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await SubtitleAccount.shared.fetchSubtitles(
                    imdbID: imdb, archiveID: item.archiveID,
                    videoURL: video, runtime: item.runtimeSeconds ?? 0)
                guard !Task.isCancelled else { return }
                self.phase = .ready("Subtitles added. Turn them on from the playback controls.")
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Source 2: transcribe on this device

    /// What transcribing would cost, measured rather than guessed, so the
    /// confirmation can state a real number.
    func measureDownload(_ item: Catalog.Item) async -> Int64? {
        guard let url = item.videoURLParsed else { return nil }
        phase = .sizing
        var r = URLRequest(url: url)
        r.httpMethod = "HEAD"
        defer { if case .sizing = phase { phase = .idle } }
        guard let (_, resp) = try? await URLSession.shared.data(for: r),
              let http = resp as? HTTPURLResponse,
              let len = http.value(forHTTPHeaderField: "Content-Length"),
              let bytes = Int64(len), bytes > 0 else { return nil }
        return bytes
    }

    func transcribe(_ item: Catalog.Item) {
        guard !isBusy else { return }
        guard let video = item.videoURLParsed else {
            phase = .failed("This title has no playable video."); return
        }
        guard AutoCaptions.isSupported else {
            phase = .failed(AutoCaptions.Failure.unsupported.errorDescription ?? ""); return
        }
        // Refusal, not detection: fabricating dialogue over a silent film is the
        // worst outcome available here, so it never starts (Decision 039b).
        guard !item.isSilent else {
            phase = .failed(AutoCaptions.Failure.silentFilm.errorDescription ?? ""); return
        }

        phase = .downloading(0)
        task = Task { [weak self] in
            guard let self else { return }
            var scratch: [URL] = []
            defer { for u in scratch { try? FileManager.default.removeItem(at: u) } }
            do {
                let local = try await self.download(video)
                scratch.append(local)
                guard !Task.isCancelled else { return }

                self.phase = .transcribing
                let audio = try await AutoCaptions.extractAudio(from: local)
                scratch.append(audio)
                // The film itself is only a means to the audio — drop the big
                // file the moment the few MB of audio exist.
                try? FileManager.default.removeItem(at: local)
                scratch.removeAll { $0 == local }
                guard !Task.isCancelled else { return }

                let runtime = Double(item.runtimeSeconds ?? 0)
                let seconds = runtime > 0 ? runtime
                    : CMTimeGetSeconds(try await AVURLAsset(url: audio).load(.duration))
                let vtt = try await AutoCaptions.transcribe(fileURL: audio, runtime: seconds,
                                                            isSilentFilm: item.isSilent)
                guard !Task.isCancelled else { return }

                guard SubtitleStore.store(vtt: vtt, for: item.archiveID, videoURL: video,
                                          runtime: Int(seconds),
                                          label: "English (auto-generated)") != nil else {
                    throw AutoCaptions.Failure.failed("Couldn't save the captions.")
                }
                self.phase = .ready("Automatic captions are ready. They're machine-made, "
                                    + "so expect mistakes — turn them on from the playback controls.")
            } catch {
                guard !Task.isCancelled else { return }
                self.phase = .failed((error as? LocalizedError)?.errorDescription
                                     ?? error.localizedDescription)
            }
        }
    }

    /// Download the film to Caches, reporting progress.
    private func download(_ url: URL) async throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-transcribe-\(UUID().uuidString).mp4")
        return try await withCheckedThrowingContinuation { cont in
            let t = URLSession.shared.downloadTask(with: url) { tmp, _, err in
                if let err { cont.resume(throwing: err); return }
                guard let tmp else {
                    cont.resume(throwing: URLError(.cannotOpenFile)); return
                }
                do {
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    cont.resume(returning: dest)
                } catch { cont.resume(throwing: error) }
            }
            self.downloadTask = t
            self.progressObservation = t.progress.observe(\.fractionCompleted) { p, _ in
                Task { @MainActor [weak self] in
                    guard let self, case .downloading = self.phase else { return }
                    self.phase = .downloading(p.fractionCompleted)
                }
            }
            t.resume()
        }
    }

    private var progressObservation: NSKeyValueObservation?
}
