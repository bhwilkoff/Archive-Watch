import Foundation

/// THE ROOM, AND THE CODE PEOPLE SAY OUT LOUD — SHAREPLAY §11.6 / §11.8.
///
/// Two doors into the same room:
///   • a LINK, for the device that receives it —
///     `https://archivewatch.org/together/#<code>-<filmID>`;
///   • a six-character CODE, for the far more common case the owner asked
///     about: on the call on a laptop, watching on the television.
///
/// The code is the interesting half. You are already on a call with these
/// people, so the cheapest transport for six characters between humans who
/// are talking to each other is talking — "the code is CALIG7" needs no
/// copy-paste, no second screen and no way to mis-send it. Decision 119
/// settled this shape in the other direction: a television hands over a link
/// as a CODE, because typing a URL with a remote is miserable.
public enum StudioRoom {

    /// **Crockford Base32**, not an alphabet invented here.
    ///
    /// It excludes I, L, O and U, and each exclusion has a reason worth
    /// keeping: I and L are confusable with 1, O with 0, and U is dropped so
    /// a random code cannot spell something unfortunate. Crucially 0 and 1
    /// REMAIN, which is what makes the input mapping below possible — an
    /// alphabet that excluded both members of each confusable pair would have
    /// nothing to map a mistyped O onto, and would have to reject it instead.
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// FOUR, because shorter is easier and the risk is a function of how many
    /// rooms are LIVE, not of how many codes exist.
    ///
    /// Owner, 2026-09-21: "Do we need a 6 digit code or could we get away with
    /// 4 (shorter is easier)?" Four characters of Base32 is 1,048,576 codes.
    /// What matters is the chance a random guess lands on a room somebody is
    /// actually in:
    ///
    ///     live rooms │ 4 chars           │ 6 chars
    ///     ───────────┼───────────────────┼──────────────────
    ///             10 │ 1 in 104,857      │ 1 in 107,374,182
    ///          1,000 │ 1 in 1,048        │ 1 in 1,073,741
    ///         10,000 │ 1 in 104          │ 1 in 107,374
    ///
    /// A free archival-film app will have single-digit concurrent rooms for a
    /// long time, and one keystroke fewer on a television remote is worth
    /// more than headroom nobody will use. **The threshold is ~1,000
    /// concurrent rooms**; past that this becomes 5 or 6, and it is one
    /// constant.
    ///
    /// Two things keep the live set small and are part of why 4 is safe:
    /// a code is checked against LIVE rooms when it is issued, and a room
    /// expires when its host stops. Neither is optional.
    ///
    /// AirPlay and Chromecast get away with 4 DIGITS because they are scoped
    /// to a network or to proximity. These rooms are global, which is why the
    /// alphabet is 32 wide rather than 10 — four Base32 characters carry as
    /// much as six digits.
    public static let codeLength = 4

    public static func newCode() -> String {
        var out = ""
        for _ in 0..<codeLength {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            out.append(alphabet[Int(byte) % alphabet.count])
        }
        return out
    }

    /// What a person typed, turned into the one canonical form — or nil.
    ///
    /// Forgiving on purpose, because the input arrives by EAR: somebody heard
    /// it over a call and is typing it with a remote control. Case is
    /// ignored, spaces and dashes are ignored (people group characters when
    /// they read them aloud), and the confusable glyphs are MAPPED rather than
    /// refused — a listener who hears "oh" and types O meant zero, and being
    /// told "invalid code" for that is a bad way to start a film.
    public static func normalize(_ typed: String) -> String? {
        var out = ""
        for ch in typed.uppercased() {
            switch ch {
            case " ", "-", "_", "\t": continue           // grouping, not content
            case "I", "L": out.append("1")               // Crockford's mapping
            case "O": out.append("0")
            case "U": return nil                          // deliberately not in the alphabet
            default:
                guard alphabet.contains(ch) else { return nil }
                out.append(ch)
            }
        }
        return out.count == codeLength ? out : nil
    }

    // MARK: - The link

    public static let host = "archivewatch.org"

    /// `https://archivewatch.org/together/#<code>-<filmID>`
    ///
    /// The film id travels in the LINK as well as in the room record, so a
    /// device that opens it can start loading the film before its first poll
    /// returns. The record stays the truth; the link is a head start.
    ///
    /// In the FRAGMENT, like `PLAYLIST-SHARING` — everything after `#` is
    /// never sent to a server, so a room a host shares is not logged by
    /// anyone's web infrastructure on the way.
    public static func link(code: String, filmID: String) -> URL? {
        guard let code = normalize(code), !filmID.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/together/"
        c.fragment = "\(code)-\(filmID)"
        return c.url
    }

    public static func parse(link: URL) -> (code: String, filmID: String)? {
        guard link.path.contains("/together"),
              let fragment = link.fragment, !fragment.isEmpty else { return nil }
        // The film id may itself contain dashes — archive ids routinely do —
        // so split on the FIRST separator only. Splitting on every dash is the
        // obvious mistake and would truncate most of this catalogue's ids.
        guard let sep = fragment.firstIndex(of: "-") else { return nil }
        let rawCode = String(fragment[fragment.startIndex..<sep])
        let filmID = String(fragment[fragment.index(after: sep)...])
        guard let code = normalize(rawCode), !filmID.isEmpty else { return nil }
        return (code, filmID)
    }
}
