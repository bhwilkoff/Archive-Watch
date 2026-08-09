// Subtitle sourcing harness — compiles the SHIPPED files and asserts the pure
// logic that decides WHICH subtitle a viewer gets and whether it is fit to show.
//
//   swiftc -O tools/test_subtitle_sources.swift \
//     ArchiveWatch/ArchiveWatch/Networking/OpenSubtitlesClient.swift \
//     ArchiveWatch/ArchiveWatch/Services/SubtitleStore.swift \
//     ArchiveWatch/ArchiveWatch/Services/AutoCaptions.swift -o /tmp/subs && /tmp/subs
//
// The quality-gate cases use the REAL measured densities from
// docs/SUBTITLE-COVERAGE-PLAN.md §4 (White Zombie 14 wpm vs His Girl Friday 187).
import Foundation
@main struct T {
  static func main() {
    var pass = 0, fail = 0
    func ck(_ n: String, _ ok: Bool, _ d: String = "") {
      if ok { pass += 1; print("  PASS  \(n)") } else { fail += 1; print("  FAIL  \(n) \(d)") }
    }
    // --- OpenSubtitles: match on the IMDb id, never the title
    ck("imdb id -> digits", OpenSubtitles.searchURL(imdbID: "tt0070666")?.query?.contains("imdb_id=70666") == true)
    ck("bare digits accepted", OpenSubtitles.searchURL(imdbID: "70666") != nil)
    ck("garbage id rejected", OpenSubtitles.searchURL(imdbID: "not-an-id") == nil)
    ck("empty id rejected", OpenSubtitles.searchURL(imdbID: "") == nil)

    // --- ranking: trusted + popular win; hearing-impaired ranked last, not dropped
    let m = { (id: Int, dl: Int, tr: Bool, hi: Bool) in
      OpenSubtitles.Match(fileID: id, language: "en", downloadCount: dl,
                          fromTrusted: tr, hearingImpaired: hi, releaseName: "r\(id)") }
    ck("most-downloaded wins", OpenSubtitles.best(of: [m(1,10,false,false), m(2,900,false,false)])?.fileID == 2)
    ck("trusted beats popular", OpenSubtitles.best(of: [m(1,900,false,false), m(2,10,true,false)])?.fileID == 2)
    ck("hearing-impaired ranked last", OpenSubtitles.best(of: [m(1,10,false,true), m(2,5,false,false)])?.fileID == 2)
    ck("...but still used when alone", OpenSubtitles.best(of: [m(1,10,false,true)])?.fileID == 1)
    ck("empty -> nil", OpenSubtitles.best(of: []) == nil)

    // --- SRT -> VTT: the comma is the #1 reason a track renders nothing
    let vtt = OpenSubtitles.srtToVTT("1\n00:01:02,345 --> 00:01:04,000\nHello")
    ck("header added", vtt.hasPrefix("WEBVTT"))
    ck("comma -> dot", vtt.contains("00:01:02.345 --> 00:01:04.000"), vtt)

    // --- byte decoding (UTF-16 was shipping as mojibake)
    let srt = "1\n00:00:01,000 --> 00:00:02,000\nHej"
    ck("utf-16 decoded", OpenSubtitles.decode(srt.data(using: .utf16)!).contains("Hej"))
    ck("utf-8 decoded", OpenSubtitles.decode(srt.data(using: .utf8)!).contains("Hej"))

    // --- quality gate, on the REAL measured numbers
    func cues(_ n: Int, words: Int, span: Double) -> [(start: Double, text: String)] {
      // VARIED text — real dialogue does not repeat verbatim, and the previous
      // version of this helper emitted identical cues, which the duplicate-cue
      // check correctly rejected. That was the test being wrong, not the gate.
      (0..<n).map { i in (start: span * Double(i) / Double(n),
                          text: (0..<words).map { "w\(i)_\($0)" }.joined(separator: " ")) }
    }
    // His Girl Friday ~187 wpm over 89 min
    ck("rich human transcript accepted",
       CaptionQuality.assess(cues: cues(3398, words: 5, span: 5300), runtime: 5340).ok)
    // White Zombie ASR: 14 wpm, 3 cues/min
    ck("sparse ASR rejected",
       !CaptionQuality.assess(cues: cues(210, words: 5, span: 4100), runtime: 4140).ok)
    // stops a third of the way in
    ck("gave-up transcript rejected",
       !CaptionQuality.assess(cues: cues(1200, words: 5, span: 1500), runtime: 5400).ok)
    let looped = (0..<800).map { (start: Double($0) * 6, text: "alright alright alright") }
    ck("looped transcript rejected", !CaptionQuality.assess(cues: looped, runtime: 4800).ok)

    // --- quota comes from the API, never hardcoded: it is PER USER, and the
    // free allowance has changed repeatedly (200 -> 20 -> 10 across eras).
    let loginJSON = """
    {"token":"abc","user":{"allowed_downloads":20,"remaining_downloads":17,"level":"Sub leecher"}}
    """.data(using: .utf8)!
    let parsed = (try? JSONSerialization.jsonObject(with: loginJSON)) as? [String: Any] ?? [:]
    let q = OpenSubtitles.parseQuota(parsed)
    ck("quota read from API", q?.allowed == 20 && q?.remaining == 17, "\(String(describing: q))")
    ck("quota absent -> nil", OpenSubtitles.parseQuota(["token": "x"]) == nil)
    var fresh = OpenSubtitles.Session(token: "t", quota: q)
    ck("token reused while fresh", fresh.isFresh)
    fresh.obtained = Date(timeIntervalSinceNow: -22 * 3600)
    ck("token re-login after ~24h", !fresh.isFresh)

    // --- the local HLS the player consumes
    let seg = SubtitleStore.encodeSegment(URL(string: "https://archive.org/download/x/A Film (1949).mp4")!)
    ck("segment percent-encoded", seg.contains("%20") && seg.contains("%28"), seg)
    ck("host untouched", seg.hasPrefix("https://archive.org/download/"))

    print("\n\(pass)/\(pass+fail) passed")
    if fail > 0 { exit(1) }
  }
}
