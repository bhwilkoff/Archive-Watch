// §8.63 — a chat message whose bytes arrive in two reads is not lost.
//
// Twitch's IRC stream is bytes; a read can end in the middle of a multi-byte
// character. The reader used to decode each read as UTF-8 on its own, so a
// read ending mid-emoji decoded to nil and EVERY message in it vanished
// (launch audit B). It now buffers bytes and decodes whole lines.
//
// Negative control: the old per-read decode, applied to the same split, must
// fail — otherwise this split does not exercise the defect.

import Foundation

@main
struct ChatBytes {
    static var failures = 0
    static func check(_ ok: Bool, _ what: String) {
        print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 }
    }

    static func main() async {
        let line = "@display-name=Ada;id=m1 :ada!ada@ada.tmi.twitch.tv PRIVMSG #aw :what a scene \u{1F3AC} bravo\r\n"
            + "@display-name=Bo;id=m2 :bo!bo@bo.tmi.twitch.tv PRIVMSG #aw :second\r\n"
        let bytes = Data(line.utf8)
        // Split INSIDE the emoji's four bytes.
        let emojiStart = bytes.firstRange(of: Data("\u{1F3AC}".utf8))!.lowerBound
        let cut = emojiStart + 2
        let a = bytes.subdata(in: bytes.startIndex..<cut)
        let b = bytes.subdata(in: cut..<bytes.endIndex)

        check(String(data: a, encoding: .utf8) == nil,
              "control: the old per-read decode drops the first read")

        let chat = StudioChatTwitch()
        await chat.ingestForTest(a)
        await chat.ingestForTest(b)
        let lines = await chat.lines
        check(lines.count == 2, "both messages arrive (\(lines.count))")
        check(lines.first?.text == "what a scene \u{1F3AC} bravo", "the split emoji survives intact")
        check(lines.last?.author == "Bo", "the second message is not glued to the first")

        // A partial line stays buffered until its CR LF arrives.
        let chat2 = StudioChatTwitch()
        await chat2.ingestForTest(Data("@id=m3 :c!c@c.tmi.twitch.tv PRIVMSG #aw :half".utf8))
        let before = await chat2.lines.count
        await chat2.ingestForTest(Data(" done\r\n".utf8))
        let after = await chat2.lines
        check(before == 0 && after.count == 1 && after[0].text == "half done",
              "a line waits for its terminator")

        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
