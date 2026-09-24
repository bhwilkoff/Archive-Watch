// Twitch chat, read ANONYMOUSLY, for the chat the Studio composites into the
// program (WATCH-TOGETHER §4).
//
// WHY THIS EXISTS BEFORE THE CREDENTIALS DO. Chat was listed as "renderer
// done, platform chat pending OAuth" — true of YouTube, and NOT true of
// Twitch. Twitch's historical IRC interface accepts a read-only connection
// with NO ACCOUNT AT ALL: nick `justinfan<digits>`, no password. Verified
// against tmi.twitch.tv on 2026-09-18 with no credential of any kind:
//
//     :tmi.twitch.tv CAP * ACK :twitch.tv/tags twitch.tv/commands
//     :tmi.twitch.tv 001 justinfan80596 :Welcome, GLHF!
//     :tmi.twitch.tv 376 justinfan80596 :>
//
// So the Twitch half of chat is not owner-blocked, and the renderer can be
// proved end to end against real messages from a real channel.
//
// WHY IRC AND NOT EVENTSUB. Twitch now prefers EventSub
// (`wss://eventsub.ws.twitch.tv/ws`, subscriptions created over Helix against
// the session id from the welcome frame) and publishes a migration guide away
// from IRC. But `channel.chat.message` requires the `user:read:chat` scope
// from a signed-in user and **EventSub has no anonymous mode** — so on this
// build, today, it cannot read anything. This is Decision 128's rule again:
// take the flow the platform actually offers a client of our type, not the one
// that is newer. When sign-in exists, EventSub becomes the better path and this
// file becomes the fallback; that is a migration, not a rewrite, because
// everything above `ChatLine` is unchanged either way.
//
// READING is all this does. It never sends a message, never authenticates, and
// never joins as a person: an anonymous reader cannot be mistaken for the host
// speaking.

import Foundation
import Network

public actor StudioChatTwitch {

    public struct Health: Sendable, Equatable {
        public var connected = false
        public var joined = false
        public var linesReceived = 0
        public var eventsReceived = 0
        public var lastError: String?
        public var reconnects = 0
        /// Raw protocol lines seen, whatever they were. Distinguishes "no data
        /// is arriving" from "data arrives and is not parsed" — the two have
        /// identical symptoms and opposite fixes.
        public var rawLines = 0
        public var receiveCallbacks = 0
    }

    public private(set) var health = Health()

    /// Newest last, capped: the overlay draws the tail, and an unbounded
    /// buffer on a busy channel is a leak with a view.
    public private(set) var lines: [StudioOverlay.ChatLine] = []
    public var maxLines = 200

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "org.archivewatch.twitchchat")
    /// RAW BYTES until a whole line has arrived (launch audit B). Each read
    /// used to be decoded as UTF-8 on its own, and a read that ended in the
    /// middle of an emoji failed to decode — dropping every message in it.
    /// A line ends in CR LF, which can never sit inside a multi-byte
    /// character, so a complete line always decodes.
    private var inbound = Data()
    private var channel = ""
    private var running = false
    /// One ordered hand-off from the socket's queue to this actor: a Task per
    /// read does not promise order, and chat lines are bytes in sequence.
    private var feed: AsyncStream<(NWConnection, Data)>.Continuation?
    private var feedTask: Task<Void, Never>?
    /// A reconnect already waiting — one failure must not open two.
    private var reconnecting = false

    public init() {}

    /// Joins `channel` (with or without the leading `#`) and reads until
    /// `stop()`. No credential is sent, ever.
    public func start(channel rawChannel: String) async {
        let name = rawChannel.hasPrefix("#") ? String(rawChannel.dropFirst()) : rawChannel
        channel = name.lowercased()
        running = true
        let (stream, cont) = AsyncStream.makeStream(of: (NWConnection, Data).self)
        feed = cont
        feedTask = Task { [weak self] in
            for await (c, data) in stream { await self?.deliver(data, from: c) }
        }
        await connect()
    }

    public func stop() {
        running = false
        connection?.cancel()
        connection = nil
        feed?.finish(); feed = nil
        feedTask?.cancel(); feedTask = nil
        health.connected = false
        health.joined = false
    }

    private func connect() async {
        let params = NWParameters.tls
        params.serviceClass = .responsiveData
        // The old connection goes before the new one starts, and its bytes
        // are not carried into the new one's first line.
        connection?.cancel()
        inbound.removeAll()
        let c = NWConnection(host: "irc.chat.twitch.tv", port: 6697, using: params)
        connection = c
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: Task { await self.handshake() }
            case .failed(let e): Task { await self.dropped(e.localizedDescription, from: c) }
            case .waiting(let e): Task { await self.waiting(e.localizedDescription, on: c) }
            case .cancelled: break
            default: break
            }
        }
        if let feed { receive(on: c, into: feed) }
        c.start(queue: queue)
    }

    private func handshake() {
        health.connected = true
        health.lastError = nil
        // The tags capability is what carries `display-name`, `color` and the
        // message `id`. Without it a line arrives as a bare nick and the
        // overlay has nothing to show but lowercase login names.
        send("CAP REQ :twitch.tv/tags twitch.tv/commands")
        send("NICK justinfan\(Int.random(in: 10_000...99_999))")
        send("JOIN #\(channel)")
    }

    private func send(_ line: String) {
        connection?.send(content: Data((line + "\r\n").utf8), completion: .contentProcessed { _ in })
    }

    /// Re-arms IMMEDIATELY inside the completion handler, on the connection's
    /// own queue, and only hops to the actor to hand over bytes.
    ///
    /// The first version re-armed through `Task { await self.keepReceiving() }`,
    /// and the read loop stopped after three callbacks: the welcome burst and
    /// the JOIN reply arrived (12 protocol lines, so parsing was fine) and then
    /// nothing, forever. It looked exactly like a quiet channel, and the
    /// harness said so — while a raw socket probe of the same channel was
    /// counting messages. `NWConnection` delivers one callback per `receive`,
    /// so anything that can drop between the callback and the next `receive`
    /// ends the stream silently. Nothing may sit in that gap.
    private nonisolated func receive(on c: NWConnection,
                                     into feed: AsyncStream<(NWConnection, Data)>.Continuation) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { feed.yield((c, data)) }
            if let error {
                Task { await self.dropped(error.localizedDescription, from: c) }
                return
            }
            if isComplete {
                Task { await self.dropped("closed by the server", from: c) }
                return
            }
            // Before any await, and unconditionally.
            self.receive(on: c, into: feed)
        }
    }

    private func deliver(_ data: Data, from c: NWConnection) {
        guard c === connection else { return }   // bytes from a replaced connection
        health.receiveCallbacks += 1
        ingest(data)
    }

    /// No route yet (Wi-Fi changing, offline). NWConnection retries by itself
    /// when the network returns, so this is said, not acted on.
    private func waiting(_ why: String, on c: NWConnection) {
        guard c === connection else { return }
        health.connected = false
        health.lastError = "waiting for the network — \(why)"
    }

    private func dropped(_ why: String, from c: NWConnection) async {
        // ONE reconnect per failure, and only for the CURRENT connection: an
        // error followed by .failed used to call this twice, and each call
        // opened its own new connection (launch audit B).
        guard running, c === connection, !reconnecting else { return }
        reconnecting = true
        defer { reconnecting = false }
        health.connected = false
        health.joined = false
        health.lastError = why
        health.reconnects += 1
        // Bounded and unhurried: chat is not the broadcast. A reader that
        // hammers a reconnect loop costs the host nothing useful and Twitch
        // rate-limits it anyway.
        try? await Task.sleep(for: .seconds(5))
        if running { await connect() }
    }

    private func ingest(_ data: Data) {
        inbound.append(data)
        let crlf = Data([0x0D, 0x0A])
        while let r = inbound.range(of: crlf) {
            let lineBytes = inbound.subdata(in: inbound.startIndex..<r.lowerBound)
            inbound.removeSubrange(inbound.startIndex..<r.upperBound)
            health.rawLines += 1
            handle(String(decoding: lineBytes, as: UTF8.self))
        }
    }

    /// The byte path without a socket, for §8.63.
    func ingestForTest(_ data: Data) { ingest(data) }

    private func handle(_ line: String) {
        // A PING that goes unanswered ends the connection within minutes, and
        // the symptom is a chat that simply stops with no error.
        if line.hasPrefix("PING") {
            send("PONG :tmi.twitch.tv")
            return
        }
        if line.contains(" 376 ") { health.joined = true; return }

        let (tags, rest) = Self.splitTags(line)
        guard let kind = Self.command(in: rest) else { return }
        switch kind {
        case "PRIVMSG":
            guard let body = Self.trailing(of: rest) else { return }
            let author = tags["display-name"].flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.nick(in: rest) ?? "someone"
            append(StudioOverlay.ChatLine(
                id: tags["id"] ?? UUID().uuidString,
                author: author, text: body, isEvent: false))
            health.linesReceived += 1
        case "USERNOTICE":
            // A sub, gift or raid: the platform's own event, which §4 gives the
            // marquee colour rather than a badge we would have to fetch.
            let author = tags["display-name"] ?? "Twitch"
            let body = tags["system-msg"]?.replacingOccurrences(of: "\\s", with: " ")
                ?? Self.trailing(of: rest) ?? "joined in"
            append(StudioOverlay.ChatLine(
                id: tags["id"] ?? UUID().uuidString,
                author: author, text: body, isEvent: true))
            health.eventsReceived += 1
        default:
            break
        }
    }

    private func append(_ l: StudioOverlay.ChatLine) {
        lines.append(l)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    // MARK: - IRCv3 parsing, kept small and total
    //
    // Twitch's lines are a strict subset of IRCv3, but the subset includes
    // escaped tag values (`\s` for space in `system-msg`) and a trailing
    // parameter that may itself contain colons, so neither can be split
    // naively.

    static func splitTags(_ line: String) -> ([String: String], String) {
        guard line.hasPrefix("@"), let sp = line.firstIndex(of: " ") else { return ([:], line) }
        let raw = String(line[line.index(after: line.startIndex)..<sp])
        var tags: [String: String] = [:]
        for pair in raw.split(separator: ";") {
            let bits = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let k = bits.first else { continue }
            let v = bits.count > 1 ? String(bits[1]) : ""
            tags[String(k)] = v
                .replacingOccurrences(of: "\\s", with: " ")
                .replacingOccurrences(of: "\\:", with: ";")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return (tags, String(line[line.index(after: sp)...]))
    }

    static func command(in rest: String) -> String? {
        var parts = rest.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.first?.hasPrefix(":") == true { parts.removeFirst() }
        return parts.first
    }

    static func nick(in rest: String) -> String? {
        guard rest.hasPrefix(":"), let bang = rest.firstIndex(of: "!") else { return nil }
        return String(rest[rest.index(after: rest.startIndex)..<bang])
    }

    /// The trailing parameter: everything after the FIRST " :" that follows
    /// the command. Splitting on every colon breaks any message containing
    /// one, which is most links.
    static func trailing(of rest: String) -> String? {
        guard let r = rest.range(of: " :") else { return nil }
        return String(rest[r.upperBound...])
    }
}
