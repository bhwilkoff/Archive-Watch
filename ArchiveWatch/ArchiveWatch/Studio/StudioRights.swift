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
        /// Public domain by age alone (`lastPublicDomainYear`). What the Roku feed ships.
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
            guard let year, year <= lastPublicDomainYear() else {
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
        // Not only government works: the bucket is _GOV_PD_COLLECTIONS,
        // which also holds Prelinger's sponsored films (Last Date, 1949).
        case "safe_gov":
            return "Public domain through its collection, not its age — not offered for streaming yet."
        case "safe_archive_license", "safe_cc":
            return "This copy's public-domain claim comes from its uploader, not from its age. Uploaders are often wrong about films they did not make, so it is not offered for streaming."
        case "presumed_pd":
            return "This film is probably in the public domain but nothing proves it, so it is not offered for streaming."
        case "renewal_zone", "renewal_zone_bw", "renewal_zone_footprint":
            return "Films published between 1964 and 1977 had their copyrights renewed automatically. This one is not offered for streaming."
        case "renewal_zone_commercial":
            return "This is an advertisement from the 1964–77 renewal era, whose copyright was renewed automatically. It is not offered for streaming."
        case "renewed_copyright_classic":
            return "This film's copyright was renewed, so it is still protected despite its age. It is not offered for streaming."
        case "modern_copyright_unconfirmed", "modern_copyright":
            return "This film is still under copyright. Streaming it would put your channel at risk."
        case "modern_copyright_confirmed":
            return "This film's copyright was confirmed against archive.org's own license record. Streaming it would put your channel at risk."
        case "modern_noyear_risk":
            return "This copy carries no year, and everything else about it points to a modern film. It is not offered for streaming."
        case "no_evidence":
            return "Nothing in the catalog says when this film was published, so its rights cannot be judged. It is not offered for streaming."
        case "unknown_year":
            return "This film has no year on record, and age is the only public-domain claim the Studio accepts. It is not offered for streaming."
        // Decision 140.
        case "uploader_licence_only":
            return "Only the uploader says this film is free to share, and nothing independent confirms it, so it is not offered for streaming."
        case "uploader_cannot_dedicate":
            return "The uploader released this under a public-domain license, but it is not their film to release. It is not offered for streaming."
        case "wrongmatch_bw":
            return "This copy looks older than the film it was matched to, so the catalog is not sure which film it is. It is not offered for streaming."
        case "commercial_keep", "commercial_slop", "commercial_modern_risk":
            return "Advertisements are not offered for streaming — their rights are held by the brands in them, not by the archive."
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

    /// What the gate CANNOT protect a host from, told before they go live.
    ///
    /// Researched 2026-09-17, and it is not a formality — both halves are
    /// documented by the platforms themselves:
    ///
    /// · YouTube's own copyright page: a live stream may be replaced by a
    ///   placeholder, interrupted or TERMINATED and the channel struck, and
    ///   "your live stream can be interrupted even if you've licensed the
    ///   third-party content" unless the rights holder has allowlisted your
    ///   channel. An automated matcher does not read our rights audit. A
    ///   creator running a "Public Domain Theater" was kicked off and warned
    ///   while streaming *His Girl Friday* — public domain for fifty years.
    ///
    /// · And the limit of our own gate: it clears a FILM by its age. It
    ///   cannot clear a particular COPY's modern recorded score or
    ///   restoration, and for silent cinema — which is the entire
    ///   `guaranteed` tier — a modern score is the norm rather than the
    ///   exception.
    ///
    /// Saying this before the first broadcast is the honest version of §2's
    /// learning orientation: the host learns how the system actually works
    /// instead of learning it from a strike.
    public static let hostWarning =
        "Even a public-domain film can trip a platform's automatic copyright "
        + "match. YouTube may interrupt or end a live stream and warn your "
        + "channel, and it can do that even when the rights are clear. And a "
        + "silent film's modern recorded score may still be under copyright "
        + "even though the film is not. Archive Watch checks the film's age; "
        + "it cannot check a platform's matcher."

    /// The one-line explanation of the rule itself, for the go-live sheet.
    /// A host who cannot find their film should learn WHY, not hunt.
    /// The newest publication year in the US public domain BY AGE. A work is
    /// protected for 95 years, through December 31 of year + 95, so it enters
    /// the public domain on January 1 of year + 96: 1930 films on 2026-01-01.
    /// This was the literal 1929 — two New Years stale, keeping every 1929
    /// and 1930 film (the first sound era) off the air. It follows the
    /// calendar now, as `tools/audit_rights.py` does.
    public static func lastPublicDomainYear(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.component(.year, from: now) - 96
    }

    public static var policy: String {
        switch tier {
        case .guaranteed:
            return "Only films published in \(lastPublicDomainYear()) or earlier can be streamed — age is the one public-domain claim nobody can dispute, and a stream goes out under your own account."
        case .strict:
            return "Only films the rights audit has cleared can be streamed: published in \(lastPublicDomainYear()) or earlier, from a government or public-domain archive collection, or carrying a verified public-domain license."
        }
    }
}
