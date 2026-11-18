# Archive Watch — Decisions 171–175

Archived verbatim from DECISIONS.md (Decision 092).

## 171 — Top Rated ranks each title by the largest crowd that rated it, against that crowd's own average; every rating names its crowd
*Date: 2026-10-27*

Every title's rating comes from the largest crowd that rated it: IMDb's users
(films, and now the series TVmaze or `build_episode_wants` can name on IMDb),
archive.org's own reviewers (avgRating/numReviews), or, for a series nothing
counted rates, TVmaze, which publishes no vote count. Top Rated sorts on
`ratingRank` (`tools/best_rating.py`): that rating's distance above its own
crowd's average for the same kind of title, in standard deviations, times
v / (v + prior) (IMDb 100 votes, archive.org 5 reviews, TVmaze one half). It
is an `items` column, rides in each title's JSON blob, and is index column 19
(`ratingRank100`, schema 16); the index's `rating10` is IMDb's alone again.
`tools/enrich_tv_ratings.py` (tv-canonical, before reconcile) writes
`seriesImdbID`, `imdbRating` and `imdbVotes` onto each spine from TVmaze's
`externals.imdb` and OMDb, accepting only an id OMDb calls a series; a one-item
series card takes its upload's reviewers. A rating names its crowd wherever it
is shown: IMDb's keeps the platform's star (the word "IMDb" where the line is
text), TVmaze's says "TVmaze", archive.org's stays in the community row.

**Why**: the owner, 2026-10-27, told that TVmaze rates 48 of the 236 TVmaze
shows: *"Please make use of the best ratings available per content."* TVmaze
names the IMDb id of 200 of them; the first run rated 170 series from IMDb
(Fawlty Towers 8.8 from 112,538 votes) before OMDb's daily quota stopped it.
Measured on the catalog, the old Top Rated led feature films with *Der Vierte
kommt nicht* (9.2 from 13 votes); 1,036 of 7,655 rated features had fewer than
50 votes. Ephemeral films had 713 IMDb ratings among 9,132; archive.org's
reviewers rate 5,971. archive.org's reviewers average 3.7 stars (7.4 of 10)
where IMDb's average our films 6.0, so a raw comparison would put every
reviewed short above every IMDb-rated one; each crowd is measured against
itself. TMDb was measured and left out: of 57 sampled films with a TMDb id and
no IMDb rating, 31 had no TMDb votes and none had 20. The IMDb rating sits on
the series CARD as `imdbRating`/`imdbVotes`, because every rights rule that
reads votes is gated to film types (all 457 series cards bucket the same with
150,000 votes added).

**How to apply**: a new sort or shelf that means "best rated" orders by
`ratingRank` and never by a raw rating. A new rating source joins
`best_rating.candidates` with a prior and a test case in
`tools/test_best_rating.py`; it is never mixed in a client. Never show a rating
without its crowd unless it is IMDb's. A series' TVmaze number stays on its
spine and card, never in `rating10`.

**Consequences**: a series' IMDb votes now reach `_pop_score`, so television's
Popular order follows IMDb's audience too. Series ratings refresh every 30 days
from `shared/editorial/omdb_series_cache.json`, apart from the films' OMDb
cache so the weekly TV build and the daily film backfill never commit one file.

## 172 — An identity must fit the file it is on, a fragment is never recommended, and a copyright claim belongs to the film, not the copy
*Date: 2026-10-28*

A title search with no year adopts a film only on an exact title whose TMDb
runtime is within 25% of the file (`tmdb_lib.search_movie`,
`omdb_lib.plausible_identity`); a dated search never takes a film released
more than two years away. What a yearless search already took is cleared
(`remediate_catalog.clear_yearless_match`, verdict `cleared_yearless_runtime`,
the Decision 150 scrub) when the matched film's runtime contradicts the file
(under half or over twice, at least 10 minutes apart). A card that plays a
fragment of the film it names (`fragment_of`: under 60% of the film, or a
part-named file under a whole-film title) keeps its identity and is
`noRecommend` with the reason "fragment — 20 of 94 min". A copy sharing an
imdbID with a copy hidden for a copyright claim is hidden under that copy's
own bucket (`copyrightClaimFrom`), unless it is overridden, government, freely
licensed on evidence, or the film is on the public-domain-by-defect list.
Clusters of copies that disagree on an id are settled by evidence already in
the build, and only when another member offers a positive alternative.

**Why**: the owner, 2026-10-27, *"There is no reason to leave bad data rather
than investigating and fixing it,"* and the audit of 2026-10-28, which
measured on the live catalog: a 19-second `silence` wearing Scorsese's 2016
film, a 14-minute reel as *Evolution* (2001), `74Help` as *Help!* (1965) on
the New Arrivals shelf — 116 visible yearless matches cleared; ~1,107 visible
cards headlining on the whole film's votes while playing 20 of 94 minutes
(Nosferatu, Caligari); and Sunset Boulevard hidden in four English copies and
served as its Mexican release *El ocaso de una vida* on three Home shelves,
with Gilda and The Hidden Fortress the same — 40 visible copies hide.

**How to apply**: never let a title search fill identity without a check the
file can answer (runtime, year). A fragment comes back to recommendations by
evidence (`runtime_match_keep.json`), never by loosening the ratio. A wrong
copyright propagation is cleared in `copyright_evidence_overrides.json`.
Tests: `test_yearless_match_identity.py`, `test_copyright_sibling.py`,
`test_title_identity_evidence.py`, `test_merge_split_anchor.py`, each seen
failing under a deliberate break.

## 173 — The pipeline fails loudly: pipefail everywhere, nothing publishes from a cancelled or failed build, and a publish carries its deletions
*Date: 2026-10-28*

Every workflow sets `defaults: run: shell: bash` (pipefail), held by
`tools/check_workflow_gates.py`; a step that tolerates a failure says so with
`::warning::`. publish-db uploads only when not cancelled and the build
succeeded, after checking the manifest's byte counts and the inflated `.zz`'s
hash against `catalog.sqlite`; `build_sqlite` writes to `.tmp` and renames into
place. tv-canonical drops `tv_rights_removed.csv` ids when it writes spines
and commits only after the TV rights step succeeds. `catalog_release.publish`
re-reads the release stamp just before upload, gzips the bytes it parsed,
carries this run's deletions onto a newer catalog, refuses a run that removes
more than 15%, and skips an unchanged upload.

**Why**: no workflow had pipefail, so 38+ `python … | tee` steps were green
when their script crashed; a cancelled publish-db's `always()` upload raced a
`build_sqlite` still writing (run 40399715287), saved only by the manifest
being written last; and the weekly TV rebuild re-added ~600 rights-removed
episodes that only a later step removed, a step the designed build timeout
could skip while the commit still pushed (ENGINEERING-PROCESS §2).

**How to apply**: a new workflow inherits the bash default; a new publish step
uses `!cancelled()` and an explicit success condition, never `always()`.

## 174 — A cartoon of racist caricature is never recommended and always findable, on a record a reader can open or the title's own tags
*Date: 2026-10-28*

`remediate_catalog.racist_caricature` sets `noRecommend` (reason "racist
caricature — …", the Decision 149 mechanism) on a title named by a sourced list
in `shared/editorial/racist_caricature.json` (the Censored Eleven Warner Bros.
withdrew in 1968; Scrub Me Mama with a Boogie Beat, Little Black Sambo, Tokio
Jokio from their own articles; the Bosko and Inki series), or on an ANIMATION
item whose own TMDb keywords or archive.org subjects name racism, racial or
ethnic stereotype, blackface or the Censored Eleven. It leaves Party Play,
Cartoon Mode, Surprise, shelves, channels and More Like This, and stays in
Search, Detail and Browse. 73 visible cards on 2026-10-28.

**Why**: the owner, 2026-10-28: *"make it so that racist cartoons don't
continually show up on the party play and cartoon features of the surprise
surface"* — *"'scrub me mama with a boogie beat' has got to be the most racist
cartoon I've ever seen and it has shown up repeatedly."* That title carried no
tag in the catalog, so no rule over the data could have caught it: the worst
offenders are often the least described. Bare "banned" was measured and left
out: it also tags Betty Boop shorts cut for the Hays Code.

**How to apply**: add a title with a source a reader can open (`add`, a list,
or a `series` pattern), never on a hunch; exempt one in `not` with its reason.
A picker that chooses for the viewer must skip `noRecommend` (the web Party
Play now checks it as well as the pool builder). Uncertain cases left for the
owner: Cannibal Capers, Jungle Drums, Uncle Tom and Little Eva.

## 175 — A complete notice removes a title unless the file contradicts it; the file is read automatically, and a requester's name never reaches the repository
*Date: 2026-11-04*

Removal requests arrive by a form on `takedown.html`, by email to the DMCA agent
(DMCA-1083942, shared with Ear Drama) or from Google, and become cases in a
private D1 table. `takedown-check.yml` reads each file named: a burned-in logo, a
soundtrack on a silent film, and whether the claim names the title or one word
of it. A complete notice removes the title unless that evidence contradicts it;
a contradiction opens an issue the owner answers with `remove` or `keep`.
`takedowns.json` takes an item, one file or a whole series, and holds a date and
a case number only. Runbook: `docs/TAKEDOWNS.md`.

**Why**: the owner, on the first two notices (2026-11-04): *"If it is a copyright
work, we should remove it. We are a public domain streaming app"*, *"any piece of
content that we serve should be able to receive a request"*, *"We need to protect
folks privacy"*, and *"Manual review might be quite difficult."* The notices showed
why the file has to be read. Metadata cleared both. `Madame Dubarry`, a 1919 film,
was an ARTE broadcast with a logo and soundtrack that archive.org's record never
mentions, so the claim may have been sound. `Home Movie: 97390: Unidentified` was
claimed as "UNIDENTIFIED", a word match. The repository and Actions logs are public,
so `takedowns.json` could not keep the `from` field it was built with. Reading frames
for pixels that do not change scored ARTE's translucent logo 0; a gradient that
points the same way in every frame scored it 111, against 0 for ten clean films.

**How to apply**: never ask a requester for more than 17 U.S.C. 512(c)(3) does.
Decision 151's readable evidence is the bar for what WE hide unprompted, not for a
notice. A file that could not be read must not hold a removal back. Nothing a
requester wrote may reach the workflow's log or an issue, including the name of the
work. A new kind of served content needs a key in `takedown_lib.blocked` and a
control in `test_takedowns.py`. The soundtrack test belongs to a request; the owner
declined a catalog-wide scan. Tune the logo threshold against
`takedown_check.LOGO_MIN`'s measurements, never by a list of ids.
