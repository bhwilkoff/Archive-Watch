// Which films may be broadcast to the world (docs/WATCH-TOGETHER.md §3.4).
//
// Watch Together Studio publishes to a viewer's OWN YouTube or Twitch account.
// A wrong call here does not degrade a screen — it puts a real person's channel
// at risk of a copyright strike. So the gate is deliberately narrower than the
// one that decides what the app will PLAY, and it is the same gate the Roku
// Search feed already applies to films it advertises to a third party
// (Decision 113, `--tier guaranteed`).
//
// WHY `safe_pd_age` ALONE. The owner set this bar for the Roku feed on
// 2026-09-10 after measuring the looser one: of the items that the audit's
// "strict" set admitted, 107 post-1963 titles rode in on an uploader's CC
// mark (A Bridge Too Far, Cross of Iron), a CC0 dedication on a studio
// cartoon (Jonny Quest, The Simpsons pilot), or membership of a government
// collection (a 2021 feature). Only AGE cannot be argued. Broadcasting is at
// least as exposed as advertising, so it inherits the same bar until the
// owner says otherwise — see `Tier` for the knob and who owns it.
//
// AND AN UNKNOWN VERDICT IS A NO. A device plays from a cached database and is
// not entitled to today's schema (`items.rightsBucket` arrived at schema 2).
// When the column is missing, or the value is null, this refuses — because the
// alternative is broadcasting a film whose rights nobody could read.

import Foundation

public enum StudioRights {

    /// Which rights verdicts may go live. The names are `audit_rights.bucket`'s.
    public enum Tier: String, Sendable, CaseIterable {
        /// Pre-1930 by age alone. What the Roku feed ships.
        case guaranteed
        /// Adds government collections, an archive.org licence, and a
        /// Creative Commons mark. **An owner decision, not a developer one**
        /// (Decision 027 reserves rights calls) — the CC mark in particular is
        /// often an uploader's claim about someone else's film.
        case strict

        var buckets: Set<String> {
            switch self {
            case .guaranteed:
                return ["safe_pd_age"]
            case .strict:
                return ["safe_pd_age", "safe_gov", "safe_archive_license", "safe_cc"]
            }
        }
    }

    /// The tier in force. `guaranteed` until the owner changes it.
    public static let tier: Tier = .guaranteed

    /// Content types that are never broadcast, whatever their rights say:
    /// television (the spines have never passed the rights audit at all — the
    /// open owner decision in SCRATCHPAD) and commercials.
    static let forbiddenTypes: Set<String> = ["tv-series", "tv-episode", "tv-special", "commercial"]

    /// Why a film may not be broadcast, or nil when it may.
    ///
    /// The reason is USER-FACING. A disabled control with no explanation is
    /// the one outcome a viewer must never be left with (WATCH-TOGETHER §5),
    /// and "we cannot prove this one is clear" is a more honest thing to read
    /// than a greyed-out button.
    public static func refusal(rightsBucket: String?,
                               contentType: String?,
                               year: Int?,
                               tier: Tier = tier) -> String? {
        if let contentType, forbiddenTypes.contains(contentType) {
            return "Television and commercials are not offered for streaming — their rights have not been audited."
        }
        guard let rightsBucket, !rightsBucket.isEmpty else {
            // Schema 1, or a build that could not ask the audit. Refuse.
            return "This copy has no rights verdict in the catalog on this device, so it cannot be streamed. Updating the catalog may resolve it."
        }
        guard tier.buckets.contains(rightsBucket) else {
            return Self.explain(bucket: rightsBucket)
        }
        // `safe_pd_age` is an age claim, so the year has to be there and has
        // to agree. A bucket without a year is a bucket computed from a
        // release date the item no longer carries.
        if rightsBucket == "safe_pd_age", tier == .guaranteed {
            guard let year, year <= 1929 else {
                return "This film is cleared by age, but the catalog's year does not support it — so it is not offered for streaming."
            }
        }
        return nil
    }

    public static func canGoLive(rightsBucket: String?, contentType: String?, year: Int?) -> Bool {
        refusal(rightsBucket: rightsBucket, contentType: contentType, year: year) == nil
    }

    /// A sentence a host can act on, per verdict. Deliberately specific: "not
    /// allowed" teaches nothing, and the whole point of this feature is that
    /// the viewer learns how the public domain actually works (§2.1).
    static func explain(bucket: String) -> String {
        switch bucket {
        case "safe_gov":
            return "This is a government work, which is free of copyright in the US but may carry other restrictions abroad — it is not offered for streaming yet."
        case "safe_archive_license", "safe_cc":
            return "This copy's public-domain claim comes from its uploader, not from its age. Uploaders are often wrong about films they did not make, so it is not offered for streaming."
        case "presumed_pd":
            return "This film is probably in the public domain but nothing proves it, so it is not offered for streaming."
        case "renewal_zone", "renewal_zone_footprint":
            return "Films published between 1964 and 1977 had their copyrights renewed automatically. This one is not offered for streaming."
        case "modern_copyright_unconfirmed", "modern_copyright":
            return "This film is still under copyright. Streaming it would put your channel at risk."
        case "wrongmatch_title", "wrongmatch_idyear":
            return "The catalog's identity for this copy is in doubt, so its rights cannot be judged — it is not offered for streaming."
        case "uploader_copyright_claim":
            return "The uploader's own description claims copyright on this film, so it is not offered for streaming."
        case "copyrighted_trailer", "excerpt":
            return "This is a fragment of a film that is still under copyright, so it is not offered for streaming."
        default:
            return "The rights audit has not cleared this copy for streaming (\(bucket))."
        }
    }

    /// The one-line explanation of the rule itself, for the go-live sheet.
    /// A host who cannot find their film should learn WHY, not hunt.
    public static var policy: String {
        switch tier {
        case .guaranteed:
            return "Only films published before 1930 can be streamed — age is the one public-domain claim nobody can dispute, and a stream goes out under your own account."
        case .strict:
            return "Only films the rights audit has cleared can be streamed: published before 1930, a US government work, or carrying a verified public-domain licence."
        }
    }
}
