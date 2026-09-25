#if os(iOS)
import SwiftUI
import SwiftData
import Network
import dnssd

/// A Google Cast device found on this Wi-Fi network.
struct CastDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    init?(_ result: NWBrowser.Result) {
        guard case let .service(service, _, _, _) = result.endpoint else { return nil }
        var name = service
        if case let .bonjour(txt) = result.metadata, let fn = txt["fn"], !fn.isEmpty { name = fn }
        id = service
        self.name = name
        endpoint = result.endpoint
    }
}

/// The phone as a Cast remote (iOS-DESIGN §8.10). One cast at a time, owned
/// here rather than by a sheet, so closing the sheet leaves the TV playing.
@MainActor @Observable
final class CastController {
    static let shared = CastController()

    enum Phase: Equatable { case idle, connecting, casting, failed(String) }

    private(set) var devices: [CastDevice] = []
    private(set) var searching = false
    private(set) var localNetworkDenied = false
    private(set) var phase: Phase = .idle
    private(set) var deviceName = ""
    private(set) var archiveID: String?
    private(set) var playing = false
    private(set) var position: Double = 0
    private(set) var duration: Double?
    private(set) var volume: Double = 0.5
    private(set) var hasSubtitles = false
    private(set) var subtitlesOn = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var client: CastClient?
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var modelContext: ModelContext?

    func startSearching() {
        guard browser == nil else { return }
        DiagFile.log("AWCAST browse start")
        searching = true
        localNetworkDenied = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: "_googlecast._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                self?.devices = results.compactMap(CastDevice.init).sorted { $0.name < $1.name }
                DiagFile.log("AWCAST devices \(self?.devices.map(\.name) ?? [])")
            }
        }
        b.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                DiagFile.log("AWCAST browser \(state)")
                switch state {
                case .waiting(let error), .failed(let error):
                    if case let .dns(code) = error, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) {
                        self.localNetworkDenied = true
                    }
                    self.searching = false
                default:
                    break
                }
            }
        }
        b.start(queue: .main)
        browser = b
        // Bonjour never says "that is everyone", so the empty state waits a moment.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.searching = false
        }
    }

    func stopSearching() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    /// `mute` is for the DEBUG door only: a test never plays a film aloud in
    /// somebody's room. The product never passes it.
    func cast(_ item: Catalog.Item, to device: CastDevice, in ctx: ModelContext, mute: Bool = false) {
        guard let base = item.videoURLParsed else { return }
        let url = ArchiveVersions.preferredURL(for: item.archiveID, default: base)
        guard AirPlayRouting.isReceiverFetchable(url) else {
            phase = .failed("This copy can't be sent to a TV.")
            return
        }
        client?.disconnect()
        let id = item.archiveID
        let saved = (try? ctx.fetch(FetchDescriptor<WatchProgress>(
            predicate: #Predicate { $0.archiveID == id })))?.first?.positionSeconds ?? 0
        let media = CastMedia(url: url, title: item.title,
                              subtitle: item.year.map(String.init),
                              posterURL: item.posterURLParsed,
                              subtitlesVTT: item.publishedVTTURL,
                              startAt: saved > 10 ? saved : 0)
        DiagFile.log("AWCAST cast \(id) to=\(device.name) at=\(media.startAt)")
        modelContext = ctx
        archiveID = id
        deviceName = device.name
        position = media.startAt
        duration = nil
        hasSubtitles = media.subtitlesVTT != nil
        subtitlesOn = hasSubtitles
        playing = false
        phase = .connecting
        let c = CastClient { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        client = c
        c.cast(media, to: device.endpoint, muteReceiver: mute)
    }

    func togglePlay() { playing ? client?.pause() : client?.play() }
    func skip(_ seconds: Double) { seek(to: position + seconds) }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), duration ?? .greatestFiniteMagnitude)
        position = t
        client?.seek(to: t)
    }

    func setVolume(_ level: Double) {
        volume = level
        client?.setVolume(level)
    }

    func setSubtitles(_ on: Bool) {
        subtitlesOn = on
        client?.setSubtitles(on)
    }

    func stopCasting() {
        DiagFile.log("AWCAST stop pressed position=\(position)")
        recordProgress()
        client?.stop()
    }

    private func handle(_ event: CastClient.Event) {
        DiagFile.log("AWCAST event \(event)")
        switch event {
        case .launched:
            break
        case .media(let s):
            if s.playerState != "IDLE" {
                phase = .casting
                position = s.currentTime
                if let d = s.duration { duration = d }
            }
            playing = s.playerState == "PLAYING" || s.playerState == "BUFFERING"
            if s.playerState == "IDLE", s.idleReason == "FINISHED" {
                if let d = duration { position = d }
                recordProgress()
                client?.stop()
            }
            if poll == nil { startPolling() }
            if ticker == nil { startTicker() }
        case .volume(let level, _):
            volume = level
        case .failed(let reason):
            phase = .failed(reason)
        case .closed:
            recordProgress()
            poll?.cancel(); poll = nil
            ticker?.cancel(); ticker = nil
            client = nil
            if case .failed = phase {} else { phase = .idle }
            playing = false
        }
    }

    /// The receiver only volunteers a status on a state change; the position
    /// that becomes WatchProgress has to be asked for.
    private func startPolling() {
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                self?.client?.refresh()
            }
        }
    }

    /// Between statuses the scrubber runs on the phone's clock; every status
    /// from the receiver corrects it.
    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.playing else { continue }
                self.position = min(self.position + 1, self.duration ?? .greatestFiniteMagnitude)
            }
        }
    }

    private func recordProgress() {
        guard let ctx = modelContext, let id = archiveID, position > 10 else { return }
        WatchProgress.record(in: ctx, archiveID: id, position: position, duration: duration)
        SyncNudge.nudge(ctx)
    }
}

/// §3.6 form sheet: find a TV, send the film, then be its remote.
struct CastSheet: View {
    let item: Catalog.Item
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var cast = CastController.shared

    private var castingThis: Bool {
        cast.archiveID == item.archiveID && (cast.phase == .casting || cast.phase == .connecting)
    }

    var body: some View {
        NavigationStack {
            Group {
                if castingThis { remote } else { picker }
            }
            .navigationTitle(castingThis ? cast.deviceName : "Cast to a TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { DiagFile.log("AWCAST sheet appear"); cast.startSearching() }
        .onDisappear { DiagFile.log("AWCAST sheet disappear"); cast.stopSearching() }
        #if DEBUG
        // `AW_CAST=<part of a TV's name>`: cast to it, muted, once discovery
        // finds it — the product path from discovery on, with no tap.
        .onChange(of: cast.devices) { _, devices in
            guard let want = ProcessInfo.processInfo.environment["AW_CAST"], !want.isEmpty,
                  cast.phase == .idle,
                  let d = devices.first(where: { $0.name.localizedCaseInsensitiveContains(want) })
            else { return }
            cast.cast(item, to: d, in: ctx, mute: true)
            // `AW_CAST_STOP=<seconds>`: press Stop after that long.
            if let secs = ProcessInfo.processInfo.environment["AW_CAST_STOP"].flatMap(Double.init) {
                Task {
                    try? await Task.sleep(for: .seconds(secs))
                    cast.stopCasting()
                }
            }
        }
        #endif
    }

    @ViewBuilder private var picker: some View {
        if cast.localNetworkDenied {
            ContentUnavailableView {
                Label("Can't look for TVs", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Archive Watch isn't allowed to find devices on your local network.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        } else if cast.devices.isEmpty {
            if cast.searching {
                ProgressView("Looking for TVs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Cast devices on this Wi-Fi network.",
                                       systemImage: "tv.slash")
            }
        } else {
            List {
                if case let .failed(reason) = cast.phase, cast.archiveID == item.archiveID {
                    Text(reason).foregroundStyle(.red)
                }
                ForEach(cast.devices) { device in
                    Button {
                        cast.cast(item, to: device, in: ctx)
                    } label: {
                        Label(device.name, systemImage: "tv")
                    }
                }
            }
        }
    }

    @State private var scrubbing: Double?

    @ViewBuilder private var remote: some View {
        VStack(spacing: 22) {
            Text(item.title).font(.headline).multilineTextAlignment(.center)
            if cast.phase == .connecting {
                ProgressView()
            } else {
                if let total = cast.duration, total > 0 {
                    VStack(spacing: 4) {
                        Slider(value: Binding(get: { scrubbing ?? cast.position },
                                              set: { scrubbing = $0 }),
                               in: 0...total) { editing in
                            if !editing, let t = scrubbing { cast.seek(to: t); scrubbing = nil }
                        }
                        .accessibilityLabel("Position")
                        HStack {
                            Text(Self.clock(scrubbing ?? cast.position))
                            Spacer()
                            Text("-" + Self.clock(total - (scrubbing ?? cast.position)))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 44) {
                    Button { cast.skip(-30) } label: {
                        Image(systemName: "gobackward.30").font(.title)
                            .accessibilityLabel("Back 30 seconds")
                    }
                    Button { cast.togglePlay() } label: {
                        Image(systemName: cast.playing ? "pause.fill" : "play.fill").font(.largeTitle)
                            .accessibilityLabel(cast.playing ? "Pause" : "Play")
                    }
                    Button { cast.skip(30) } label: {
                        Image(systemName: "goforward.30").font(.title)
                            .accessibilityLabel("Forward 30 seconds")
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: Binding(get: { cast.volume }, set: { cast.setVolume($0) }), in: 0...1)
                        .accessibilityLabel("TV volume")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                if cast.hasSubtitles {
                    Toggle("Subtitles", isOn: Binding(get: { cast.subtitlesOn },
                                                      set: { cast.setSubtitles($0) }))
                }
            }
            Button(role: .destructive) { cast.stopCasting() } label: {
                Text("Stop casting")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}
#endif
