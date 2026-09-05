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
| F4 | No archive.org metadata (reviews, favorites) on Roku | ⏳ | tvOS has CommunityDetailSection; Roku Detail has none |
| F5 | "Watch on another device" shows a long link; where is the QR? | ⏳ | no QR API on Roku; encode one in BrightScript → PNG in tmp:/ |
| F6 | Resume buttons malformed — text outside the pill | ✅ | pills re-measured on every label change; "Resume · 91m left" verified inside its pill |
| F7 | Left on Detail should reach the sidebar | ✅ | Detail raises `exitLeft`; trace `AWFOCUS rail` after Left from Play |
| F8 | Back should return to where you were, not the top of Home | ✅ | Home keeps the row/tile on Back from Detail (trace `AWHERO zone=rows` + `AWTILE focus 1,1` restored); a grid opened from a Surprise door, Home tile or collection card returns THERE; a series opened from Browse returns to the grid; Home from the rail goes to the top |
| F9 | Filter chips cycle; should open a designed picker; pills mis-sized | ✅ | a chip opens the options panel ON its current value (§6.3 "a chip opens a dialog"); verified "Sort by" → Oldest applied, "Genre" → Animation applied; pills fit their value |
| F10 | Grid titles hidden until focused and ellipsized; always show, never abbreviate | ✅ | captions visible at rest on Browse/Search grids and Home rows, wrap to 3 lines, no ellipsis; verified on the glass |
| F11 | Missing posters still frequent; never a blank graphic | 🔨 | Browse/Search grid tiles now draw the designed title card (accent rule + name) when art is missing or fails, as Home tiles do; Home/hero/random/More Like This/collection cards require professional art. Still to audit: Library rows + Continue Watching with an art-less episode |
| F12 | More Like This non-functional, tiny rectangles; Down only highlights the synopsis | ✅ | More Like This is a full PosterTile shelf with its own row label; Down slides the page up so the shelf sits at the heading line (the tvOS scroll), Up returns; the synopsis stop is gone — a cut synopsis is read from More → "Read the full synopsis". Verified on the glass |
| F13 | Blurred background is a pixelated bad crop; represent the film better | ✅ | blur cache-bust (`?aw=blur`) forces a tiny decode on every host; archive-cover item verified as a soft wash, not a crop |
| F14 | Filters should reset when switching Movies → TV | ✅ | decade/genre/sort reset on scope change; trace `type=tv-series decade= 0` after Movies→TV |
| F15 | Channels is not a TV-guide grid; selecting non-current items does nothing | ⏳ | build the proportional EPG (tvOS ChannelScheduler shape) |
| F16 | Collections duplicates Home; Apple TV shows curated collections | ✅ | Collections is a two-column grid of curated CARDS (3-poster montage, accent, count, Fraunces title, blurb — the tvOS CollectionsView); a card opens the collection as a Browse grid; Back returns to the cards. Verified |
| F17 | Party Play broken; Random Film returns TV; Surprise bottom rows unreachable | ✅ | 12 doors, 4 rows, all on screen; Random Film = a feature (trace `random type=feature-film`); Random TV Series opens a show; Party Play is an EPHEMERAL, MUTED lineup (trace `ephemeral=true`, zero `AWPLAY bookmark` lines) that returns to Surprise on Back; Cartoon Marathon moved to `*` on Cartoon Mode |
| F18 | Hero never changes between launches | ✅ | hero pool shuffled per launch; two launches led with different films (trace) |
| F19 | Search "start here" pills poorly sized | ✅ | doors fit their labels — "Feature Films", "Classic TV", "Silent Era", "Animation", "Surprise Me" verified |
| F20 | Search titles only when focused; adult films in search with no filter | 🔨 | titles ✅. Adult: measured on the glass — "stripper" returns 42 stag reels. archive.org tags them as SUBJECTS ("Stripper - Strippers - Stag - Burlesque", "fetishism; grind house"), so `remediate_catalog.is_adult_signal` gained a subject-tier rule (+ 3 curated titles), tested 8/8 incl. "The Stripper" 1963 and "Stagecoach" NOT flagged. Lands in the index at the next publish-db; Roku has no adult column and shows what the index serves (§8.3 upstream-only, as web) |

## Order of work
Visible-and-fast first (F1 F2 F6 F7 F13 F14 F18 F19 F10/F20-titles), then the
structural ones (F12 F9 F16 F17 F8 F11 F3), then the large builds (F15 EPG, F4
archive metadata, F5 QR). Every row flips to ✅ only with a device screenshot
read adversarially plus a console trace.
