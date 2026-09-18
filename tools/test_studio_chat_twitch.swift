// Does the Twitch chat reader work, with no credential? (WATCH-TOGETHER §4.)
//
// Two halves, because they fail differently:
//
//   1. THE PARSER, against real IRCv3 shapes — escaped tag values, a message
//      containing colons, a USERNOTICE event, a bare nick with no
//      display-name. Deterministic, no network.
//   2. THE TRANSPORT, against tmi.twitch.tv itself with NO account: the
//      anonymous `justinfan` read that makes this feature reachable before
//      the owner registers anything.
//
// It counts messages and NEVER PRINTS THEIR TEXT. Strangers' chat should not
// end up in a log to prove a parser works, and a count is the only thing the
// assertion needs.
//
//   DEVELOPER_DIR=... xcrun swiftc -parse-as-library -O \
//     ArchiveWatch/ArchiveWatch/Studio/StudioEngine.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioAudio.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioOverlayRenderer.swift \
//     ArchiveWatch/ArchiveWatch/Studio/RTMPPublisher.swift \
//     ArchiveWatch/ArchiveWatch/Studio/StudioChatTwitch.swift \
//     tools/test_studio_chat_twitch.swift -o /tmp/awchat && /tmp/awchat [#channel]

import Foundation

@main
struct ChatHarness {

    static var failures = 0

    static func check(_ ok: Bool, _ what: String, _ detail: String = "") {
        if ok { print("OK: \(what)") }
        else { print("FAIL: \(what)\(detail.isEmpty ? "" : " — \(detail)")"); failures += 1 }
    }

    static func main() async {
        print("WATCH-TOGETHER §4 — Twitch chat, read anonymously\n")

        // ---- 1. the parser, on real shapes
        let privmsg = "@badge-info=;badges=moderator/1;color=#1E90FF;display-name=AdaL;"
            + "emotes=;id=abc-123;mod=1;room-id=1;tmi-sent-ts=1;turbo=0;user-id=2;user-type=mod"
            + " :adal!adal@adal.tmi.twitch.tv PRIVMSG #archivewatch :look at this https://ex.am/p:1 — wild"
        let (tags, rest) = StudioChatTwitch.splitTags(privmsg)
        check(tags["display-name"] == "AdaL", "the display name comes from the tags, not the login",
              "got \(tags["display-name"] ?? "nil")")
        check(tags["id"] == "abc-123", "the message id is the tag id, so a redraw cannot duplicate a line")
        check(StudioChatTwitch.command(in: rest) == "PRIVMSG", "the command is found past the prefix")
        check(StudioChatTwitch.nick(in: rest) == "adal", "the login is recoverable when there is no display name")
        // The trailing parameter must survive colons: most links contain one.
        let body = StudioChatTwitch.trailing(of: rest) ?? ""
        check(body == "look at this https://ex.am/p:1 — wild",
              "a message keeps its own colons", "got \"\(body)\"")

        // Escaped tag values: `\s` is a space, `\:` a semicolon.
        let notice = "@display-name=Ada;id=e1;system-msg=Ada\\ssubscribed\\sfor\\s3\\smonths!"
            + " :tmi.twitch.tv USERNOTICE #archivewatch"
        let (ntags, nrest) = StudioChatTwitch.splitTags(notice)
        check(ntags["system-msg"] == "Ada subscribed for 3 months!",
              "an escaped tag value is unescaped", "got \"\(ntags["system-msg"] ?? "")\"")
        check(StudioChatTwitch.command(in: nrest) == "USERNOTICE", "an event line is recognised as an event")

        // A line with no trailing parameter must not crash or invent one.
        check(StudioChatTwitch.trailing(of: ":tmi.twitch.tv 376 justinfan1 :>") == ">",
              "a trailing parameter of one character still parses")
        check(StudioChatTwitch.trailing(of: "PING") == nil, "a line with no trailing parameter yields nil")

        // ---- 2. the transport, against the real service with NO credential
        let channel = CommandLine.arguments.dropFirst().first ?? "twitchpresents"
        print("\n… connecting to irc.chat.twitch.tv:6697 anonymously, joining #\(channel.replacingOccurrences(of: "#", with: ""))")
        let chat = StudioChatTwitch()
        await chat.start(channel: channel)

        var joined = false
        for _ in 0..<20 {
            try? await Task.sleep(for: .seconds(1))
            let h = await chat.health
            if h.joined { joined = true; break }
            if let e = h.lastError { print("   (\(e))") }
        }
        let mid = await chat.health
        check(mid.connected, "TLS connected with no account", mid.lastError ?? "")
        check(joined, "the server completed the anonymous handshake (376)", mid.lastError ?? "")

        // Read for a while and count only. A channel may simply be quiet, and
        // that is not a failure of ours — so it is reported, not asserted.
        print("… reading for 20s (counting only; message text is never printed)")
        try? await Task.sleep(for: .seconds(20))
        let h = await chat.health
        let lines = await chat.lines
        print("   received \(h.linesReceived) message(s), \(h.eventsReceived) event(s); buffer holds \(lines.count)")
        print("   [diag] raw protocol lines=\(h.rawLines) receive callbacks=\(h.receiveCallbacks)")
        if h.linesReceived > 0 {
            let sane = lines.allSatisfy { !$0.id.isEmpty && !$0.author.isEmpty }
            check(sane, "every buffered line has an id and an author")
            check(lines.count <= 200, "the buffer is capped, so a busy channel cannot grow it without limit")
        } else {
            print("   NOTE: no messages arrived — the channel was quiet. Connect and JOIN are still proved;")
            print("         message flow is not, and is not claimed.")
        }
        await chat.stop()

        print(failures == 0 ? "\nPASS: the Twitch reader parses real shapes and connects with no credential"
                            : "\nFAIL: \(failures) check(s) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
