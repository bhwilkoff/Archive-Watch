# Archive Watch — Decisions 123–126 (archived verbatim)

> Moved from `DECISIONS.md` on 2026-09-20 when that file passed its ~50 KB
> ceiling. Append-only binds here too (Decision 092): these entries are moved,
> never edited.

## 123 — Pulse replaces the vendor consoles: every store is read by the route it actually offers, and a reading that cannot be trusted is refused rather than written
*Date: 2026-09-14*

Pulse is the one place the owner reads how the app is doing — seven views by
audience, a tab per platform, daily. Three rules bind it beyond Decision 108's:
**a store is read by the route it actually offers**, **a reading that is mostly
carried-forward is REFUSED rather than written**, and **absence is written,
never drawn as a zero**. Binding detail: `docs/PULSE-ANALYTICS.md`.

**Why**: the owner — *"The whole point of Pulse is that I never have to go into
the individual dashboards."* That is a higher bar than a summary page, and it
fails the moment one number is stale, one is invented, or one platform is
quietly missing. All three happened in a day.

**The route is the finding, every time.** Amazon publishes no acquisition
endpoint and no live-version endpoint — but for a FREE app every install is a
`$0.00 Charge` row in the SALES report, and an EDIT is seeded from the live
build, so both questions are answerable by asking something else. Roku
publishes no API at all and never will, and answers by DELIVERING its Looker
dashboards to an endpoint we already ran. Play's install export was called
broken and was merely lagging twice over. In each case the first answer —
"there is no API for that" — was our claim, not the vendor's.

**How to apply**: before recording that a vendor exposes nothing, ask what it
DOES expose and in what shape; Decision 109 started this list and every entry
since has been found the same way. Distinguish the vendor's error codes
precisely — Amazon's *"Report not found"* (real route, no data) versus
*"Unable to fetch the request scope"* (no such route) is the difference between
waiting and rebuilding. Never delete a vendor-side object you did not create:
the live-version reader creates an edit only when none exists, because an
existing one is somebody's in-flight submission.

**And guard the reading itself.** CI holds every credential and a laptop holds
a few, so a local `--apply` writes a mostly carried-forward file that silently
replaces fresher numbers — which is how macOS vanished from Reach hours after
being fixed. `HEALTH_OWNS` must name every key a reader writes or a dark reader
DELETES its section rather than preserving it. And a missing column must never
default to zero: Roku reported 0 installs for a platform with 112 because the
day's rows came from a different report.

**Consequences**: five stores now answer for themselves — Apple, Play, Amazon
and the web by API or counter, Roku by delivery — and each declares its own
route on the page, so "declared by hand" appears only where it is true. What no
route can reach is named on the page rather than omitted: Apple's retention and
session analytics 403 for this key, and Play withholds ratings below a minimum
audience.

## 124 — A checked source's synopsis always beats the uploader's, every synopsis carries its provenance, and the client SAYS it
*Date: 2026-09-16*

`tools/synopsis_provenance.py` gives every visible synopsis a `synopsisSource`
— `tmdb`, `omdb`, `wikipedia`, `tvmaze`, `agent-reviewed`, or `archive` (the
uploader's own description) — and REPLACES unstamped or uploader text with
TMDb's overview wherever the item has a `tmdbID`. Every client draws the
source under the synopsis: "Synopsis from TMDb", "Synopsis from Wikipedia",
or "Uploader's description on archive.org". Roku, whose Detail has no room
for a caption row, prefixes the uploader case in-line.

**Why**: the owner — "I continue to find descriptions and other metadata that
are not appropriate for the films... many instances of uploader information
and reviews instead of information about the film." Measured before the
change: 27,159 visible items carried a synopsis and **22,192 had no source
stamp** — archive.org's `description`, i.e. whatever the uploader typed.
6,304 of those matched uploader/review markers ("I've been researching newly
public domain films from 1929 and earlier, so I'm uploading the best
copies…" as the synopsis of *Devil May Care*; "The acting is still awful"
for *The Wild Women of Wongo*). **11,229 of them had a tmdbID**, so an
accurate overview had existed the whole time: the TMDb fillers were written
to fill EMPTY synopses only ("never overwrites") and did not stamp what they
wrote, so nothing downstream could tell TMDb's text from a reviewer's.

**How to apply**: never write a synopsis without a `synopsisSource`; a
writer that cannot name its source is writing the uploader's text and must
say `archive`. Prefer a checked source over the uploader whenever one
exists, and never overwrite a checked source with a lower one (the
precedence here is tmdb ≥ omdb ≥ wikipedia ≥ tvmaze over archive; the four
checked sources are left as they stand). Label every source on screen, not
only the weak one — a caption that appears only on bad records is a warning
nobody reads; one that appears on every record is provenance, which is the
learning-orientation answer (expose the structure, let the viewer weigh it).
The TMDb overviews are cached in `shared/editorial/tmdb_overview_cache.json`
(committed) so the rule costs no fetch on a rebuild.

**Consequences**: uploader-only text remains for the ~9,000 items with no
external id, labeled. The remaining unchecked fields are the next audit:
`director` and `cast` carried without any external id (1,139 / 758 visible
items, from the Archive `creator` field), `genres` inferred from subjects
(controlled vocabulary, not a source), and the canonical-title adoption that
Decision 123's sweep showed can hide a wrong match.

## 125 — Credits with no surviving id are residue unless the cast proves the film; and the same cast dates an upload-dated film
*Date: 2026-09-16*

`remediate_catalog.strip_unanchored_tmdb_residue` removes TMDb credit rows
(cast with `character` / `tmdbPersonID`, and the director, countries and
ratings that arrive in the same credits call), `metaSource = "tmdb"` fields
(writer, studios, release date, tagline, keywords...) and a `languageSource =
"tmdb"` language from any film item with NO surviving external id — UNLESS
`cast_residue_fixes` proves the credits are the film's own: three or more of
those names are the cast of a TMDb film carrying the item's own title
(article-insensitive, containment) within fifteen years. That same anchor
DATES the item: when its archive id names no year and its catalog year is
1978+ while the anchored film's is more than five years earlier, the film's
year is adopted (`yearSource: "cast-anchored-tmdb"`). Series cards and
anything with a tvmazeID/tvdbID are out of scope; a wikidataQID is an
identity, not a cast source, so Wikidata-only items ARE judged.
`tools/anchor_orphan_credits.py` grows the offline caches by TMDb title
search, keeping a film only when ≥3 cast names agree.

**Why**: the owner's audit — *"uploader information and reviews instead of
information about the film"* — reached the credits. Decision 087 clears a
wrong match's ids and artwork ONLY, on the correct ground that director and
cast can also come from the Archive item; the 2026-09-08 residue strip only
reaches items the verifier stamped. Measured 2026-09-16: **916 visible no-id
items carried TMDb credit rows.** A NetZero commercial reel titled "501" wore
the 2008 Danish film "501" entire — director, writer, studio, release date,
20 IMDb votes, Danish language, ten cast members with TMDb person ids — and
no marker of any kind. A Dragnet episode was credited to *The Big Bounce*
(2004, Owen Wilson), a War of 1812 newsreel to the 2011 PBS documentary,
Keaton's *Cops* to a 2016 Austrian film, a Michael Shayne episode to Mario
Bava, a 1956 Producers' Showcase to Omar Sy. And a `wikidataQID` had been
shielding the worst: *Godzilla* (1954) wore Aaron Taylor-Johnson, *The Fast
and the Furious* (1955) Paul Walker, *Panique* (1946) its 1977 remake.

The evidence is in the fields, not in a marker: `metaSource`/`languageSource`
`= "tmdb"` are written only against a tmdbID, and a cast row with `character`
can only be a TMDb credit. With every id gone, each describes the film the
match pointed at.

**The keep side cost more than the strip.** A first pass cleared 352 visible
items and ~40% of them were CORRECT credits with the id gone for an
unrelated reason — *All the Fine Young Cannibals*, *Cold Turkey* (1925), Night
of the Living Dead, *Three Ages* (Keaton, uploader-dated 2006). "No id" is not
evidence of a wrong film; the cast reverse-matched to a same-titled film IS
evidence of the right one. Three refinements, each from a false positive read
off the list: name-only votes (a `None` profile path broke the strict key,
160 items); article-insensitive containment ("The Werewolf of Washington" /
"Werewolf of Washington"; "Lady Snowblood 2: Love Song of Vengeance"); and a
15-year window, because *Die Sister, Die!* is 1972 AND 1978, *I Eat Your
Skin* 1964 and 1971 — same film, production vs release — while a remake is
decades away. Net: 269 visible items lose another film's credits; 6 pre-1961
features that the rights audit was about to hide as "confirmed modern" get
their real year instead.

**How to apply**: never judge residue by the presence of an id alone in
either direction — an id can be missing on a correct film and present on a
wrong one (Decision 026). When a rule clears, look for what it clears that
was RIGHT, and find the evidence that separates the two; here it was already
in the caches. Keep the two rules' thresholds distinct: the strict
(name, profile) vote at ≥2 CLEARS on a >5-year contradiction; the name-only
vote at ≥3 with a title agreement KEEPS. Do not restore a cleared tmdbID
from the anchor — a verifier removed it for a reason this rule does not
re-litigate; the credits stay, the id does not. Run `anchor_orphan_credits`
locally when the cleared count jumps: it is the only network step and it
writes nothing to the catalog.

**Consequences**: 19 items whose ONLY year evidence was a cleared match's
release date now fall to the owner's 09-11 `no_evidence` hide — among them
one copy of *L'Arrivée d'un train en gare de La Ciotat* — which is that
policy working on truer data, not a defect here. The rights confirm CANNOT
run from CI any longer (archive.org refuses the runner: 4/4 failed on each of
the last three days) and was run locally over its 116 stuck targets; a
follow-up is to move that step to the owner's Mac on a schedule.

## 126 — A request that must be answered rides its own field; a shared query record served once per bump merges whatever lands on it together
*Date: 2026-09-17*

The Roku channel's single-id lookup — what a deep link and Detail's index
fallback use — no longer goes through `CatalogService`'s query fields. It
has its own pair, `lookupId` / `lookupResult`, served from each event's own
data, and the answer names the id it is for so the Scene matches it to the
request it still holds. `qId` is gone.

**Why**: Roku certification failed the Search Beta channel (ticket 110523):
"The Content and search beta channel found, but it redirects to the
channel's home screen instead of playing the video" — The General, The Sky
Pilot, The Ten Commandments. Reproduced on the Streaming Stick 4K against
the store channel, the beta channel and the sideload:

    AWDEEP contentId=TheGeneral720p1926 mediaType=movie
    AWSVC query # 2 ... ids= 14 ... id=TheGeneral720p1926
    AWSVC resolveIds asked= 14 found= 11

`CatalogService` reads every `q*` field as ONE record and serves only the
newest `queryId` — by design, so a burst of keystrokes costs one scan. On a
cold start Continue Watching's `resolveIds` (`qIds`, 14 ids) and the queued
deep link (`qId`) both bump before the task attaches its observer; the task
runs the merged record once, `runQuery` dispatches the `qIds` branch first,
and the Scene's results handler — which checks `pendingUserItems` before
`pendingDeepLink` — hands the answer to the user-items branch. The deep
link is never answered. A device with no watch history has no `qIds` to
merge with, so the harness (fresh sideloads) never saw it, and the memory
"deep-link demo film TheGeneral720p1926 verified playing" was true on the
day it was written.

**How to apply**: coalescing is right for a *query* — the viewer only wants
the latest page — and wrong for a *request* that a specific caller is
waiting on. When a field on a shared service must be answered, give it its
own field and its own result, serve from `msg.GetData()` rather than the
field (two ids set back to back are two answers), and tag the answer with
what it answers so a stale one is ignored rather than misrouted. Do not fix
this by reordering the branches in `runQuery`: whichever branch runs, the
other request's `pending*` flag is left set and misroutes the next result.
And test deep links on a device WITH history — the empty-registry case is
the one that always passes.

**Consequences**: `roku/manifest` 1.0.75, packaged and uploaded to the beta
(881088, published) and the store (881015, App Behavior Analysis queued).
The feed's own "Submit for review" is disabled while its status is FEED
VALIDATED — that status means "undergoing deep-linking certification", so
the re-test is asked for on the ticket, not re-submitted in the Dashboard.
Verified on the glass before upload: three cold-start links on the Stick
with history present, one roInput link mid-film, and Hintertreppe on the
Roku 2 XD (legacy tier) — `media-player state=play` for each.

