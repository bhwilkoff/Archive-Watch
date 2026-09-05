# Roku — owner feedback ledger (2026-09-05)

Twenty items from the owner after using the Roku build. Each is binding until
its row reads ✅ with on-device evidence. This ledger SUPERSEDES the 2026-09-04
"distance to parity" assessment in ROKU-FEATURE-PARITY.md, which counted
surfaces that existed rather than surfaces that were finished.

| # | Feedback (owner's words, abridged) | Status | Notes / evidence |
|---|---|---|---|
| F1 | Too many animated titles in the hero row; at most one | ✅ | hero pool capped at ONE `animation` (trace: `AWHERO pool kinds=` shows exactly one per launch) |
| F2 | Shelves with 4–5 items; no shelf below a full row | ✅ | shelf floor raised to 7 (a full visible row); Continue Watching/Favorites are the viewer's own rows and may be short |
| F3 | The same shelves should appear across all platforms | 🔨 | Roku Home = featured.json shelves (same order/titles as every platform) + Top Rated + Public Domain Day + director shelves. NOT buildable from the web index: Hidden Gems (needs popularity), Watching Now / Community Favorites / Most Discussed (community signals) — an index column each; pipeline follow-up |
| F4 | No archive.org metadata (reviews, favorites) on Roku | ✅ | Detail carries "From archive.org viewers": the stats line (★ rating · views · favorites) and up to six review cards (stars, title, body capped at six lines, byline; Select opens a long one), the tvOS CommunityDetailSection, as a third zone below More Like This on the scrolling page. Verified on Murder on Flight 502 (4 reviews) |
| F5 | "Watch on another device" shows a long link; where is the QR? | ✅ | a QR encoder in BrightScript (QR.brs: byte mode, EC L, v1–10, Reed-Solomon, mask penalty, PNG written to tmp:/) behind More → "Watch this on another device": a share card with the code, title and URL. PROVEN: the device matrix matched the python reference cell for cell and OpenCV decoded a screenshot to the exact URL. Two BrightScript traps on the way: `rem` is the comment keyword; a nested for-each over one array shares its enumerator |
| F6 | Resume buttons malformed — text outside the pill | ✅ | pills re-measured on every label change; "Resume · 91m left" verified inside its pill |
| F7 | Left on Detail should reach the sidebar | ✅ | Detail raises `exitLeft`; trace `AWFOCUS rail` after Left from Play |
| F8 | Back should return to where you were, not the top of Home | ✅ | Home keeps the row/tile on Back from Detail (trace `AWHERO zone=rows` + `AWTILE focus 1,1` restored); a grid opened from a Surprise door, Home tile or collection card returns THERE; a series opened from Browse returns to the grid; Home from the rail goes to the top |
| F9 | Filter chips cycle; should open a designed picker; pills mis-sized | ✅ | a chip opens the options panel ON its current value (§6.3 "a chip opens a dialog"); verified "Sort by" → Oldest applied, "Genre" → Animation applied; pills fit their value |
| F10 | Grid titles hidden until focused and ellipsized; always show, never abbreviate | ✅ | captions visible at rest on Browse/Search grids and Home rows, wrap to 3 lines, no ellipsis; verified on the glass |
| F11 | Missing posters still frequent; never a blank graphic | 🔨 | Browse/Search grid tiles now draw the designed title card (accent rule + name) when art is missing or fails, as Home tiles do; Home/hero/random/More Like This/collection cards require professional art. Still to audit: Library rows + Continue Watching with an art-less episode |
| F12 | More Like This non-functional, tiny rectangles; Down only highlights the synopsis | ✅ | More Like This is a full PosterTile shelf with its own row label; Down slides the page up so the shelf sits at the heading line (the tvOS scroll), Up returns; the synopsis stop is gone — a cut synopsis is read from More → "Read the full synopsis". Verified on the glass |
| F13 | Blurred background is a pixelated bad crop; represent the film better | ✅ | blur cache-bust (`?aw=blur`) forces a tiny decode on every host; archive-cover item verified as a soft wash, not a crop |
| F14 | Filters should reset when switching Movies → TV | ✅ | decade/genre/sort reset on scope change; trace `type=tv-series decade= 0` after Movies→TV |
| F15 | Channels is not a TV-guide grid; selecting non-current items does nothing | ✅ | Channels is a proportional EPG: a time ruler (NOW + half-hour ticks), one row per channel with a name cell, programme blocks sized to their minutes, a now-line, a focused block that fills with the channel accent and grows to a readable width, Up/Down landing on the programme on air at the same time, Right past the last block paging the window +90 min, vertical scroll. Rail cell or ON NOW block = tune in (joins in progress; trace `AWCH lineup 29 items`), a later block = its Detail. Verified on the glass |
| F16 | Collections duplicates Home; Apple TV shows curated collections | ✅ | Collections is a two-column grid of curated CARDS (3-poster montage, accent, count, Fraunces title, blurb — the tvOS CollectionsView); a card opens the collection as a Browse grid; Back returns to the cards. Verified |
| F17 | Party Play broken; Random Film returns TV; Surprise bottom rows unreachable | ✅ | 12 doors, 4 rows, all on screen; Random Film = a feature (trace `random type=feature-film`); Random TV Series opens a show; Party Play is an EPHEMERAL, MUTED lineup (trace `ephemeral=true`, zero `AWPLAY bookmark` lines) that returns to Surprise on Back; Cartoon Marathon moved to `*` on Cartoon Mode |
| F18 | Hero never changes between launches | ✅ | hero pool shuffled per launch; two launches led with different films (trace) |
| F19 | Search "start here" pills poorly sized | ✅ | doors fit their labels — "Feature Films", "Classic TV", "Silent Era", "Animation", "Surprise Me" verified |
| F20 | Search titles only when focused; adult films in search with no filter | ✅ | titles always shown (F10). Adult: see F21 — the pipeline rule, verified on the device after the index refresh (42 stag reels → 0) |

## Owner additions (2026-09-05, mid-session)

| # | Feedback | Status | Notes / evidence |
|---|---|---|---|
| F21 | Adult films filtered out as a rule, as on every other platform | ✅ | Same rule as the apps and web: the pipeline's `isAdult`, which the index build drops. Two tiers added: subjects (strippers/stag/fetish/grind house/bdsm) and a title-START rule (`^strippers?` — thirteen Prelinger reels carry no subjects; "The Stripper" 1963 untouched). VERIFIED after two publish-db runs: the index holds 0 titles beginning with Stripper and the device's "stripper" search shows 11 legitimate films (Lady of Burlesque, The Crimson Kimono, Sunset Murder Case…) where it showed 42 stag reels |
| F22 | Hero text must not overlap when the title wraps to two lines | ✅ | the hero copy is anchored from the BOTTOM: meta keeps its line above the dots and a two-line title grows upward. Verified on "Les Aventures de Robinson Crusoé" (two lines, no overlap) |

## Order of work
Visible-and-fast first (F1 F2 F6 F7 F13 F14 F18 F19 F10/F20-titles), then the
structural ones (F12 F9 F16 F17 F8 F11 F3), then the large builds (F15 EPG, F4
archive metadata, F5 QR). Every row flips to ✅ only with a device screenshot
read adversarially plus a console trace.
