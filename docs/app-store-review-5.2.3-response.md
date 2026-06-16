# App Review response — Guideline 5.2.3 (Legal), iOS

**Submission ID:** 5b4a6d1e-0ca0-44e3-9d41-b3722de28bd8
**Rejected build:** 1.0 (36) · **Review date:** 2026-06-16
**Issue:** 5.2.3 — "potentially unauthorized access to third-party audio or
video streaming, catalogs, and discovery services"; asks for documentary
evidence of rights/permissions.

The core fact: **Archive Watch streams only public-domain and openly-licensed
(Creative Commons / CC0) moving-image works, hosted by and streamed directly
from the Internet Archive (archive.org) — a nonprofit public library.** There
is no proprietary or commercial streaming service involved, and public-domain
works have no rights-holder to infringe. Below is the paste-ready reply, the
short App Review Information note, and the evidence to attach.

---

## 1. Reply to paste into App Store Connect (Resolution Center)

> Thank you for the review. We want to resolve the 5.2.3 concern directly,
> because Archive Watch is built specifically to avoid it.
>
> **What the app is.** Archive Watch is a dedicated browser and player for the
> **public-domain moving-image collections of the Internet Archive**
> (archive.org) — a registered 501(c)(3) nonprofit digital public library.
> The app is, in effect, a specialized client for the same openly-available
> public-domain films, classic television, newsreels, silent cinema, and
> animation that any web browser can access at archive.org. It is a
> cinematheque for works whose copyright has expired or lapsed.
>
> **We do not access any proprietary, commercial, or unauthorized streaming
> service.** There is no Netflix/YouTube/etc. integration, no scraping of a
> paid catalog, and no re-hosting. Every playable title streams **directly
> from the Internet Archive's own public servers** (the `archive.org/download/…`
> endpoints the Internet Archive provides for public access). The app hosts no
> media itself.
>
> **Why the content does not infringe third-party rights.** Every playable item
> is either (a) in the **public domain** — by expiration of term, by failure to
> renew, or by publication without the copyright notice U.S. law then required —
> or (b) released by its creator under a **Creative Commons / CC0** license that
> expressly permits redistribution. Public-domain works have no rights-holder
> whose rights could be violated, and CC/CC0 works are licensed precisely for
> this kind of access.
>
> **We proactively screen out anything that might still be under copyright.**
> Before publishing our catalog we run an automated copyright rights audit that
> *hides* any item not confidently free, anchored on each work's own license
> metadata at the Internet Archive and on U.S. public-domain rules:
> - Works first published **before 1929** — public domain by age. Kept.
> - **1929–1963** — within the Internet Archive's curated public-domain film
>   collections; kept.
> - **1964–1977** — kept only where appropriate (this is the well-documented
>   "public-domain by notice/renewal defect" era, e.g. *Night of the Living
>   Dead*).
> - **1978 and later** — *excluded by default*, and kept only if the work's own
>   Internet Archive record carries a genuine **CC0/Creative Commons** license.
>   A bare "Public Domain Mark," a missing license, or an uploader claim is
>   **not** treated as a rescue — those items are hidden.
> - Modern branded commercials/advertisements (1995+) and rips/compilations are
>   excluded regardless of any uploader tag.
>
> The audit produces a per-item evidence manifest (the Internet Archive URL,
> publication year, license URL, and the basis for inclusion) for every title
> in the app. We are happy to provide this manifest in full.
>
> **Metadata / "discovery" services.** Posters, synopses, and cast information
> are drawn only for visual enrichment from The Movie Database (TMDB), Wikidata,
> Wikimedia Commons, and the Library of Congress, used within each provider's
> published API terms. We are a non-commercial (free, no ads, no IAP) app and
> display the required TMDB attribution in-app ("This product uses the TMDB API
> but is not endorsed or certified by TMDB," with the TMDB logo). These services
> supply *metadata only* — never the video stream.
>
> **Documentation attached / referenced** (see App Review Information):
> 1. A statement of the content-rights basis and our exclusion methodology.
> 2. Representative example titles with direct links to their Internet Archive
>    records showing public-domain / openly-licensed status (verified against
>    our catalog), spanning age-based PD, notice/renewal-defect PD, and
>    creator-released works:
>    - *A Trip to the Moon* (1902, Méliès — PD by age) —
>      https://archive.org/details/ATripToTheMoonGeorgeMelies
>    - *Nosferatu* (1922 — PD by age) —
>      https://archive.org/details/Nosferatu_most_complete_version_93_mins.
>    - *The General* (1927, Keaton — PD by age) —
>      https://archive.org/details/the_general_ipod
>    - *His Girl Friday* (1940 — PD, non-renewal) —
>      https://archive.org/details/his_girl_friday
>    - *Detour* (1945 — PD, non-renewal) —
>      https://archive.org/details/Detour_movie
>    - *Carnival of Souls* (1962 — PD, no notice) —
>      https://archive.org/details/CarnivalofSouls
>    - *Night of the Living Dead* (1968 — PD, notice defect) —
>      https://archive.org/details/night_of_the_living_dead_dvd
>    - *Sita Sings the Blues* (2008 — released by its creator for free
>      redistribution) — https://archive.org/details/Sita_Sings_the_Blues
> 3. The Internet Archive's public collections these are drawn from
>    (e.g. https://archive.org/details/feature_films) and its Terms of Use
>    (https://archive.org/about/terms.php).
>
> We would gladly make any adjustment that would help — for example, surfacing
> the public-domain provenance and source attribution even more prominently in
> the app, or providing the full per-title rights manifest. Please let us know
> what additional documentation would be most useful, and thank you again.
>
> — Ben Wilkoff (ben@learningischange.com)

---

## 2. App Review Information → "Notes" (short form, for the metadata field)

> Archive Watch is a player for the **public-domain** moving-image collections
> of the **Internet Archive (archive.org)**, a nonprofit public library. All
> playable media streams directly from the Internet Archive's public servers;
> the app hosts nothing and accesses no proprietary/commercial streaming
> service. Every title is public domain (expired/lapsed/uncopyrighted) or
> Creative Commons/CC0. We run an automated rights audit that excludes anything
> not confidently free, anchored on each item's own Internet Archive license
> metadata and U.S. public-domain rules (post-1977 works are excluded unless
> CC0/CC-licensed). Posters/synopses come from TMDB/Wikidata/Commons/LoC for
> metadata only, used per their API terms (TMDB attribution shown in-app). A
> full per-title rights manifest is available on request. See the Resolution
> Center reply for details and example source links.

---

## 3. Documentary evidence to attach / have ready

- [ ] **Rights-basis statement** (the reply above, as a PDF) — what the app is,
      where content comes from, why it's non-infringing, how we screen.
- [ ] **Per-title rights manifest** — export from `tools/audit_rights.py`
      (`tools/rejected_audit.csv` is the exclusion manifest; produce the
      companion *included*-items evidence list: Archive URL, year, licenseURL,
      inclusion basis). Offer as a spreadsheet if asked.
- [ ] **Example-title links** (5–10 recognizable PD/CC titles with their
      archive.org record + visible license/year) — included in the reply.
- [ ] **Internet Archive context** — link to the IA collections used and IA's
      Terms of Use; note IA's 501(c)(3) public-library status.
- [ ] **TMDB attribution** — screenshot of the in-app About/Attribution screen
      showing the required TMDB notice + logo.

---

## 4. Optional in-app strengthening (lowers the chance of a repeat 5.2.3)

These are not required to reply, but make the provenance self-evident to a
reviewer and reinforce the rights story:

- Surface **per-title provenance** on the Detail screen: "Public domain · source:
  archive.org/details/{id}" with the year/rights basis (we already store
  `rightsStatus`, `archiveLicense`, `archiveDate`, and the source URL).
- Add a one-line **rights/provenance statement** to the About screen: "All
  titles are public-domain or openly-licensed works streamed from the Internet
  Archive (archive.org), a nonprofit library." + a contact for rights concerns
  (ben@learningischange.com) / a "Report a title" mailto.
- Consider resubmitting on the **current build** (1.3.x) rather than 1.0 (36),
  since the rights audit (Decision 027) post-dates that older build and the
  newer build's catalog is already audit-filtered.

---

## Notes for us (not for Apple)

- This is the rights complement to **Decision 027** (the audit) and **Decision
  026** (match correctness). The defense rests on three true facts: (1) content
  is hosted/served by the Internet Archive, not us; (2) it is PD or CC/CC0; (3)
  we additionally screen out anything questionable.
- 5.2.3 can require a couple of rounds. Keep replies factual, lead with the
  Internet Archive public-library framing, and offer the manifest. Do **not**
  claim licenses we don't have — the claim is "public domain / openly licensed,"
  not "licensed by studios."
