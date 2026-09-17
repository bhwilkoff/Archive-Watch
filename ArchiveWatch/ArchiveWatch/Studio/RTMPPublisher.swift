// RTMP / RTMPS publisher — the transport under Watch Together Studio.
//
// YouTube and Twitch ingest RTMP from any encoder and nothing else from a
// general creator (docs/LIVE-RIFF-RESEARCH.md §1), so the device that renders
// the film speaks RTMP itself. This is the whole protocol we need, and no
// more: the C0/C1/C2 handshake, the chunk stream in both directions, the four
// AMF0 commands (connect, createStream, publish, and the server's _result /
// onStatus answers), the onMetaData data message, and FLV-shaped video
// (AVC sequence header + NALUs) and audio (AAC sequence header + raw frames)
// tags. Decision 127 records why this is ours rather than a dependency.
//
// Threading: one actor. The socket is an NWConnection on its own queue; every
// inbound byte is handed back into the actor, and every outbound message is
// serialised through it, so chunk interleaving and timestamps are consistent
// by construction. Encoded frames arrive as Sendable `EncodedVideoFrame`
// values, converted on the encoder callback thread — a CMSampleBuffer is
// not Sendable and never crosses into here.

import Foundation
import Network
import CoreMedia

// MARK: - Public surface

/// What a `publish` attempt can end as. A Bool cannot say WHY nothing
/// happened, and "nothing happened" is the one outcome a host must never be
/// left with (WATCH-TOGETHER §5).
public enum RTMPPublishError: Error, CustomStringConvertible, Sendable {
    case badURL(String)
    case connectFailed(String)
    case handshakeFailed(String)
    case rejected(code: String, description: String)
    case closed(String)
    case timeout(String)

    public var description: String {
        switch self {
        case .badURL(let s): return "bad destination: \(s)"
        case .connectFailed(let s): return "could not connect: \(s)"
        case .handshakeFailed(let s): return "handshake failed: \(s)"
        case .rejected(let c, let d): return "refused by the server: \(c) — \(d)"
        case .closed(let s): return "connection closed: \(s)"
        case .timeout(let s): return "timed out: \(s)"
        }
    }
}

/// The publisher's health, as the Studio shows it (WATCH-TOGETHER §4: a
/// health value is never hidden).
public struct RTMPHealth: Sendable, Equatable {
    public var state: State = .idle
    public var bytesSent: Int = 0
    public var videoFramesSent: Int = 0
    public var audioFramesSent: Int = 0
    public var videoFramesDropped: Int = 0
    public var queuedBytes: Int = 0
    public var lastError: String? = nil
    /// Bytes read from the socket, and the first inbound bytes as hex when
    /// `AW_RTMP_WIRE=1`. A connect that times out is either "the server said
    /// nothing" or "the server replied and we failed to parse it", and those
    /// need opposite fixes.
    public var bytesReceived: Int = 0
    public var wireHead: String = ""
    /// The server answered `connect` with NetConnection.Connect.Success. This
    /// is what separates "we never spoke RTMP properly" from "the server
    /// refused our key" — a socket close alone cannot tell the two apart, and
    /// a test that treats any close as success will pass on a broken
    /// handshake (it did, 2026-09-17).
    public var connectAcknowledged = false

    public enum State: String, Sendable { case idle, connecting, handshaking, connected, publishing, closed, failed }
}

/// Codec configuration the publisher needs before the first frame. Both
/// come straight from the encoders' format descriptions.
public struct RTMPStreamConfig: Sendable {
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var videoBitrate: Int
    /// AVCDecoderConfigurationRecord (the `avcC` atom body).
    public var avcC: Data
    public var audioSampleRate: Double
    public var audioChannels: Int
    public var audioBitrate: Int
    /// AudioSpecificConfig (2 bytes for AAC-LC).
    public var audioSpecificConfig: Data

    public init(width: Int, height: Int, frameRate: Double, videoBitrate: Int, avcC: Data,
                audioSampleRate: Double, audioChannels: Int, audioBitrate: Int, audioSpecificConfig: Data) {
        self.width = width; self.height = height; self.frameRate = frameRate; self.videoBitrate = videoBitrate
        self.avcC = avcC; self.audioSampleRate = audioSampleRate; self.audioChannels = audioChannels
        self.audioBitrate = audioBitrate; self.audioSpecificConfig = audioSpecificConfig
    }
}

public actor RTMPPublisher {

    public private(set) var health = RTMPHealth()

    // Back-pressure: bytes handed to the socket and not yet acknowledged as
    // sent. Past this, VIDEO inter-frames are dropped until a keyframe; audio
    // is never dropped (WATCH-TOGETHER §6.4 — viewers forgive a frame, not a
    // gap in the host's voice).
    public var maxQueuedBytes = 2_000_000

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "org.archivewatch.rtmp", qos: .userInitiated)
    private var inbound = Data()
    /// 128 is the protocol's default and the ONLY size a server assumes until
    /// we tell it otherwise. Raised to `negotiatedChunkSize` immediately after
    /// the Set Chunk Size message is sent — never before. Sending a >128-byte
    /// `connect` as one 4096-byte chunk made mediamtx report "received type 1
    /// chunk without previous chunk": it read 128 bytes, then looked for a
    /// chunk header and found the middle of our payload.
    private var outChunkSize = 128
    private let negotiatedChunkSize = 4096
    private var inChunkSize = 128
    private var windowAckSize = 2_500_000
    private var bytesReceived = 0
    private var lastAckAt = 0
    private var streamID: UInt32 = 0
    // 0 so the first `invoke` — always `connect` — is transaction 1.
    // THE PROTOCOL FIXES THIS NUMBER, and YouTube hardcodes it: measured
    // 2026-09-17, our connect went out as transaction 2 and YouTube's
    // `_result` came back as transaction 1.0, so nothing matched and the
    // connect timed out. mediamtx and Twitch echo whatever they are sent,
    // which is why the same bug passed on two servers out of three.
    private var transactionID = 0
    private var app = ""
    private var streamKey = ""
    private var tcURL = ""
    private var startTime: CMTime?
    private var config: RTMPStreamConfig?
    private var sentSequenceHeaders = false
    private var droppingUntilKeyframe = false
    private var pendingResults: [Int: CheckedContinuation<[AMF0Value], Error>] = [:]
    private var publishContinuation: CheckedContinuation<Void, Error>?
    private var closeReason: String?
    private var lastVideoTimestamp: UInt32 = 0
    private var lastAudioTimestamp: UInt32 = 0

    /// Partially received messages per chunk stream id.
    private var inflight: [UInt32: InboundMessage] = [:]

    public init() {}

    // MARK: Lifecycle

    /// Connects, handshakes, `connect`s, `createStream`s and `publish`es.
    /// Returns once the server answered `NetStream.Publish.Start`, which is
    /// the moment the stream key was accepted. `rtmp://host[:1935]/app/key`
    /// or `rtmps://host[:443]/app/key`; YouTube's `live2` and Twitch's `app`
    /// are both one path component before the key.
    public func publish(to url: URL, config: RTMPStreamConfig, timeout: TimeInterval = 15) async throws {
        // Convenience form: the LAST path component is the key, the rest is
        // the app. Prefer `publish(to:streamKey:config:)` — every platform
        // hands out an address and a key separately (YouTube's
        // `cdn.ingestionInfo.ingestionAddress` + `streamName`, Twitch's
        // ingest template + Get Stream Key), and YouTube's backup address
        // carries a QUERY (`/live2?backup=1`) that no combined URL can
        // express without ambiguity.
        var parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            throw RTMPPublishError.badURL("need /app/streamKey in \(url.absoluteString) — or use publish(to:streamKey:config:)")
        }
        let keyPart = parts.removeLast()
        var server = URLComponents()
        server.scheme = url.scheme
        server.host = url.host
        server.port = url.port
        server.path = "/" + parts.joined(separator: "/")
        server.query = url.query
        guard let serverURL = server.url else { throw RTMPPublishError.badURL(url.absoluteString) }
        try await publish(to: serverURL, streamKey: keyPart, config: config, timeout: timeout)
    }

    /// The real entry point: a server address (scheme, host, optional port,
    /// app path, optional query) and the stream key, exactly as a platform's
    /// API returns them.
    public func publish(to server: URL, streamKey key: String,
                        config: RTMPStreamConfig, timeout: TimeInterval = 15) async throws {
        guard let host = server.host, let scheme = server.scheme?.lowercased(),
              scheme == "rtmp" || scheme == "rtmps" else {
            throw RTMPPublishError.badURL(server.absoluteString)
        }
        var appPath = server.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !appPath.isEmpty else { throw RTMPPublishError.badURL("no app path in \(server.absoluteString)") }
        // YouTube's backup ingest is `/live2?backup=1`: the query belongs to
        // the APP, not to the key.
        if let q = server.query, !q.isEmpty { appPath += "?" + q }
        app = appPath
        streamKey = key
        let tls = scheme == "rtmps"
        let port = UInt16(server.port ?? (tls ? 443 : 1935))
        // tcUrl WITHOUT a default port. YouTube ignored a connect whose tcUrl
        // carried `:443`; ffmpeg omits the port when it is the default, and
        // that is what the servers are built against.
        let portSuffix = (server.port == nil) ? "" : ":\(port)"
        tcURL = "\(scheme)://\(host)\(portSuffix)/\(app)"
        self.config = config
        health = RTMPHealth(state: .connecting)

        let params: NWParameters = tls ? .tls : .tcp
        params.serviceClass = .interactiveVideo
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
        connection = conn

        try await withTimeout(timeout, label: "TCP connect") { [self] in
            try await self.waitReady(conn)
        }
        health.state = .handshaking
        try await withTimeout(timeout, label: "RTMP handshake") { [self] in
            try await self.handshake(conn)
        }
        startReceiving(conn)

        health.state = .connected
        // CONNECT FIRST, and with the full object. Measured 2026-09-17:
        // YouTube ignored a connect that carried only app/type/flashVer/tcUrl
        // and timed out (both RTMP and RTMPS), while Twitch accepted the same
        // one — so "it works on one platform" proves nothing about the other.
        // These are the fields ffmpeg sends, which is what the ingest servers
        // are built against. Chunk size is negotiated AFTER connect, which is
        // also ffmpeg's order.
        let connectResult = try await withTimeout(timeout, label: "connect") { [self] in
            try await self.invoke("connect", args: [.object([
                "app": .string(app),
                "type": .string("nonprivate"),
                "flashVer": .string("FMLE/3.0 (compatible; ArchiveWatch)"),
                "tcUrl": .string(tcURL),
                "fpad": .bool(false),
                "capabilities": .number(15),
                "audioCodecs": .number(4071),
                "videoCodecs": .number(252),
                "videoFunction": .number(1),
            ])], streamID: 0, chunkStreamID: 3)
        }
        if case .object(let info)? = connectResult.dropFirst().first,
           case .string(let code)? = info["code"] {
            if code != "NetConnection.Connect.Success" {
                let desc = (info["description"].flatMap { if case .string(let s) = $0 { return s } else { return nil } }) ?? ""
                throw fail(.rejected(code: code, description: desc))
            }
            health.connectAcknowledged = true
        } else {
            // A `_result` with no status object is still a result: the server
            // answered our connect, which is what this flag records.
            health.connectAcknowledged = true
        }

        // releaseStream + FCPublish: the FMLE preamble. YouTube and most CDNs
        // tolerate their absence, but some refuse `publish` without them, and
        // they cost two messages. No reply is awaited — FMLE does not either.
        sendCommand("releaseStream", transaction: 0, args: [.null, .string(streamKey)],
                    streamID: 0, chunkStreamID: 3)
        sendCommand("FCPublish", transaction: 0, args: [.null, .string(streamKey)],
                    streamID: 0, chunkStreamID: 3)

        let streamResult = try await withTimeout(timeout, label: "createStream") { [self] in
            try await self.invoke("createStream", args: [.null], streamID: 0, chunkStreamID: 3)
        }
        guard case .number(let sid)? = streamResult.last else {
            throw fail(.handshakeFailed("createStream returned no stream id"))
        }
        streamID = UInt32(sid)

        // Now that the connection is established, ask for bigger chunks and
        // declare our acknowledgement window. The Set Chunk Size message is
        // itself sent at the OLD size, and only then does ours change.
        send(message: .protocolControl(type: 1, payload: be32(UInt32(negotiatedChunkSize))))
        outChunkSize = negotiatedChunkSize
        send(message: .protocolControl(type: 5, payload: be32(UInt32(windowAckSize))))

        // publish has no _result; the answer is an onStatus on the stream.
        try await withTimeout(timeout, label: "publish") { [self] in try await self.awaitPublishStart() }
        health.state = .publishing
        sendMetadata(config)
    }

    /// Sends the `publish` command and suspends until the server answers
    /// `NetStream.Publish.Start` (or refuses). Its own actor method so the
    /// continuation closure is actor-isolated rather than escaping through the
    /// `@Sendable` timeout wrapper.
    private func awaitPublishStart() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            publishContinuation = c
            sendCommand("publish", transaction: 0,
                        args: [.null, .string(streamKey), .string("live")],
                        streamID: streamID, chunkStreamID: 8)
        }
    }

    /// Ends the stream politely (FCUnpublish/deleteStream are courtesies the
    /// big two ignore; closing the socket is what ends the broadcast).
    public func close() {
        if let sid = Optional(streamID), sid != 0 {
            sendCommand("deleteStream", transaction: 0, args: [.null, .number(Double(sid))], streamID: 0, chunkStreamID: 3)
        }
        connection?.cancel()
        connection = nil
        if health.state != .failed { health.state = .closed }
        failPending(RTMPPublishError.closed("closed by the app"))
    }

    // MARK: Media in

    /// One encoded H.264 frame. The caller converts the `CMSampleBuffer` on
    /// the encoder's own callback thread (`EncodedVideoFrame.init`), because a
    /// `CMSampleBuffer` is not `Sendable` and must not cross into this actor —
    /// and the conversion is a memcpy we were doing anyway.
    public func send(video frame: EncodedVideoFrame) {
        guard health.state == .publishing, let config else { return }
        if health.queuedBytes > maxQueuedBytes && !frame.isKeyframe {
            droppingUntilKeyframe = true
        }
        if droppingUntilKeyframe {
            if frame.isKeyframe { droppingUntilKeyframe = false } else { health.videoFramesDropped += 1; return }
        }
        if !sentSequenceHeaders {
            sendSequenceHeaders(config)
        }
        let ts = timestampMS(frame.decodeTime)
        let cts = max(0, Int32((CMTimeGetSeconds(frame.presentationTime) - CMTimeGetSeconds(frame.decodeTime)) * 1000))
        var tag = Data(capacity: frame.avccData.count + 5)
        tag.append(UInt8((frame.isKeyframe ? 1 : 2) << 4 | 7))
        tag.append(1)                                     // AVC NALU
        tag.append(contentsOf: be24(UInt32(cts)))
        tag.append(frame.avccData)
        lastVideoTimestamp = ts
        send(message: .media(type: 9, timestamp: ts, streamID: streamID, chunkStreamID: 6, payload: tag))
        health.videoFramesSent += 1
    }

    /// One AAC frame (raw, no ADTS) with its presentation time.
    public func send(audioFrame: Data, presentationTime: CMTime) {
        guard health.state == .publishing, let config else { return }
        if !sentSequenceHeaders { sendSequenceHeaders(config) }
        let ts = timestampMS(presentationTime)
        var tag = Data(capacity: audioFrame.count + 2)
        tag.append(0xAF)                                  // AAC, 44kHz flag (informational for AAC), 16-bit, stereo
        tag.append(1)                                     // raw frame
        tag.append(audioFrame)
        lastAudioTimestamp = ts
        send(message: .media(type: 8, timestamp: ts, streamID: streamID, chunkStreamID: 4, payload: tag))
        health.audioFramesSent += 1
    }

    // MARK: - Handshake

    private func waitReady(_ conn: NWConnection) async throws {
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { c.resume() }
                case .failed(let e):
                    if once.claim() { c.resume(throwing: RTMPPublishError.connectFailed(e.localizedDescription)) }
                case .waiting(let e):
                    // "waiting" is DNS/route trouble that may never resolve;
                    // report it rather than hanging the go-live sheet.
                    if once.claim() { c.resume(throwing: RTMPPublishError.connectFailed(e.localizedDescription)) }
                case .cancelled:
                    if once.claim() { c.resume(throwing: RTMPPublishError.closed("cancelled")) }
                default: break
                }
            }
            conn.start(queue: queue)
        }
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let e): Task { await self.socketClosed("failed: \(e.localizedDescription)") }
            case .cancelled: Task { await self.socketClosed("cancelled") }
            default: break
            }
        }
    }

    private func handshake(_ conn: NWConnection) async throws {
        var c0c1 = Data([0x03])
        var c1 = Data(count: 1536)
        c1.replaceSubrange(0..<4, with: be32(UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))))
        for i in 8..<1536 { c1[i] = UInt8.random(in: 0...255) }
        c0c1.append(c1)
        try await sendRaw(conn, c0c1)
        let s0s1s2 = try await receiveExactly(conn, 1 + 1536 + 1536)
        guard s0s1s2[s0s1s2.startIndex] == 0x03 else {
            throw RTMPPublishError.handshakeFailed("server version \(s0s1s2[s0s1s2.startIndex])")
        }
        // C2 echoes S1.
        let s1 = s0s1s2.subdata(in: (s0s1s2.startIndex + 1)..<(s0s1s2.startIndex + 1 + 1536))
        try await sendRaw(conn, s1)
    }

    private func sendRaw(_ conn: NWConnection, _ data: Data) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { e in
                if let e { c.resume(throwing: RTMPPublishError.connectFailed(e.localizedDescription)) } else { c.resume() }
            })
        }
    }

    private func receiveExactly(_ conn: NWConnection, _ n: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: n, maximumLength: n) { data, _, _, e in
                if let e { c.resume(throwing: RTMPPublishError.handshakeFailed(e.localizedDescription)) }
                else if let data, data.count == n { c.resume(returning: data) }
                else { c.resume(throwing: RTMPPublishError.handshakeFailed("short read (\(data?.count ?? 0) of \(n))")) }
            }
        }
    }

    // MARK: - Inbound

    private func startReceiving(_ conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty { await self.ingest(data) }
                if let error { await self.socketClosed(error.localizedDescription); return }
                if isComplete { await self.socketClosed("server closed the connection"); return }
                await self.startReceiving(conn)
            }
        }
    }

    private func socketClosed(_ reason: String) {
        guard health.state != .closed, health.state != .failed else { return }
        health.state = health.state == .publishing ? .closed : .failed
        health.lastError = reason
        closeReason = reason
        failPending(RTMPPublishError.closed(reason))
    }

    private func failPending(_ error: Error) {
        for (_, c) in pendingResults { c.resume(throwing: error) }
        pendingResults.removeAll()
        publishContinuation?.resume(throwing: error)
        publishContinuation = nil
    }

    private static let wireDiag = ProcessInfo.processInfo.environment["AW_RTMP_WIRE"] == "1"

    private func ingest(_ data: Data) {
        inbound.append(data)
        bytesReceived += data.count
        health.bytesReceived = bytesReceived
        if Self.wireDiag && health.wireHead.count < 512 {
            health.wireHead += data.prefix(96).map { String(format: "%02x", $0) }.joined()
        }
        if bytesReceived - lastAckAt >= windowAckSize {
            lastAckAt = bytesReceived
            send(message: .protocolControl(type: 3, payload: be32(UInt32(truncatingIfNeeded: bytesReceived))))
        }
        while let consumed = parseChunk() { inbound.removeFirst(consumed) }
    }

    private struct InboundMessage {
        var timestamp: UInt32 = 0
        var length: Int = 0
        var type: UInt8 = 0
        var streamID: UInt32 = 0
        var payload = Data()
    }

    /// Parses one chunk from `inbound`; returns bytes consumed, or nil when
    /// more data is needed. Handles fmt 0–3 headers and extended timestamps.
    private func parseChunk() -> Int? {
        guard inbound.count >= 1 else { return nil }
        var i = inbound.startIndex
        let b0 = inbound[i]; i += 1
        let fmt = b0 >> 6
        var csid = UInt32(b0 & 0x3F)
        if csid == 0 { guard inbound.count >= 2 else { return nil }; csid = UInt32(inbound[i]) + 64; i += 1 }
        else if csid == 1 { guard inbound.count >= 3 else { return nil }; csid = UInt32(inbound[i]) + UInt32(inbound[i + 1]) << 8 + 64; i += 2 }
        let headerLen = [11, 7, 3, 0][Int(fmt)]
        guard inbound.endIndex - i >= headerLen else { return nil }
        var msg = inflight[csid] ?? InboundMessage()
        var ts: UInt32 = 0
        if fmt <= 2 {
            ts = UInt32(inbound[i]) << 16 | UInt32(inbound[i + 1]) << 8 | UInt32(inbound[i + 2]); i += 3
        }
        if fmt <= 1 {
            msg.length = Int(inbound[i]) << 16 | Int(inbound[i + 1]) << 8 | Int(inbound[i + 2]); i += 3
            msg.type = inbound[i]; i += 1
            msg.payload.removeAll(keepingCapacity: true)
        }
        if fmt == 0 {
            msg.streamID = UInt32(inbound[i]) | UInt32(inbound[i + 1]) << 8 | UInt32(inbound[i + 2]) << 16 | UInt32(inbound[i + 3]) << 24; i += 4
        }
        if fmt <= 2 && ts == 0xFFFFFF {
            guard inbound.endIndex - i >= 4 else { return nil }
            ts = UInt32(inbound[i]) << 24 | UInt32(inbound[i + 1]) << 16 | UInt32(inbound[i + 2]) << 8 | UInt32(inbound[i + 3]); i += 4
        }
        if fmt == 0 { msg.timestamp = ts } else if fmt <= 2 { msg.timestamp &+= ts }
        let remaining = msg.length - msg.payload.count
        let take = min(remaining, inChunkSize)
        guard inbound.endIndex - i >= take else { return nil }
        msg.payload.append(inbound[i..<(i + take)]); i += take
        if msg.payload.count >= msg.length {
            handle(msg)
            msg.payload.removeAll(keepingCapacity: true)
        }
        inflight[csid] = msg
        return i - inbound.startIndex
    }

    private func handle(_ m: InboundMessage) {
        if Self.wireDiag {
            health.wireHead += " [t\(m.type)/\(m.length)]"
        }
        switch m.type {
        case 1:  // Set Chunk Size
            if m.payload.count >= 4 { inChunkSize = Int(readBE32(m.payload, 0) & 0x7FFF_FFFF) }
        case 3:  // Acknowledgement — informational
            break
        case 4:  // User Control: 6 = PingRequest → 7 = PingResponse
            if m.payload.count >= 6, readBE16(m.payload, 0) == 6 {
                var p = Data([0, 7]); p.append(m.payload.subdata(in: 2..<6))
                send(message: .protocolControl(type: 4, payload: p))
            }
        case 5:  // Window Acknowledgement Size
            if m.payload.count >= 4 { windowAckSize = Int(readBE32(m.payload, 0)) }
        case 6:  // Set Peer Bandwidth → answer with our window
            send(message: .protocolControl(type: 5, payload: be32(UInt32(windowAckSize))))
        case 20: // AMF0 command
            let values = AMF0.decodeAll(m.payload)
            guard case .string(let name)? = values.first else { return }
            switch name {
            case "_result", "_error":
                guard values.count >= 2, case .number(let tid) = values[1] else { return }
                // Exact match first. If a server answers with a transaction id
                // we never sent — and they do, for `connect` — resolve the one
                // outstanding request rather than hanging. Only when there is
                // exactly ONE, so a reply can never be misrouted.
                var c = pendingResults.removeValue(forKey: Int(tid))
                if c == nil, pendingResults.count == 1, let only = pendingResults.keys.first {
                    c = pendingResults.removeValue(forKey: only)
                }
                guard let c else { return }
                if name == "_error" {
                    let (code, desc) = statusOf(values)
                    c.resume(throwing: fail(.rejected(code: code, description: desc)))
                } else {
                    c.resume(returning: Array(values.dropFirst(2)))
                }
            case "onStatus":
                let (code, desc) = statusOf(values)
                if code == "NetStream.Publish.Start" {
                    publishContinuation?.resume(); publishContinuation = nil
                } else if code.hasPrefix("NetStream.Publish") || code.hasPrefix("NetConnection") || code.hasSuffix("Failed") || code.hasSuffix("BadName") {
                    let e = fail(.rejected(code: code, description: desc))
                    publishContinuation?.resume(throwing: e); publishContinuation = nil
                }
            default:
                break
            }
        default:
            break
        }
    }

    private func statusOf(_ values: [AMF0Value]) -> (String, String) {
        for v in values {
            if case .object(let o) = v {
                let code = o["code"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                let desc = o["description"].flatMap { if case .string(let s) = $0 { return s } else { return nil } } ?? ""
                if !code.isEmpty { return (code, desc) }
            }
        }
        return ("", "")
    }

    @discardableResult
    private func fail(_ e: RTMPPublishError) -> RTMPPublishError {
        health.state = .failed
        health.lastError = e.description
        return e
    }

    // MARK: - Outbound

    private enum Outbound {
        case protocolControl(type: UInt8, payload: Data)
        case command(chunkStreamID: UInt32, streamID: UInt32, payload: Data)
        case data(chunkStreamID: UInt32, streamID: UInt32, payload: Data)
        case media(type: UInt8, timestamp: UInt32, streamID: UInt32, chunkStreamID: UInt32, payload: Data)
    }

    private func invoke(_ command: String, args: [AMF0Value], streamID: UInt32, chunkStreamID: UInt32) async throws -> [AMF0Value] {
        transactionID += 1
        let tid = transactionID
        return try await withCheckedThrowingContinuation { c in
            pendingResults[tid] = c
            sendCommand(command, transaction: tid, args: args, streamID: streamID, chunkStreamID: chunkStreamID)
        }
    }

    private func sendCommand(_ command: String, transaction: Int, args: [AMF0Value], streamID: UInt32, chunkStreamID: UInt32) {
        var payload = AMF0.encode(.string(command))
        payload.append(AMF0.encode(.number(Double(transaction))))
        for a in args { payload.append(AMF0.encode(a)) }
        send(message: .command(chunkStreamID: chunkStreamID, streamID: streamID, payload: payload))
    }

    private func sendMetadata(_ c: RTMPStreamConfig) {
        var payload = AMF0.encode(.string("@setDataFrame"))
        payload.append(AMF0.encode(.string("onMetaData")))
        payload.append(AMF0.encode(.ecmaArray([
            "width": .number(Double(c.width)), "height": .number(Double(c.height)),
            "framerate": .number(c.frameRate), "videocodecid": .number(7),
            "videodatarate": .number(Double(c.videoBitrate) / 1000),
            "audiocodecid": .number(10), "audiosamplerate": .number(c.audioSampleRate),
            "audiodatarate": .number(Double(c.audioBitrate) / 1000),
            "audiochannels": .number(Double(c.audioChannels)), "stereo": .bool(c.audioChannels == 2),
            "encoder": .string("Archive Watch Studio"),
        ])))
        send(message: .data(chunkStreamID: 6, streamID: streamID, payload: payload))
    }

    private func sendSequenceHeaders(_ c: RTMPStreamConfig) {
        sentSequenceHeaders = true
        var v = Data([0x17, 0x00, 0x00, 0x00, 0x00]); v.append(c.avcC)
        send(message: .media(type: 9, timestamp: 0, streamID: streamID, chunkStreamID: 6, payload: v))
        var a = Data([0xAF, 0x00]); a.append(c.audioSpecificConfig)
        send(message: .media(type: 8, timestamp: 0, streamID: streamID, chunkStreamID: 4, payload: a))
    }

    private func send(message: Outbound) {
        guard let connection else { return }
        let bytes: Data
        switch message {
        case .protocolControl(let type, let payload):
            bytes = chunks(csid: 2, timestamp: 0, type: type, streamID: 0, payload: payload)
        case .command(let csid, let sid, let payload):
            bytes = chunks(csid: csid, timestamp: 0, type: 20, streamID: sid, payload: payload)
        case .data(let csid, let sid, let payload):
            bytes = chunks(csid: csid, timestamp: 0, type: 18, streamID: sid, payload: payload)
        case .media(let type, let ts, let sid, let csid, let payload):
            bytes = chunks(csid: csid, timestamp: ts, type: type, streamID: sid, payload: payload)
        }
        health.queuedBytes += bytes.count
        let n = bytes.count
        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            Task { await self.sent(n, error: error) }
        })
    }

    private func sent(_ n: Int, error: NWError?) {
        health.queuedBytes -= n
        health.bytesSent += n
        if let error { socketClosed(error.localizedDescription) }
    }

    /// Splits one message into chunks: a fmt-0 header on the first chunk,
    /// fmt-3 continuation headers on the rest. Absolute timestamps
    /// everywhere, so a dropped video frame never desynchronises the stream.
    private func chunks(csid: UInt32, timestamp: UInt32, type: UInt8, streamID: UInt32, payload: Data) -> Data {
        var out = Data(capacity: payload.count + 16 + payload.count / outChunkSize + 1)
        let extended = timestamp >= 0xFFFFFF
        out.append(basicHeader(fmt: 0, csid: csid))
        out.append(contentsOf: be24(extended ? 0xFFFFFF : timestamp))
        out.append(contentsOf: be24(UInt32(payload.count)))
        out.append(type)
        out.append(contentsOf: [UInt8(streamID & 0xFF), UInt8(streamID >> 8 & 0xFF), UInt8(streamID >> 16 & 0xFF), UInt8(streamID >> 24 & 0xFF)])
        if extended { out.append(contentsOf: be32(timestamp)) }
        var offset = payload.startIndex
        var first = true
        while offset < payload.endIndex {
            if !first {
                out.append(basicHeader(fmt: 3, csid: csid))
                if extended { out.append(contentsOf: be32(timestamp)) }
            }
            let end = min(offset + outChunkSize, payload.endIndex)
            out.append(payload[offset..<end])
            offset = end
            first = false
        }
        return out
    }

    private func basicHeader(fmt: UInt8, csid: UInt32) -> Data {
        if csid < 64 { return Data([fmt << 6 | UInt8(csid)]) }
        if csid < 320 { return Data([fmt << 6, UInt8(csid - 64)]) }
        return Data([fmt << 6 | 1, UInt8((csid - 64) & 0xFF), UInt8((csid - 64) >> 8)])
    }

    private func timestampMS(_ t: CMTime) -> UInt32 {
        if startTime == nil { startTime = t }
        let ms = (CMTimeGetSeconds(t) - CMTimeGetSeconds(startTime!)) * 1000
        return UInt32(max(0, ms.rounded()))
    }

    // MARK: - Timeout

    private func withTimeout<T: Sendable>(_ seconds: TimeInterval, label: String, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw RTMPPublishError.timeout(label)
            }
            let r = try await group.next()!
            group.cancelAll()
            return r
        }
    }
}

/// A resume-once guard for a continuation driven by a `@Sendable` callback
/// (NWConnection's state handler). Swift 6 forbids mutating a captured `var`
/// from concurrently-executing code, so the flag lives behind a lock.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
}

// MARK: - Byte helpers

@inline(__always) private func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
@inline(__always) private func be24(_ v: UInt32) -> [UInt8] { [UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
@inline(__always) private func be32(_ v: UInt32) -> Data { Data([UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]) }
@inline(__always) private func readBE16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) << 8 | UInt16(d[d.startIndex + o + 1]) }
@inline(__always) private func readBE32(_ d: Data, _ o: Int) -> UInt32 {
    UInt32(d[d.startIndex + o]) << 24 | UInt32(d[d.startIndex + o + 1]) << 16 | UInt32(d[d.startIndex + o + 2]) << 8 | UInt32(d[d.startIndex + o + 3])
}

// MARK: - AMF0

/// The subset of AMF0 the RTMP command channel uses.
public indirect enum AMF0Value: Sendable, Equatable {
    case number(Double)
    case bool(Bool)
    case string(String)
    case object([String: AMF0Value])
    case null
    case undefined
    case ecmaArray([String: AMF0Value])
    case strictArray([AMF0Value])
}

enum AMF0 {
    static func encode(_ v: AMF0Value) -> Data {
        var d = Data()
        write(v, into: &d)
        return d
    }

    private static func write(_ v: AMF0Value, into d: inout Data) {
        switch v {
        case .number(let n):
            d.append(0x00); d.append(contentsOf: withUnsafeBytes(of: n.bitPattern.bigEndian) { Array($0) })
        case .bool(let b):
            d.append(0x01); d.append(b ? 1 : 0)
        case .string(let s):
            let u = Array(s.utf8)
            if u.count < 65536 { d.append(0x02); d.append(contentsOf: be16(UInt16(u.count))) }
            else { d.append(0x0C); d.append(be32(UInt32(u.count))) }
            d.append(contentsOf: u)
        case .object(let o):
            d.append(0x03); writeProperties(o, into: &d)
        case .null:
            d.append(0x05)
        case .undefined:
            d.append(0x06)
        case .ecmaArray(let o):
            d.append(0x08); d.append(be32(UInt32(o.count))); writeProperties(o, into: &d)
        case .strictArray(let a):
            d.append(0x0A); d.append(be32(UInt32(a.count))); for x in a { write(x, into: &d) }
        }
    }

    private static func writeProperties(_ o: [String: AMF0Value], into d: inout Data) {
        // Sorted for a stable wire image; servers do not care about order.
        for k in o.keys.sorted() {
            let u = Array(k.utf8)
            d.append(contentsOf: be16(UInt16(u.count))); d.append(contentsOf: u)
            write(o[k]!, into: &d)
        }
        d.append(contentsOf: [0, 0, 0x09])
    }

    static func decodeAll(_ data: Data) -> [AMF0Value] {
        var out: [AMF0Value] = []
        var i = data.startIndex
        while i < data.endIndex, let (v, next) = decode(data, at: i) { out.append(v); i = next }
        return out
    }

    private static func decode(_ d: Data, at start: Int) -> (AMF0Value, Int)? {
        guard start < d.endIndex else { return nil }
        var i = start
        let marker = d[i]; i += 1
        switch marker {
        case 0x00:
            guard d.endIndex - i >= 8 else { return nil }
            var bits: UInt64 = 0
            for k in 0..<8 { bits = bits << 8 | UInt64(d[i + k]) }
            return (.number(Double(bitPattern: bits)), i + 8)
        case 0x01:
            guard i < d.endIndex else { return nil }
            return (.bool(d[i] != 0), i + 1)
        case 0x02:
            guard d.endIndex - i >= 2 else { return nil }
            let n = Int(readBE16(d, i - d.startIndex)); i += 2
            guard d.endIndex - i >= n else { return nil }
            return (.string(String(decoding: d[i..<(i + n)], as: UTF8.self)), i + n)
        case 0x03:
            guard let (o, next) = decodeProperties(d, at: i) else { return nil }
            return (.object(o), next)
        case 0x05: return (.null, i)
        case 0x06: return (.undefined, i)
        case 0x08:
            guard d.endIndex - i >= 4 else { return nil }
            i += 4
            guard let (o, next) = decodeProperties(d, at: i) else { return nil }
            return (.ecmaArray(o), next)
        case 0x0A:
            guard d.endIndex - i >= 4 else { return nil }
            let n = Int(readBE32(d, i - d.startIndex)); i += 4
            var a: [AMF0Value] = []
            for _ in 0..<n { guard let (v, next) = decode(d, at: i) else { return nil }; a.append(v); i = next }
            return (.strictArray(a), i)
        case 0x0C:
            guard d.endIndex - i >= 4 else { return nil }
            let n = Int(readBE32(d, i - d.startIndex)); i += 4
            guard d.endIndex - i >= n else { return nil }
            return (.string(String(decoding: d[i..<(i + n)], as: UTF8.self)), i + n)
        default:
            return nil
        }
    }

    private static func decodeProperties(_ d: Data, at start: Int) -> ([String: AMF0Value], Int)? {
        var o: [String: AMF0Value] = [:]
        var i = start
        while d.endIndex - i >= 3 {
            let n = Int(readBE16(d, i - d.startIndex)); i += 2
            if n == 0, d[i] == 0x09 { return (o, i + 1) }
            guard d.endIndex - i >= n else { return nil }
            let key = String(decoding: d[i..<(i + n)], as: UTF8.self); i += n
            guard let (v, next) = decode(d, at: i) else { return nil }
            o[key] = v; i = next
        }
        return nil
    }
}

// MARK: - The wire-ready frame

/// An encoded frame as BYTES plus its timing — the only shape that crosses
/// into the publisher actor. Built on whatever thread VideoToolbox called
/// back on, so a `CMSampleBuffer` (not `Sendable`, and reference-counted
/// against a pool) never escapes that thread.
public struct EncodedVideoFrame: Sendable {
    public let avccData: Data          // length-prefixed NAL units
    public let presentationTime: CMTime
    public let decodeTime: CMTime
    public let isKeyframe: Bool

    public init(avccData: Data, presentationTime: CMTime, decodeTime: CMTime, isKeyframe: Bool) {
        self.avccData = avccData; self.presentationTime = presentationTime
        self.decodeTime = decodeTime; self.isKeyframe = isKeyframe
    }

    /// Nil when the sample carries no data (VideoToolbox can emit one).
    public init?(_ sample: CMSampleBuffer) {
        guard let data = sample.dataBytes else { return nil }
        let pts = sample.presentationTimeStamp
        self.avccData = data
        self.presentationTime = pts
        self.decodeTime = sample.decodeTimeStamp.isValid ? sample.decodeTimeStamp : pts
        self.isKeyframe = sample.isKeyframe
    }
}

// MARK: - CMSampleBuffer helpers

extension CMSampleBuffer {
    var isKeyframe: Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]],
              let first = attachments.first else { return true }
        if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool { return !notSync }
        return true
    }

    /// The sample's bytes as one contiguous Data (VideoToolbox emits
    /// length-prefixed NAL units; AudioConverter output is one AAC frame).
    var dataBytes: Data? {
        guard let block = CMSampleBufferGetDataBuffer(self) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        var contiguous: CMBlockBuffer?
        // A block buffer can be non-contiguous; make it contiguous first.
        guard CMBlockBufferCreateContiguous(allocator: nil, sourceBuffer: block, blockAllocator: nil, customBlockSource: nil,
                                            offsetToData: 0, dataLength: CMBlockBufferGetDataLength(block), flags: 0,
                                            blockBufferOut: &contiguous) == noErr, let contiguous else { return nil }
        guard CMBlockBufferGetDataPointer(contiguous, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
              let pointer else { return nil }
        return Data(bytes: pointer, count: length)
    }
}

extension CMFormatDescription {
    /// The `avcC` atom body — AVCDecoderConfigurationRecord — that RTMP's
    /// AVC sequence header carries verbatim.
    var avcCRecord: Data? {
        guard let ext = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
              let avcC = ext["avcC"] as? Data else { return nil }
        return avcC
    }
}
