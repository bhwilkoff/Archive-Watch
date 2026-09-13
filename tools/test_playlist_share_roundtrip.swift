// Does the Apple share service read the links the OTHER platforms make?
//
// A share link is written on one platform and opened on another — that is the
// entire point of the feature — so the only test worth having crosses the
// boundary. This compiles the SHIPPED PlaylistShare.swift (never a copy) and
// feeds it blobs produced elsewhere.
//
//   swiftc -O tools/test_playlist_share_roundtrip.swift \
//          ArchiveWatch/ArchiveWatch/Services/PlaylistShare.swift -o /tmp/t && /tmp/t
//
// The web's `ShareList` in watch.js is the reference implementation; the
// fixtures below were produced by it and by the Roku channel, not by this file.

import Foundation

var pass = 0, fail = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : "  — " + detail)")
    ok ? (pass += 1) : (fail += 1)
}

// Top-level statements are only legal in a file named main.swift, and this one
// is compiled BESIDE the shipped service rather than being one.
@main enum Test {
static func main() {

// ---------------------------------------------------------------- round trip

let ids = ["TheGeneral720p1926", "college_1927", "silent-the-seventh-day"]
if let url = PlaylistShare.url(name: "creature feature", archiveIDs: ids) {
    check("a link is /list/ with the playlist in the fragment",
          url.absoluteString.hasPrefix("https://archivewatch.org/list/#"),
          url.absoluteString)
    if let back = PlaylistShare.shared(from: url) {
        check("its own link round-trips the name", back.name == "creature feature", back.name)
        check("its own link round-trips every id", back.archiveIDs == ids,
              back.archiveIDs.joined(separator: ","))
    } else {
        check("its own link round-trips", false, "decode returned nil")
    }
} else {
    check("a link is produced at all", false)
}

// ------------------------------------------------- blobs made ELSEWHERE
//
// ROKU. BrightScript has no deflate, so it emits the `0`-prefixed uncompressed
// variant — the reason that variant exists. Captured from the device console
// (AWSHARE open) on a Streaming Stick 4K, not constructed here.
let rokuURL = URL(string: "https://archivewatch.org/list/#0eyJpIjpbIlRoZUdlbmVyYWw3MjBwMTkyNiIsImNvbGxlZ2VfMTkyNyIsInNpbGVudC10aGUtc2V2ZW50aC1kYXkiXSwibiI6ImNyZWF0dXJlIGZlYXR1cmUifQ")!
if let r = PlaylistShare.shared(from: rokuURL) {
    check("reads a ROKU link (uncompressed, 0-prefixed)", r.archiveIDs.count == 3,
          "\(r.archiveIDs.count) ids")
    check("...with the right name", r.name == "creature feature", r.name)
    check("...and the right ids", r.archiveIDs == ids, r.archiveIDs.joined(separator: ","))
} else {
    check("reads a ROKU link", false, "decode returned nil")
}

// THE WEB, COMPRESSED. This is the direction that actually crosses codecs:
// the browser deflates with CompressionStream('deflate-raw') and this decodes
// with compression_decode_buffer(COMPRESSION_ZLIB). Produced by watch.js's own
// ShareList, not by this file. If the two ever disagree about what raw DEFLATE
// is, this is the assertion that says so.
let webURL = URL(string: "https://archivewatch.org/list/#q1bKU7JSSi5KTSwpLUpVSIPQSjpKmUpW0UohGanuqXmpRYk55kYGBYaWRmZAmeT8nJzU9NR4INccyC3OzEnNK9EtyUjVLU4tAzIzdFMSK5ViawE")!
if let w = PlaylistShare.shared(from: webURL) {
    check("reads a WEB link (deflated by CompressionStream)", w.archiveIDs == ids,
          w.archiveIDs.joined(separator: ","))
    check("...with the right name", w.name == "creature feature", w.name)
} else {
    check("reads a WEB link (deflated by CompressionStream)", false, "decode returned nil")
}

// THE OLD SHAPE. `#/list/<blob>` is what shipped first and is already in the
// wild. Links are permanent, so it must decode forever.
let oldShape = URL(string: "https://archivewatch.org/#/list/0eyJpIjpbIlRoZUdlbmVyYWw3MjBwMTkyNiIsImNvbGxlZ2VfMTkyNyIsInNpbGVudC10aGUtc2V2ZW50aC1kYXkiXSwibiI6ImNyZWF0dXJlIGZlYXR1cmUifQ")!
check("reads the OLD #/list/ shape", PlaylistShare.shared(from: oldShape)?.archiveIDs == ids)

// A blob in the PATH — nothing emits it, 404.html accepts it, so this does too.
let pathShape = URL(string: "https://archivewatch.org/list/0eyJpIjpbIlRoZUdlbmVyYWw3MjBwMTkyNiIsImNvbGxlZ2VfMTkyNyIsInNpbGVudC10aGUtc2V2ZW50aC1kYXkiXSwibiI6ImNyZWF0dXJlIGZlYXR1cmUifQ")!
check("reads a blob written into the path", PlaylistShare.shared(from: pathShape)?.archiveIDs == ids)

// ------------------------------------------------------------- the refusals

check("a link with no blob is nil", PlaylistShare.shared(from: URL(string: "https://archivewatch.org/list/")!) == nil)
check("an unrelated link is nil", PlaylistShare.shared(from: URL(string: "https://archivewatch.org/item/suddenly")!) == nil)
check("garbage in the fragment is nil", PlaylistShare.shared(from: URL(string: "https://archivewatch.org/list/#not-a-playlist")!) == nil)
check("an empty playlist makes no link", PlaylistShare.url(name: "x", archiveIDs: []) == nil)
check("past the limit makes no link",
      PlaylistShare.url(name: "x", archiveIDs: (0..<(PlaylistShare.limit + 1)).map { "id\($0)" }) == nil)
check("exactly at the limit still makes one",
      PlaylistShare.url(name: "x", archiveIDs: (0..<PlaylistShare.limit).map { "id\($0)" }) != nil)

// A 50-title playlist must survive the round trip — that is the cap the share
// sheet offers. Real catalogue ids, not `id-1..id-50`: synthetic ids are
// near-identical and deflate to almost nothing, which once flattered a size
// claim in this very feature by 5x. The length is NOT asserted here (that
// belongs to the measurement in docs/PLAYLIST-SHARING.md); what is asserted is
// that fifty of them survive intact.
let fifty = [
    "TheGeneral720p1926", "college_1927", "silent-the-seventh-day", "suddenly",
    "reefer_madness1938", "night_of_the_living_dead", "TheCabinetOfDrCaligari",
    "Nosferatu_1922", "his_girl_friday", "the_stranger_1946", "DetourFilm",
    "carnival_of_souls", "TheLastManOnEarth", "plan_9_from_outer_space",
    "Metropolis_1927", "TheKid_1921", "sherlock_jr_1924", "TheGoldRush1925",
    "safety_last_1923", "steamboat_bill_jr", "TheCircus1928", "city_lights_1931",
    "modern_times_1936", "the_great_dictator", "M_1931", "TheThirdMan",
    "double_indemnity", "the_maltese_falcon", "casablanca_trailer",
    "citizen_kane_trailer", "TheBirdsTrailer", "psycho_trailer_1960",
    "rear_window_trailer", "vertigo_trailer_1958", "north_by_northwest",
    "the_39_steps_1935", "the_lady_vanishes", "TheLodger1927", "blackmail_1929",
    "murder_1930", "rich_and_strange", "number_seventeen", "the_skin_game",
    "juno_and_the_paycock", "the_manxman_1929", "champagne_1928",
    "easy_virtue_1928", "downhill_1927", "the_ring_1927", "the_pleasure_garden",
]
if let u = PlaylistShare.url(name: "fifty", archiveIDs: fifty),
   let back = PlaylistShare.shared(from: u) {
    check("fifty REAL ids round-trip intact", back.archiveIDs == fifty)
} else {
    check("fifty REAL ids round-trip intact", false, "no link or no decode")
}

// ------------------------------------------------- what the ROUTER will see
//
// The parse has to happen before the `archivewatch://` scheme guard, because a
// share link is an ordinary https url — the whole point is that it opens for
// somebody with no app at all. These assert the DISCRIMINATION rather than the
// routing (which needs SwiftUI): a share link must be recognised as one, and
// an item link must NOT be mistaken for one.
check("a /list/ link is recognised as a shared playlist",
      PlaylistShare.shared(from: URL(string: "https://archivewatch.org/list/#0eyJpIjpbImEiXSwibiI6IngifQ")!) != nil)
check("an /item/ link is NOT",
      PlaylistShare.shared(from: URL(string: "https://archivewatch.org/item/suddenly")!) == nil)
check("a /series/ link is NOT",
      PlaylistShare.shared(from: URL(string: "https://archivewatch.org/series/alfred-hitchcock-presents")!) == nil)
check("an archivewatch://item deep link is NOT",
      PlaylistShare.shared(from: URL(string: "archivewatch://item/suddenly")!) == nil)
check("the bare site is NOT",
      PlaylistShare.shared(from: URL(string: "https://archivewatch.org/")!) == nil)
// A film whose id merely CONTAINS "list" must not be read as a playlist — the
// path check is on a segment, not a substring.
check("an item id containing 'list' is NOT a playlist",
      PlaylistShare.shared(from: URL(string: "https://archivewatch.org/item/the-listener-1932")!) == nil)

print("\n\(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
}
}
