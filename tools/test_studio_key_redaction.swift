// §8.68 — a stream key a SERVER quotes back never reaches the screen or a log.
import Foundation

@main
struct KeyRedaction {
    static func main() {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "OK: \(what)" : "FAIL: \(what)"); if !ok { failures += 1 } }
        let key = "abcd-1234-efgh-5678"
        let nginx = "NetStream.Publish.BadName: \(key) already publishing"
        let red = redactingKey(in: nginx, key: key)
        check(!red.contains(key), "nginx-style echo is redacted -> \(red)")
        check(red.contains("already publishing"), "the rest of the sentence survives")
        let enc = "stream live/abcd%201234 not found"
        check(!redactingKey(in: enc, key: "abcd 1234").contains("abcd%201234"),
              "the percent-encoded form is redacted too")
        check(redactingKey(in: "the live stream", key: "live") == "the live stream",
              "a key too short to tell from words is left alone")
        let e = RTMPPublishError.rejected(code: "NetStream.Publish.BadName", description: nginx)
        check("\(e)".contains(key), "control: the raw error DOES carry the key")
        print(failures == 0 ? "PASS" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
