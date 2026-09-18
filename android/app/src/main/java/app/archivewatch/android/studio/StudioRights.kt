package app.archivewatch.android.studio

// Which films may be broadcast to the world (docs/WATCH-TOGETHER.md §3.4) —
// the Kotlin port of `Studio/StudioRights.swift`, sentence for sentence.
//
// IT IS A PORT AND THE WORDING IS LOAD-BEARING. A wrong call here does not
// degrade a screen: it puts a real person's YouTube or Twitch channel at risk
// of a copyright strike. The tier is the same one the Roku Search feed already
// applies to films it advertises to a third party (Decision 113,
// `--tier guaranteed`) — only AGE cannot be argued.
//
// AND AN UNKNOWN VERDICT IS A NO. A device plays from a cached database and is
// not entitled to today's schema (`items.rightsBucket` arrived at schema 2).
// When the column is missing, or the value is null, this refuses — because the
// alternative is broadcasting a film whose rights nobody could read.

object StudioRights {

    /** Which rights verdicts may go live. The names are `audit_rights.bucket`'s. */
    enum class Tier(val buckets: Set<String>) {
        /** Pre-1930 by age alone. What the Roku feed ships. */
        GUARANTEED(setOf("safe_pd_age")),

        /**
         * Adds government collections, an archive.org licence, and a Creative
         * Commons mark. **An owner decision, not a developer one** (Decision
         * 027 reserves rights calls) — the CC mark in particular is often an
         * uploader's claim about someone else's film.
         */
        STRICT(setOf("safe_pd_age", "safe_gov", "safe_archive_license", "safe_cc")),
    }

    /** The tier in force. `GUARANTEED` until the owner changes it. */
    val tier: Tier = Tier.GUARANTEED

    /**
     * Content types that are never broadcast, whatever their rights say:
     * television (the spines have never passed the rights audit at all) and
     * commercials.
     */
    private val forbiddenTypes = setOf("tv-series", "tv-episode", "tv-special", "commercial")

    /**
     * Why a film may not be broadcast, or null when it may.
     *
     * The reason is USER-FACING. A disabled control with no explanation is the
     * one outcome a viewer must never be left with (§5), and "we cannot prove
     * this one is clear" is a more honest thing to read than a greyed-out
     * button.
     */
    fun refusal(
        rightsBucket: String?,
        contentType: String?,
        year: Int?,
        tier: Tier = StudioRights.tier,
    ): String? {
        if (contentType != null && contentType in forbiddenTypes) {
            return "Television and commercials are not offered for streaming — their rights have not been audited."
        }
        if (rightsBucket.isNullOrEmpty()) {
            // Schema 1, or a build that could not ask the audit. Refuse.
            return "This copy has no rights verdict in the catalog on this device, so it cannot be streamed. Updating the catalog may resolve it."
        }
        if (rightsBucket !in tier.buckets) return explain(rightsBucket)
        // `safe_pd_age` is an age claim, so the year has to be there and has to
        // agree. A bucket without a year is a bucket computed from a release
        // date the item no longer carries.
        if (rightsBucket == "safe_pd_age" && tier == Tier.GUARANTEED) {
            if (year == null || year > 1929) {
                return "This film is cleared by age, but the catalog's year does not support it — so it is not offered for streaming."
            }
        }
        return null
    }

    fun canGoLive(rightsBucket: String?, contentType: String?, year: Int?): Boolean =
        refusal(rightsBucket, contentType, year) == null

    /**
     * A sentence a host can act on, per verdict. Deliberately specific: "not
     * allowed" teaches nothing, and the whole point of this feature is that the
     * viewer learns how the public domain actually works (§2.1).
     */
    fun explain(bucket: String): String =
        when (bucket) {
            "safe_gov" ->
                "This is a government work, which is free of copyright in the US but may carry other restrictions abroad — it is not offered for streaming yet."
            "safe_archive_license", "safe_cc" ->
                "This copy's public-domain claim comes from its uploader, not from its age. Uploaders are often wrong about films they did not make, so it is not offered for streaming."
            "presumed_pd" ->
                "This film is probably in the public domain but nothing proves it, so it is not offered for streaming."
            "renewal_zone", "renewal_zone_bw", "renewal_zone_footprint" ->
                "Films published between 1964 and 1977 had their copyrights renewed automatically. This one is not offered for streaming."
            "renewal_zone_commercial" ->
                "This is an advertisement from the 1964–77 renewal era, whose copyright was renewed automatically. It is not offered for streaming."
            "renewed_copyright_classic" ->
                "This film's copyright was renewed, so it is still protected despite its age. It is not offered for streaming."
            "modern_copyright_unconfirmed", "modern_copyright" ->
                "This film is still under copyright. Streaming it would put your channel at risk."
            "modern_copyright_confirmed" ->
                "This film's copyright was confirmed against archive.org's own licence record. Streaming it would put your channel at risk."
            "modern_noyear_risk" ->
                "This copy carries no year, and everything else about it points to a modern film. It is not offered for streaming."
            "no_evidence" ->
                "Nothing in the catalog says when this film was published, so its rights cannot be judged. It is not offered for streaming."
            "unknown_year" ->
                "This film has no year on record, and age is the only public-domain claim the Studio accepts. It is not offered for streaming."
            "uploader_cannot_dedicate" ->
                "The uploader released this under a public-domain licence, but it is not their film to release. It is not offered for streaming."
            "wrongmatch_bw" ->
                "This copy looks older than the film it was matched to, so the catalog is not sure which film it is. It is not offered for streaming."
            "commercial_keep", "commercial_slop", "commercial_modern_risk" ->
                "Advertisements are not offered for streaming — their rights are held by the brands in them, not by the archive."
            "wrongmatch_title", "wrongmatch_idyear" ->
                "The catalog's identity for this copy is in doubt, so its rights cannot be judged — it is not offered for streaming."
            "uploader_copyright_claim" ->
                "The uploader's own description claims copyright on this film, so it is not offered for streaming."
            "copyrighted_trailer", "excerpt" ->
                "This is a fragment of a film that is still under copyright, so it is not offered for streaming."
            else ->
                "The rights audit has not cleared this copy for streaming ($bucket)."
        }

    /**
     * What the gate CANNOT protect a host from, told before they go live.
     * Researched 2026-09-17; both halves are documented by the platforms
     * themselves. See the Swift copy for the full citation — and
     * `tools/test_studio_rights_parity.py` keeps the two identical, because
     * this is exactly the kind of sentence that drifts.
     */
    val hostWarning: String =
        "Even a public-domain film can trip a platform's automatic copyright " +
        "match. YouTube may interrupt or end a live stream and warn your " +
        "channel, and it can do that even when the rights are clear. And a " +
        "silent film's modern recorded score may still be under copyright " +
        "even though the film is not. Archive Watch checks the film's age; " +
        "it cannot check a platform's matcher."

    /**
     * The one-line explanation of the rule itself, for the go-live surface.
     * A host who cannot find their film should learn WHY, not hunt.
     */
    val policy: String get() = when (tier) {
        Tier.GUARANTEED ->
            "Only films published before 1930 can be streamed — age is the one public-domain claim nobody can dispute, and a stream goes out under your own account."
        Tier.STRICT ->
            "Only films the rights audit has cleared can be streamed: published before 1930, a US government work, or carrying a verified public-domain licence."
    }
}
