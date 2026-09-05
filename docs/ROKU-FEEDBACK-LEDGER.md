# Roku — owner feedback ledger (2026-09-05)

Twenty items from the owner after using the Roku build. Each is binding until
its row reads ✅ with on-device evidence. This ledger SUPERSEDES the 2026-09-04
"distance to parity" assessment in ROKU-FEATURE-PARITY.md, which counted
surfaces that existed rather than surfaces that were finished.

| # | Feedback (owner's words, abridged) | Status | Notes / evidence |
|---|---|---|---|
| F1 | Too many animated titles in the hero row; at most one | ✅ | hero pool capped at ONE `animation` (trace: `AWHERO pool kinds=` shows exactly one per launch) |
| F2 | Shelves with 4–5 items; no shelf below a full row | ✅ | shelf floor raised to 7 (a full visible row); Continue Watching/Favorites are the viewer's own rows and may be short |
| F3 | The same shelves should appear across all platforms | ⏳ | audit Roku Home shelf set vs tvOS/Android from featured.json |
| F4 | No archive.org metadata (reviews, favorites) on Roku | ⏳ | tvOS has CommunityDetailSection; Roku Detail has none |
| F5 | "Watch on another device" shows a long link; where is the QR? | ⏳ | no QR API on Roku; encode one in BrightScript → PNG in tmp:/ |
| F6 | Resume buttons malformed — text outside the pill | ✅ | pills re-measured on every label change; "Resume · 91m left" verified inside its pill |
| F7 | Left on Detail should reach the sidebar | ✅ | Detail raises `exitLeft`; trace `AWFOCUS rail` after Left from Play |
| F8 | Back should return to where you were, not the top of Home | ⏳ | per-screen focus/scroll memory on return |
| F9 | Filter chips cycle; should open a designed picker; pills mis-sized | 🔨 | SIZING done — chips fit their value via the Button's rendered width (Timer + boundingRect), verified "Feature Film · Any decade · Any genre · Most popular"; the PICKER (select from a list instead of cycling) is still open |
| F10 | Grid titles hidden until focused and ellipsized; always show, never abbreviate | ✅ | captions visible at rest on Browse/Search grids and Home rows, wrap to 3 lines, no ellipsis; verified on the glass |
| F11 | Missing posters still frequent; never a blank graphic | ⏳ | audit every tile type's fallback + loading state |
| F12 | More Like This non-functional, tiny rectangles; Down only highlights the synopsis | ⏳ | MiniTile 144px strip → a real poster shelf |
| F13 | Blurred background is a pixelated bad crop; represent the film better | ✅ | blur cache-bust (`?aw=blur`) forces a tiny decode on every host; archive-cover item verified as a soft wash, not a crop |
| F14 | Filters should reset when switching Movies → TV | ✅ | decade/genre/sort reset on scope change; trace `type=tv-series decade= 0` after Movies→TV |
| F15 | Channels is not a TV-guide grid; selecting non-current items does nothing | ⏳ | build the proportional EPG (tvOS ChannelScheduler shape) |
| F16 | Collections duplicates Home; Apple TV shows curated collections | ⏳ | curated collection cards → grid (CollectionMetadata) |
| F17 | Party Play broken; Random Film returns TV; Surprise bottom rows unreachable | ⏳ | type-strict doors; grid scroll extent |
| F18 | Hero never changes between launches | ✅ | hero pool shuffled per launch; two launches led with different films (trace) |
| F19 | Search "start here" pills poorly sized | ✅ | doors fit their labels — "Feature Films", "Classic TV", "Silent Era", "Animation", "Surprise Me" verified |
| F20 | Search titles only when focused; adult films in search with no filter | ⏳ | titles (F10); trace the adult leak to the index/blob |

## Order of work
Visible-and-fast first (F1 F2 F6 F7 F13 F14 F18 F19 F10/F20-titles), then the
structural ones (F12 F9 F16 F17 F8 F11 F3), then the large builds (F15 EPG, F4
archive metadata, F5 QR). Every row flips to ✅ only with a device screenshot
read adversarially plus a console trace.
