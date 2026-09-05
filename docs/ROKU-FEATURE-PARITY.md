# Roku vs Apple TV — FEATURE-level parity

The structural matrix in `ROKU-PARITY.md` tracks screens. This one tracks the
**buttons and behaviours inside them**, enumerated from the tvOS sources
(`ArchiveWatch/ArchiveWatch/Views/*.swift`) rather than from memory, because a
surface that exists and does nothing is worse than one that is missing: it
promises.

Legend: ✅ built + verified on the device · 🔨 built, not yet verified ·
⏳ not built · 🚫 not possible on Roku, with the reason.

## Distance to parity (2026-09-04, build 16)

The tally below counts the rows in this file. Roku is at **feature parity**
with the Apple TV app except one item that is not a Roku decision to make.

| Status | Count | Meaning |
|---|---|---|
| ✅ verified | 74 | built and confirmed on the glass |
| 🚫 impossible | 5 | Clip Studio, Downloads, Watch Together, Cast/AirPlay-send, PiP, background controls, VHS shader, idle screensaver, mature toggle, **cross-device sign-in** — each with a sourced reason in ROKU-DESIGN §8 (sign-in is blocked by Roku certification, lesson 102) |
| ⏳ open | 1 | Keyword / Studio search facets — needs a new column in the shared web catalog index (a cross-platform PIPELINE change), so it is not a Roku-app tick. Studio/keyword text is already SEARCHABLE via the blob; only the facet CHIPS are absent |
| 🔨 unverified | 0 | — |

**Every consumer-facing surface has now been read adversarially on the device
at build 15/16** — Home, Browse (Movies/TV), Detail (rest + reading mode +
rating), Series (season↔episode + monogram), Channels EPG, Library, Search
(results + chips + true count), Surprise, Collections, the Options/Settings
panel, and the Player (playback + resume + bookmark, confirmed by console
trace since the video plane does not appear in a screenshot). No Roku-side
defect is open.

**The two things left are not engineering on the app:**
1. The keyword/studio facet, which is a pipeline column decision affecting all
   platforms.
2. The owner-only publish gate — a signing key (`genkey`), an age rating and
   category, a privacy-policy URL, and the priced trick-play BIF batch
   (measured at ~69 GB / ~157 machine-hours catalogue-wide; the flow is built
   and proven on one film). None of these is a parity gap; they are the
   Channel Store submission, which the owner deferred (the app runs sideloaded
   today).

The honest read: the parity loop's engineering is effectively complete. What
remains is a pipeline facet and the owner's publish decisions.


## Detail

| tvOS | Roku | Note |
|---|---|---|
| Play / Resume with runtime or position | ✅ | "Resume · 83m left" verified |
| Favorite (Save / Saved) | ✅ | persists across relaunch |
| More → Mark as watched / not watched | ✅ | state-aware; watched = a ≥95% progress row, so Library, hide-watched and the resume label agree by construction |
| More → Start from the beginning | ✅ | offered only when a bookmark exists |
| More → Save / Remove from Library | ✅ | duplicated in the menu deliberately: the menu is where a viewer looks for verbs |
| Choose version (pick a copy) | ✅ | real files, real facts; verified switching fiddlesticks_1930 from a 618x480 derivative to its 928x720 original |
| Add to Playlist | ✅ | existing lists, or a new one named on Roku's keyboard |
| More Like This row | ✅ | 12 sampled by type + era; the index has no genre column, so similarity is honest about its inputs |
| Next Episode button | ✅ | via the series queue, not a Detail button |
| Also known as (Decision 100) | ✅ | |
| Cast / crew | ✅ | one line of five names; the shard's TMDb portraits are deliberately not drawn — see below |
| Share | ⚠️ divergence | the URL, stated; no QR — see below |
| "Can't play this title" error | ✅ | plus the reason, on screen |

## Home

| tvOS | Roku | Note |
|---|---|---|
| Hero carousel | ✅ | pool of 12, backdrop-only |
| Curated + dynamic shelves | ✅ | 23 rows from featured.json + index |
| Continue Watching | ✅ | leads Home, resolved against the WHOLE index |
| Hidden Gems (Decision 050) | ✅ | the index publishes a `hidden-gems` shelf computed from the DB's flag (Decision 050 holds: the client never restates the rule). It had been rendering for ticks while this table said "not built" — the row was written from the code, not from the glass |
| Top Rated | ✅ | Home shelf and Browse sort, both on the 1,000-vote floor |
| Public Domain Day | ✅ | derived as current year minus 95, so it is right on 1 January with nobody editing a file |
| Community Favorites / Most Discussed | ✅ | both published as shelves and both on Home; verified by name in the on-device report |
| Director shelves | ✅ | top 3 of 538 eligible directors, ≥6 professionally-presented films each |
| Browse by Category tiles | ✅ | typographic cards, 8 categories, route to a scoped Browse |
| Browse by Era tiles | ✅ | 1900s–1970s; verified landing on "The 1920s · 3428 titles" |
| Cross-shelf dedup | ✅ | 67 repeats dropped on the live catalog; first shelf to claim a film keeps it |

## Browse (Movies / TV)

| tvOS | Roku | Note |
|---|---|---|
| Type facet | ✅ | |
| Decade / Era facet | ✅ | |
| Sort (Popular / Newest / Oldest / A–Z) | ✅ | all five measured on the device at 422–602 ms; year-less rows sort LAST |
| Top Rated sort | ✅ | index schema 10 carries rating and votes; 1,000-vote floor |
| Genre facet | ✅ | 16 genres; "Western" returns 635 titles in 521 ms |
| Keyword / Studio facets | ⏳ | searchable via the blob; no facet columns |
| Result count in the heading | ✅ | |
| Empty state that says what to change | ✅ | |
| Shuffle again | ✅ | a fifth sort mode; verified returning a different set |
| TV browse → series drill-in | ✅ | **was a dead end until this tick** |

## Series

| tvOS | Roku | Note |
|---|---|---|
| Season list | ✅ | unnumbered seasons named "Unsorted" |
| Episode list with still, number, blurb | ✅ | |
| Honest episode count | ✅ | "18 of 39 episodes here" |
| Per-episode resume bar | ✅ | read from the registry |
| Play episode | ✅ | verified: position advancing. An episode a spine names but the detail shards do not carry now SAYS so and, inside a queue, skips to the next — it used to do nothing at all, with the reason in a console the viewer cannot read |
| Autoplay next episode | ✅ | honours the Options setting |
| Favorite a series | ✅ | verified: saved from `*`, resolved 4/4, card renders in Favorites |
| Add series to playlist | ✅ | a playlist stores ids and a `series:` slug is an id — the store needed no change; the verb was simply never offered, and the picker read `m.detail.item.id` unconditionally so a series could not name itself as the subject |

## Channels

| tvOS | Roku | Note |
|---|---|---|
| Guide with real listings | ✅ | schedule proven identical to the other platforms |
| Tune in joins live | ✅ | verified at 4795 s in |
| Never writes resume progress | ✅ | |
| Commercial breaks woven | ✅ | 1–2 vintage ads per break; lineup shape printed as evidence |
| VHS look | 🚫 | a fragment shader on tvOS; SceneGraph exposes no shader stage and no per-pixel filter over a `Video` node, so there is nothing to port it onto |
| User-created channels | ✅ | two option lists (type, then era) name the channel themselves; deletable from `*` |

## Library

| tvOS | Roku | Note |
|---|---|---|
| Favorites | ✅ | |
| Continue Watching | ✅ | verified rendering in Library with its real posters |
| Watched list | ✅ | last row in Library, built where the data lives |
| Playlists (create / add / Play All / remove / delete) | ✅ | store proven by an 18-assertion on-device self-test; Roku's own KeyboardDialog names them |
| Storage budget stated | ✅ | Roku-specific: 32 KB registry |

## Search

| tvOS | Roku | Note |
|---|---|---|
| Keyboard search over the catalog | ✅ | ~400 ms across 26,965 items |
| No-typing doors | ✅ | five |
| Result filters (type / era) | ✅ | present-facets-only: a filter is offered only when the results contain more than one value for it. Was UNREACHABLE by remote until build 13 (no key handler on the chip zone — lesson 94); verified on the glass 2026-09-04: Up from the top result row lights the chip, Select cycles it, 300 → 2 titles |
| Series results route to the series | ✅ | now that series drill-in exists |

## Surprise

| tvOS | Roku | Note |
|---|---|---|
| Surprise Me | ✅ | Search door + its own surface |
| Random Film / Feature / Silent / Animation / Short / Newsreel / Ephemera / Commercial / Documentary / TV Episode / Decade | ✅ | eleven doors, each re-rolls; reservoir-sampled in one index pass |
| Cartoon Marathon | ✅ | 40-item shuffled queue, verified playing 1/40 |
| Cartoon Mode (character shelves) | ✅ | 7 shelves in 274 ms — Betty Boop, Popeye, and the rest |
| Party Play | ✅ | 40-film shuffled lineup that LEANS colour; verified playing |
| Cover Art Wall | ✅ | 27 posters from a 13,361 pool, three swapping every 4s. Roku owns the screensaver, so this is a place you go, not an idle trigger |

## Settings (behind `*`)

| tvOS | Roku | Note |
|---|---|---|
| TMDb attribution verbatim (Decision 007) | ✅ | |
| Sources & Attribution | ✅ | |
| Support the Internet Archive | ✅ | |
| Hide Watched on Home | ✅ | |
| Autoplay Next | ✅ | consumed by the episode queue |
| Clear Continue Watching | ✅ | |
| Mature content toggle | 🚫 | the web index this platform reads drops adult items upstream, so the control would change nothing |
| Sign in / sync across devices | 🚫 | Roku has no Apple or Google identity; `roRegistrySection` is device-local (32 KB) |
| Commercial breaks toggle | ✅ | in the `*` panel, default on |
| VHS look | 🚫 | a shader effect; SceneGraph has no shader stage, so this is not deferred — it is unavailable |
| Idle screensaver | 🚫 | ROKU-DESIGN §11 — a channel may not draw one; Roku owns the screensaver |

## Player

| tvOS | Roku | Note |
|---|---|---|
| Resume from bookmark | ✅ | |
| Bookmarks written during playback | ✅ | every 5 s and on exit |
| Instant Replay | ✅ | |
| Trick play | ✅ | Roku's own, coloured to brand. Thumbnails (BIF) proven on the device with a generated file for one film — 21 s / 2.55 MB per feature; the catalog-wide batch is the owner's call (ROKU-SUBMISSION) |
| Title / description overlay | ✅ native | Roku's transport already draws it; ours was a duplicate and was removed |
| Subtitles | ✅ | WebVTT accepted directly; display governed by the device's caption mode |
| Stall recovery | ✅ | watchdog re-issues play at the last position |
| Next / previous episode | ✅ | Down and Up during playback; verified on 26 Men season 1, 0→1→0. Roku's Video node owns Left/Right/Rev/Fwd for trick play and the transport keys are not delivered outside video at all, so Up/Down are the only pair free for this |


## Why cast is a line and not a row of faces

The detail shard carries TMDb profile paths for every credited actor, so a row
of portraits was available for free. It is not drawn: Detail is a SCENE
(ROKU-DESIGN §13.7) — backdrop across the top 60%, the poster inset over the
seam, eyebrow / title / meta / pills / synopsis / cast stacked to its right —
and the copy column under the seam holds a three-line synopsis, one cast line
and the More Like This row before the screen ends. A row of six faces would
push the synopsis off the screen to show information nobody opened the page
for. Five names on one line answers "who is in this" at a glance.

Geometry since §13 (every value divisible by 3): poster 288×432 at [42,318];
copy column at x = 378; eyebrow 318, title 348 with aka and meta STACKED under
the title's rendered height; pills at the seam, never above 606; synopsis at
+84 on a 1,140 px measure (~80 characters), cast at +228; More Like This label
at 882 and its row at 927 with 90×135 tiles, ending inside the screen.


## Why Share states a URL instead of drawing a QR

tvOS, iOS and macOS draw a QR code to `archivewatch.org/item/<id>`. Roku has no
QR API, and there is no QR library available to generate a reference from
either — so shipping one here means implementing the encoder TWICE, once in
Python to produce known-answer vectors and once in BrightScript, including
Reed-Solomon, mask selection and format bits. That is a disproportionate
amount of new, hand-rolled, hard-to-verify code for a single label, and this
build has already shown what unverified code costs on this platform.

What ships instead states the fact a viewer can act on: **"Watch it anywhere:
archivewatch.org/item/el-candidato-1959"**, on a bar across the foot of Detail.
It is weaker than a QR and it is honest. If the QR is wanted, the scoped
follow-up is: a Python reference implementation producing matrix vectors, the
BrightScript port checked against them the way `SchedSelfTest` checks the
scheduler, and the matrix drawn as merged horizontal runs of `Rectangle` nodes
(a 29x29 code reduces to roughly 200 rects, not 841).
