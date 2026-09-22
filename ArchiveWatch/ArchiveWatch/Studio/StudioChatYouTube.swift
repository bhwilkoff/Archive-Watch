// YouTube live chat, read into the program's chat column
// (WATCH-TOGETHER §4; roadmap item #3).
//
// WHY THIS WAS MISSING, AND IT WAS NOT THE HARD PART. `YouTubeLive.chat(
// liveChatID:pageToken:)` has been written, complete and correct, since the
// platform layer was built: it lists `liveChat/messages`, maps them to author
// and text, and returns YouTube's own `pollingIntervalMillis`. **Nothing ever
// called it.** And the `liveChatId` that it needs was read out of the
// `liveBroadcasts.insert` response into `StreamCredentials.liveChatID`, and
// then dropped, because `StudioGoLive.destination()` returned a bare `URL?`.
//
// That is the shape this project keeps finding — a capability declared where
// nothing can reach it (§9.ccc, the credential path that lived inside one
// platform's file; Decision 133, a value that lands nowhere). The fix here is
// the same one: carry the thing to where it is used, and have exactly one
// place that knows how.
//
// WHY POLLING, when Twitch gets a socket. YouTube's Data API publishes no
// streaming chat interface to a client of our type — `liveChat/messages` is a
// GET, and the response TELLS YOU how soon to ask again. An app that ignores
// `pollingIntervalMillis` and picks its own interval gets throttled, so the
// server's number is the one this uses. Decision 128's rule again: take the
// flow the platform actually offers.
//
// READING is all this does. It never posts a message. The host speaks with
// their voice; the audience speaks in chat; neither is put in the other's
// mouth.

import Foundation

public actor StudioChatYouTube {

    public struct Health: Sendable, Equatable {
        public var polling = false
        public var linesReceived = 0
        public var polls = 0
        public var lastError: String?
        /// What YouTube last asked us to wait. Surfaced because a chat column
        /// that updates every 10 s on a busy stream looks broken, and the
        /// reason is the server's, not ours.
        public var pollIntervalMS = 0
    }

    public private(set) var health = Health()

    /// Newest last, capped: the overlay draws the tail, and an unbounded
    /// buffer on a busy stream is a leak with a view. Same contract as
    /// `StudioChatTwitch` so the engine's pump cannot tell them apart.
    public private(set) var lines: [StudioOverlay.ChatLine] = []
    public var maxLines = 200

    private var task: Task<Void, Never>?
    private var pageToken: String?
    /// A monotonically increasing id, because YouTube's own message ids are
    /// opaque strings and the renderer's cache key compares ids for equality
    /// only — a counter is enough and costs no parsing.
    private var counter = 0

    public init() {}

    /// Reads `liveChatID` until `stop()`.
    ///
    /// The FIRST page is discarded on purpose. `liveChat/messages` opens with
    /// the backlog of everything said before we asked, which on a broadcast
    /// that has been live for a while would dump a wall of old messages into
    /// the programme at the moment a host turns chat on. A viewer reads the
    /// conversation from now.
    public func start(liveChatID: String, token: String) {
        stop()
        health = Health()
        health.polling = true
        task = Task { [weak self] in
            let api = YouTubeLive(token: token)
            var first = true
            while !Task.isCancelled {
                guard let self else { return }
                let token = await self.pageToken
                do {
                    let page = try await api.chat(liveChatID: liveChatID, pageToken: token)
                    await self.accept(page, discard: first)
                    first = false
                    let ms = max(1000, page.pollAfterMS)
                    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
                } catch {
                    await self.failed(error)
                    // A FIXED BACKOFF, not the server's interval: the error
                    // path has no interval to read, and hammering a failing
                    // endpoint at 1 Hz is how a token problem becomes a rate
                    // limit on top of a token problem.
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        health.polling = false
        pageToken = nil
    }

    private func accept(_ page: (messages: [(author: String, text: String)],
                                next: String?, pollAfterMS: Int),
                        discard: Bool) {
        pageToken = page.next
        health.polls += 1
        health.pollIntervalMS = page.pollAfterMS
        health.lastError = nil
        guard !discard else { return }
        for m in page.messages {
            counter += 1
            lines.append(StudioOverlay.ChatLine(id: "yt\(counter)",
                                                author: m.author,
                                                text: m.text,
                                                isEvent: false))
            health.linesReceived += 1
        }
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
    }

    private func failed(_ error: Error) {
        // SAY IT rather than go quiet. A chat column that simply stops is
        // indistinguishable from an audience that stopped talking, and the
        // two have opposite fixes.
        health.lastError = "\(error)"
    }
}
