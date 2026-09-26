// A pasted archive.org link resolves in the apps' search (2026-09-26): the same
// table as Android's ArchiveLinkTest and the web's test_web_archive_address.
//   swiftc -parse-as-library ArchiveWatch/ArchiveWatch/Services/ArchiveLink.swift tools/test_archive_link.swift -o /tmp/t && /tmp/t
import Foundation

@main struct ArchiveLinkTest {
    static func main() {
        var failures = 0
        let cases: [(String, String?)] = [
            ("https://archive.org/details/TheScarecrow1920", "TheScarecrow1920"),
            ("archive.org/details/the-scarecrow/The+Scarecrow.mp4", "the-scarecrow"),
            ("https://archive.org/download/the-scarecrow/The%20Scarecrow.mp4", "the-scarecrow"),
            ("https://www.archivewatch.org/details/x-y?q=1", "x-y"),
            ("  https://archive.org/embed/abc  ", "abc"),
            ("scarecrow", nil),
            ("https://evil.example/details/x", nil),
            ("archive.org", nil),
        ]
        for (text, want) in cases {
            let got = ArchiveLink.id(from: text)
            let ok = got == want
            if !ok { failures += 1 }
            print("\(ok ? "PASS" : "FAIL") \(text.debugDescription) -> \(got ?? "nil")")
        }
        print(failures == 0 ? "PASS archive links" : "FAILED (\(failures))")
        exit(failures == 0 ? 0 : 1)
    }
}
