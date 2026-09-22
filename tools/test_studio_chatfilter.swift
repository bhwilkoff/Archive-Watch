// §8.43 — what the host's chat filter lets through (§D22).
//
// Every rule, the interactions between them, and the two cases that decide
// whether this is a useful feature or an infuriating one: a message that
// merely CONTAINS an exclamation mark is somebody talking, and a domain
// written without a scheme is still a link.
import Foundation

@main
struct ChatFilterTest {
    static var failures = 0

    static func check(_ what: String, _ f: StudioChatFilter,
                      author: String = "someone", _ text: String, allow: Bool) {
        let got = f.allows(author: author, text: text)
        if got == allow {
            print("  ok   \(what)")
        } else {
            print("  FAIL \(what): expected \(allow ? "ALLOW" : "DROP"), got "
                  + "\(got ? "ALLOW" : "DROP")  —  \(author): \(text)")
            failures += 1
        }
    }

    static func main() {
        print("§8.43 chat filter")

        var off = StudioChatFilter()
        off.hideCommands = false; off.hideLinks = false
        var on = StudioChatFilter()   // defaults: commands and links hidden

        // EVERYTHING OFF still drops nothing but empties. A filter whose
        // "off" state is not transparent is a filter nobody can reason about.
        check("off: ordinary message", off, "what a great film", allow: true)
        check("off: a command", off, "!uptime", allow: true)
        check("off: a link", off, "https://archive.org/details/x", allow: true)
        check("off: empty", off, "   ", allow: false)
        check("off: newline only", off, "\n", allow: false)

        // COMMANDS.
        check("commands: !uptime is a command", on, "!uptime", allow: false)
        check("commands: !drop with args", on, "!so someone", allow: false)
        // THE ONE THAT MATTERS. Dropping this would quietly eat a real
        // conversation, and a host would never trace it back to a checkbox.
        check("commands: mid-sentence ! is speech", on, "wait what!! that was great",
              allow: true)
        check("commands: a lone ! is speech", on, "!", allow: true)
        check("commands: !!! is speech", on, "!!!", allow: true)
        check("commands: leading space then ! is still a command", on, "  !uptime",
              allow: false)

        // LINKS. Without a scheme is the shape people actually paste.
        check("links: full url", on, "look https://example.com/a", allow: false)
        check("links: www", on, "www.example.com", allow: false)
        check("links: bare domain", on, "go to bit.ly/abc now", allow: false)
        check("links: bare .org", on, "archive.org has it", allow: false)
        check("links: a sentence with a period is NOT a link", on,
              "i liked it. a lot.", allow: true)
        check("links: a decimal is not a link", on, "it was 9.5 out of 10", allow: true)
        // A file name should not read as a link — this is the over-match that
        // would eat conversation, the mirror of the "!!" case.
        check("links: a plain filename is not a link", on, "reel 2.mkv looked better",
              allow: true)

        // PEOPLE.
        let blocked = StudioChatFilter(hideCommands: false, hideLinks: false,
                                       blockedText: "@Spammer, anotherone\nthird")
        check("blocked: named, with the @ the host pasted", blocked,
              author: "spammer", "hello", allow: false)
        check("blocked: named, different case", blocked, author: "SPAMMER", "hello",
              allow: false)
        check("blocked: comma-separated", blocked, author: "anotherone", "hi", allow: false)
        check("blocked: newline-separated", blocked, author: "third", "hi", allow: false)
        check("blocked: an author with a @ of their own", blocked, author: "@third",
              "hi", allow: false)
        check("blocked: someone else is fine", blocked, author: "friend", "hi", allow: true)
        check("blocked: a substring is NOT a match", blocked, author: "spammerson",
              "hi", allow: true)

        // INTERACTION: blocked outranks everything, and a blocked author's
        // ordinary message is still dropped.
        var all = StudioChatFilter(hideCommands: true, hideLinks: true,
                                   blockedText: "bot")
        check("interaction: blocked author, ordinary text", all, author: "bot",
              "hello everyone", allow: false)
        check("interaction: allowed author, command", all, author: "friend",
              "!uptime", allow: false)
        check("interaction: allowed author, ordinary text", all, author: "friend",
              "hello everyone", allow: true)

        // apply() KEEPS ORDER, which the pump depends on: the column is
        // newest-last and a reordering filter would scramble a conversation.
        let lines = ["a", "!cmd", "b", "http://x.com", "c"].enumerated().map {
            StudioOverlay.ChatLine(id: "\($0.offset)", author: "someone",
                                   text: $0.element, isEvent: false)
        }
        let kept = on.apply(lines).map(\.text)
        if kept == ["a", "b", "c"] {
            print("  ok   apply() keeps order and drops the right three")
        } else {
            print("  FAIL apply() returned \(kept), expected [a, b, c]")
            failures += 1
        }

        // NEGATIVE CONTROL. Every check above asserts one call; a filter that
        // returned `true` unconditionally would fail the DROP rows, and one
        // that returned `false` would fail the ALLOW rows — but a filter with
        // no rules at all would pass the whole "off" block. So: the default
        // filter and the all-off filter must DISAGREE about something.
        let probe = "!uptime"
        if on.allows(author: "x", text: probe) == off.allows(author: "x", text: probe) {
            print("  FAIL control — the default and all-off filters agree on '\(probe)',")
            print("        so the toggles are not connected to anything.")
            failures += 1
        } else {
            print("  ok   control — the toggles actually change the verdict")
        }

        print(failures == 0 ? "PASS" : "FAIL: \(failures) check(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
