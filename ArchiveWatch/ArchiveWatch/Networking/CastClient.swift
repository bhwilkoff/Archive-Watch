import Foundation
import Network

// Google Cast sender — CASTV2 spoken directly, to the receiver the web and
// Android senders already use (`58AF34C3`, hosted at archivewatch.org/cast/).
//
// Why not Google's iOS Cast SDK: the project ships no third-party packages
// (Decision 127's reasoning), and the SDK is a closed binary. What a sender
// needs is small and fixed: a TLS socket to port 8009, a length-prefixed
// protobuf envelope with five fields, and JSON on four namespaces. The web
// sender (cast-sender.js) is the reference for WHAT is sent; this is how.
//
// The device certificate chains to Google's private Cast root, never a public
// CA, so ordinary validation always fails and every non-SDK sender accepts it.
// Nothing secret travels: the payload is the public URL of a public-domain film.

enum CastWire {
    static let connectionNS = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeatNS = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiverNS = "urn:x-cast:com.google.cast.receiver"
    static let mediaNS = "urn:x-cast:com.google.cast.media"
    static let platform = "receiver-0"

    struct Message: Equatable, Sendable {
        var source: String
        var destination: String
        var namespace: String
        var payload: String
    }

    /// One CastMessage, protobuf-encoded, behind its 4-byte big-endian length.
    static func frame(_ m: Message) -> Data {
        var body = Data([0x08, 0x00])            // protocol_version = CASTV2_1_0
        field(2, m.source, into: &body)
        field(3, m.destination, into: &body)
        field(4, m.namespace, into: &body)
        body.append(contentsOf: [0x28, 0x00])    // payload_type = STRING
        field(6, m.payload, into: &body)
        let n = UInt32(body.count)
        return Data([UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)]) + body
    }

    private static func field(_ number: UInt8, _ s: String, into d: inout Data) {
        let bytes = Data(s.utf8)
        d.append(number << 3 | 2)
        varint(UInt64(bytes.count), into: &d)
        d.append(bytes)
    }

    static func varint(_ value: UInt64, into d: inout Data) {
        var v = value
        while v >= 0x80 { d.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
        d.append(UInt8(v))
    }

    /// The body of one frame (length already stripped). Unknown fields are
    /// skipped; a malformed body is nil rather than a partial message.
    static func parse(_ body: Data) -> Message? {
        let b = [UInt8](body)
        var i = 0
        func readVarint() -> UInt64? {
            var r: UInt64 = 0, shift: UInt64 = 0
            while i < b.count {
                let byte = b[i]; i += 1
                r |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return r }
                shift += 7
                if shift > 63 { return nil }
            }
            return nil
        }
        var m = Message(source: "", destination: "", namespace: "", payload: "")
        while i < b.count {
            guard let key = readVarint() else { return nil }
            switch key & 7 {
            case 0:
                guard readVarint() != nil else { return nil }
            case 2:
                guard let len = readVarint(), len <= UInt64(b.count - i) else { return nil }
                let s = String(decoding: b[i..<i + Int(len)], as: UTF8.self)
                i += Int(len)
                switch key >> 3 {
                case 2: m.source = s
                case 3: m.destination = s
                case 4: m.namespace = s
                case 6: m.payload = s
                default: break
                }
            default:
                return nil
            }
        }
        return m
    }
}

/// What to put on the television.
struct CastMedia: Sendable {
    var url: URL
    var title: String
    var subtitle: String?
    var posterURL: URL?
    var subtitlesVTT: URL?
    var startAt: Double

    /// The LOAD request, field for field what cast-sender.js sends.
    func loadPayload(requestId: Int) -> [String: Any] {
        var metadata: [String: Any] = ["metadataType": 1, "title": title]
        if let subtitle { metadata["subtitle"] = subtitle }
        if let posterURL { metadata["images"] = [["url": posterURL.absoluteString]] }
        var media: [String: Any] = [
            "contentId": url.absoluteString,
            "contentType": "video/mp4",
            "streamType": "BUFFERED",
            "metadata": metadata,
        ]
        var body: [String: Any] = [
            "type": "LOAD", "requestId": requestId, "media": media,
            "currentTime": max(0, startAt.rounded(.down)), "autoplay": true,
        ]
        if let vtt = subtitlesVTT {
            media["tracks"] = [[
                "trackId": 1, "type": "TEXT", "trackContentId": vtt.absoluteString,
                "trackContentType": "text/vtt", "subtype": "SUBTITLES",
                "name": "English", "language": "en",
            ]]
            body["media"] = media
            body["activeTrackIds"] = [1]
        }
        return body
    }
}

/// One connection to one Cast device. All state lives on `queue`; events are
/// handed to `onEvent` from that queue, and the caller hops to its own actor.
final class CastClient: @unchecked Sendable {
    static let appID = "58AF34C3"
    static let senderID = "sender-0"

    struct MediaStatus: Sendable, Equatable {
        var playerState: String          // IDLE, PLAYING, PAUSED, BUFFERING
        var currentTime: Double
        var idleReason: String?          // FINISHED, CANCELLED, INTERRUPTED, ERROR
        var duration: Double?
    }

    enum Event: Sendable {
        case launched
        case media(MediaStatus)
        case volume(level: Double, muted: Bool)
        case failed(String)
        case closed
    }

    private let queue = DispatchQueue(label: "app.archivewatch.cast")
    private let onEvent: @Sendable (Event) -> Void
    private var connection: NWConnection?
    private var heartbeat: DispatchSourceTimer?
    private var requestId = 0
    private var transportId: String?
    private var sessionId: String?
    private var mediaSessionId: Int?
    private var pending: CastMedia?
    private var finished = false
    private var mutedByUs = false

    init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
    }

    /// Connect, launch our receiver, and load `media`. `muteReceiver` exists
    /// for test harnesses only — a test must never play a film aloud in
    /// somebody's room — and the app never passes it.
    func cast(_ media: CastMedia, to endpoint: NWEndpoint, muteReceiver: Bool = false) {
        queue.async { [self] in
            pending = media
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_verify_block(tls.securityProtocolOptions,
                                                  { _, _, complete in complete(true) }, queue)
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = 8
            let c = NWConnection(to: endpoint, using: NWParameters(tls: tls, tcp: tcp))
            connection = c
            c.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.send(CastWire.connectionNS, to: CastWire.platform, ["type": "CONNECT"])
                    self.startHeartbeat()
                    if muteReceiver {
                        self.mutedByUs = true
                        self.send(CastWire.receiverNS, to: CastWire.platform,
                                  ["type": "SET_VOLUME", "requestId": self.nextId(),
                                   "volume": ["muted": true]])
                    }
                    self.send(CastWire.receiverNS, to: CastWire.platform,
                              ["type": "LAUNCH", "appId": Self.appID, "requestId": self.nextId()])
                    self.readFrame()
                case .failed(let error):
                    self.fail("Couldn't reach the TV (\(error.localizedDescription)).")
                case .waiting(let error):
                    self.fail("Couldn't reach the TV (\(error.localizedDescription)).")
                default:
                    break
                }
            }
            c.start(queue: queue)
        }
    }

    func play() { mediaCommand("PLAY") }
    func pause() { mediaCommand("PAUSE") }

    func seek(to seconds: Double) {
        queue.async { [self] in
            guard let t = transportId, let m = mediaSessionId else { return }
            send(CastWire.mediaNS, to: t, ["type": "SEEK", "requestId": nextId(),
                                           "mediaSessionId": m, "currentTime": max(0, seconds)])
        }
    }

    /// The TV's own volume, 0...1.
    func setVolume(_ level: Double) {
        queue.async { [self] in
            send(CastWire.receiverNS, to: CastWire.platform,
                 ["type": "SET_VOLUME", "requestId": nextId(), "volume": ["level": min(1, max(0, level))]])
        }
    }

    /// Show or hide the film's subtitle track (track 1, when LOAD carried one).
    func setSubtitles(_ on: Bool) {
        queue.async { [self] in
            guard let t = transportId, let m = mediaSessionId else { return }
            send(CastWire.mediaNS, to: t, ["type": "EDIT_TRACKS_INFO", "requestId": nextId(),
                                           "mediaSessionId": m, "activeTrackIds": on ? [1] : []])
        }
    }

    /// Ask for a fresh MEDIA_STATUS (the receiver only volunteers one on a
    /// state change, so a position readout has to ask).
    func refresh() {
        queue.async { [self] in
            guard let t = transportId else { return }
            var body: [String: Any] = ["type": "GET_STATUS", "requestId": nextId()]
            if let m = mediaSessionId { body["mediaSessionId"] = m }
            send(CastWire.mediaNS, to: t, body)
        }
    }

    /// End the receiver app on the TV and drop the connection.
    func stop() {
        queue.async { [self] in
            if let s = sessionId {
                send(CastWire.receiverNS, to: CastWire.platform,
                     ["type": "STOP", "requestId": nextId(), "sessionId": s])
            }
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in close() }
        }
    }

    /// Leave the TV playing and drop only our connection.
    func disconnect() {
        queue.async { [self] in close() }
    }

    // MARK: - Queue-confined

    private func nextId() -> Int { requestId += 1; return requestId }

    private func mediaCommand(_ type: String) {
        queue.async { [self] in
            guard let t = transportId, let m = mediaSessionId else { return }
            send(CastWire.mediaNS, to: t, ["type": type, "requestId": nextId(), "mediaSessionId": m])
        }
    }

    private func send(_ namespace: String, to destination: String, _ body: [String: Any]) {
        guard let c = connection,
              let json = try? JSONSerialization.data(withJSONObject: body),
              let payload = String(data: json, encoding: .utf8) else { return }
        let m = CastWire.Message(source: Self.senderID, destination: destination,
                                 namespace: namespace, payload: payload)
        c.send(content: CastWire.frame(m), completion: .contentProcessed { _ in })
    }

    private func startHeartbeat() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 5, repeating: 5)
        t.setEventHandler { [weak self] in
            self?.send(CastWire.heartbeatNS, to: CastWire.platform, ["type": "PING"])
        }
        t.resume()
        heartbeat = t
    }

    private func readFrame() {
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] head, _, _, error in
            guard let self else { return }
            guard error == nil, let head, head.count == 4 else {
                if !self.finished { self.close() }
                return
            }
            let len = head.reduce(0) { $0 << 8 | Int($1) }
            guard len > 0, len < 1 << 20 else { self.fail("The TV sent something unreadable."); return }
            self.connection?.receive(minimumIncompleteLength: len, maximumLength: len) { body, _, _, error in
                guard error == nil, let body, let m = CastWire.parse(body) else {
                    if !self.finished { self.close() }
                    return
                }
                self.handle(m)
                self.readFrame()
            }
        }
    }

    private func handle(_ m: CastWire.Message) {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(m.payload.utf8))) as? [String: Any],
              let type = obj["type"] as? String else { return }
        switch (m.namespace, type) {
        case (CastWire.heartbeatNS, "PING"):
            send(CastWire.heartbeatNS, to: m.source, ["type": "PONG"])
        case (CastWire.connectionNS, "CLOSE"):
            close()
        case (CastWire.receiverNS, "RECEIVER_STATUS"):
            let status = obj["status"] as? [String: Any]
            if let v = status?["volume"] as? [String: Any], let level = v["level"] as? Double, !mutedByUs {
                onEvent(.volume(level: level, muted: v["muted"] as? Bool ?? false))
            }
            let apps = (status?["applications"] as? [[String: Any]]) ?? []
            guard let ours = apps.first(where: { $0["appId"] as? String == Self.appID }) else {
                // Our app was running and now is not: someone else took the TV.
                if transportId != nil { close() }
                return
            }
            guard transportId == nil, let t = ours["transportId"] as? String else { return }
            transportId = t
            sessionId = ours["sessionId"] as? String
            send(CastWire.connectionNS, to: t, ["type": "CONNECT"])
            onEvent(.launched)
            if let media = pending {
                pending = nil
                send(CastWire.mediaNS, to: t, media.loadPayload(requestId: nextId()))
            }
        case (CastWire.receiverNS, "LAUNCH_ERROR"):
            fail("The TV couldn't open Archive Watch.")
        case (CastWire.mediaNS, "MEDIA_STATUS"):
            guard let s = (obj["status"] as? [[String: Any]])?.first else { return }
            if let id = s["mediaSessionId"] as? Int { mediaSessionId = id }
            onEvent(.media(MediaStatus(playerState: s["playerState"] as? String ?? "IDLE",
                                       currentTime: s["currentTime"] as? Double ?? 0,
                                       idleReason: s["idleReason"] as? String,
                                       duration: (s["media"] as? [String: Any])?["duration"] as? Double)))
        case (CastWire.mediaNS, "LOAD_FAILED"), (CastWire.mediaNS, "LOAD_CANCELLED"),
             (CastWire.mediaNS, "INVALID_REQUEST"):
            fail("The TV couldn't play this film.")
        default:
            break
        }
    }

    /// A failure also ends the receiver session, so the television is not
    /// left on an error screen that nobody in the room asked for.
    private func fail(_ reason: String) {
        guard !finished else { return }
        onEvent(.failed(reason))
        if let s = sessionId {
            send(CastWire.receiverNS, to: CastWire.platform,
                 ["type": "STOP", "requestId": nextId(), "sessionId": s])
        }
        close()
    }

    private func close() {
        guard !finished else { return }
        finished = true
        heartbeat?.cancel(); heartbeat = nil
        if let t = transportId { send(CastWire.connectionNS, to: t, ["type": "CLOSE"]) }
        if mutedByUs {
            send(CastWire.receiverNS, to: CastWire.platform,
                 ["type": "SET_VOLUME", "requestId": nextId(), "volume": ["muted": false]])
        }
        // Cancel after the queued writes have gone, or the unmute is dropped.
        let c = connection
        connection = nil
        c?.send(content: nil, contentContext: .finalMessage, isComplete: true,
                completion: .contentProcessed { _ in c?.cancel() })
        onEvent(.closed)
    }
}
