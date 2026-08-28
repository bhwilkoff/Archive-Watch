# iPhone 12 audit — every surface, every button, on older hardware

**Rig**: iPhone 12 (iPhone13,2, A14, iOS 26.5, 390×844pt, **notch not
island**), paired wirelessly (see the `google-tv-adb-harness` memory).
**Method**: `tools/ios_scenario.py` — cold launch with `AW_START_TAB` /
`AW_START_ITEM` / `--payload-url`, `devicectl capture screenshot`, Vision
OCR (`/tmp/awocr`, now emitting box WIDTH so clipping is measurable), and
XCUITest for anything behind a tap.

**Why this rig finds what the others cannot.** Every iOS screenshot in
this repo until now was taken on an iPhone 15 Pro (393pt) or a simulator.
Three points of width and a different top inset are enough to break a
layout that has always looked correct — and T1 below is exactly that
bug, shipped and invisible for as long as the action row has had seven
buttons.

**Verdict rule** (from `atv-external-observation-harness`): a row passes
when the GLASS says so. The app's own report is never the evidence.

Legend: `[x]` verified on device · `[!]` defect found · `[>]` fixed +
re-verified · `[ ]` not yet run.

---

## T1 — Layout integrity (the "no clipped text" ask)

| # | Surface | Result |
|---|---|---|
| 1.1 | Home — hero, category tiles, first shelf | `[x]` clean, 16pt insets correct |
| 1.2 | Browse — chips, facets, grid | `[x]` clean |
| 1.3 | Channels — EPG guide | `[x]` clean |
| 1.4 | Search — empty state | `[x]` clean |
| 1.5 | Library — tab bar, empty state | `[x]` clean |
| 1.6 | Surprise | `[x]` clean (the Detail it opens was 1.7) |
| 1.7 | **Detail — title / meta / synopsis / actions** | `[>]` **DEFECT, FIXED** — see below |
| 1.8 | Settings (top + scrolled) | `[x]` clean |
| 1.9 | Series Detail (season/episode) | `[ ]` |
| 1.10 | Collections | `[ ]` |
| 1.11 | Cartoon Mode | `[ ]` |
| 1.12 | Player + transport chrome | `[x]` clean, native AVKit HUD |
| 1.13 | Get Subtitles sheet | `[ ]` |
| 1.14 | Clip Studio | `[ ]` |
| 1.15 | Add-to-playlist sheet | `[ ]` |
| 1.16 | Home, scrolled to every shelf | `[x]` clean (5 screens) |

### 1.7 — Detail clipped every line of text on both edges `[>]`

**Measured**: title `His Girl Friday` drew as `-lis Girl Friday` (the H
sliced down its stem), `1940` as `940`, the synopsis cut on the left and
the right, the favourite button halved at x=0 and the share button
halved at x=390. Zero of this is visible on a 15 Pro.

**Root cause** — not the text, and not the hero. The action row is a
fixed `HStack` of **seven** `.bordered` buttons (favourite, playlist,
watched, subtitles, clip, versions, share): ~44pt each plus 12pt spacing
needs ~380pt against 358pt of content width. An overflowing HStack does
not clip itself — it makes the whole Detail **column** ~428pt wide, and a
vertical `ScrollView` centres an oversized column, so every line lost
~16pt off BOTH ends. The hero was the obvious suspect and was innocent:
its 2026-06-10 `.background` + `.clipped()` fix still holds.

**Fix**: `ViewThatFits(in: .horizontal)` — the plain row wherever it
fits, a horizontally scrolling row where it does not. Tightening the
spacing would have bought exactly one more action; this cannot overflow
at any count. The buttons live in one `actionButtons` property so the
two branches can never drift.

**Verified**: title back at x=15.4pt, `1940` whole, **0 edge lines**
where there were 11.

---

## T2 — Every control does something

Reached by XCUITest (real taps). A control passes when the tap produces
an observable change on the glass, never when it merely exists.

| # | Control | Result |
|---|---|---|
| 2.1 | Tab bar — all five tabs | `[x]` all five open and draw |
| 2.2 | Home shuffle → Surprise | `[x]` reached (deep link + toolbar) |
| 2.3 | Home gear → Settings | `[x]` opens |
| 2.4 | Category tile → filtered grid | `[x]` pushes a grid |
| 2.5 | Shelf poster → Detail | `[x]` via Detail tests |
| 2.6 | Detail: Play | `[x]` film starts |
| 2.7 | Detail: favourite (and it persists) | `[>]` worked; had NO a11y label — fixed |
| 2.8 | Detail: add to playlist | `[x]` sheet opens |
| 2.9 | Detail: watched toggle | `[x]` labelled + flips |
| 2.10 | Detail: subtitles | `[x]` sheet opens |
| 2.11 | Detail: clip (rights-gated) | `[x]` opens Clip Studio |
| 2.12 | Detail: versions menu | `[>]` worked; had NO a11y label — fixed |
| 2.13 | Detail: share menu incl. archive.org | `[>]` worked; had NO a11y label — fixed |
| 2.14 | Detail: cast bubble → person browse | `[ ]` |
| 2.15 | Detail: More Like This | `[ ]` |
| 2.16 | Browse: sort + every facet chip | `[x]` Films / TV / Collections |
| 2.17 | Search: type a query, get results | `[x]` 'chaplin' returns results |
| 2.18 | Search: result filters | `[ ]` |
| 2.19 | Library: Favorites / History / Playlists / Clips | `[x]` all four |
| 2.20 | Channels: tune in | `[ ]` |
| 2.21 | Settings: every toggle | `[>]` all 12 flip; sheet-reset DEFECT fixed |
| 2.22 | Back navigation from every pushed screen | `[ ]` |

---

## T3 — Playback and captions (A14 hardware)

| # | Check | Result |
|---|---|---|
| 3.1 | A film starts within 30s (Decision 077) | `[x]` playing at 30s |
| 3.2 | Native transport chrome — no persistent overlay | `[x]` clean frame at 30s; HUD only on tap |
| 3.3 | Resume from a saved position | `[ ]` |
| 3.4 | Published subtitle file renders | `[ ]` |
| 3.5 | Generated captions on a captionless film | `[ ]` |
| 3.6 | Caption switching (file ↔ automatic) | `[ ]` |
| 3.7 | PiP + background audio | `[ ]` |
| 3.8 | A14 decode: no dropped frames on a large file | `[ ]` |

---

## T4 — Data spine (posters, shelves, counts)

| # | Check | Result |
|---|---|---|
| 4.1 | Every Home shelf non-empty and gated | `[x]` 5 screens of populated shelves |
| 4.2 | No missing/broken poster in the first screens | `[x]` none seen |
| 4.3 | Catalog downloads and swaps in | `[x]` full catalog on device (Browse counts real) |
| 4.4 | Adult filter on by default | `[x]` OFF as designed (Decision 012) |


---

## 2.7/2.12/2.13 — Three action buttons had no accessibility label `[>]`

**Measured**: XCUITest could not find the favourite button at all. Four of
the seven Detail actions carried `.accessibilityLabel` (playlist, watched,
subtitles, clip); **favourite, versions and share carried none**, so
VoiceOver announced them by SF Symbol name or not at all.

**Fix**: labels added — favourite state-describing ("Add to favorites" /
"Remove from favorites", matching the watched button's pattern), "Choose
another copy", "Share and more". **Verified**: all seven actions are now
found, tapped, and the favourite's label flips on tap.

## 2.21 — Every Settings toggle threw the viewer back to the top `[>]`

**Measured**: after flipping "Show mature collections" (which sits well down
a long page), the row was still absent from the view 30 seconds later, while
the app stayed fully responsive the whole time — the `Done` button resolved
on every one-second poll. The screenshot settled it: Settings had **scrolled
back to "Account & Sync"** within 4 seconds.

**Root cause**: `HomeView` carries `.id(store.dbVersion)` so its shelves
re-query when the DB swaps (seed → full). The `.sheet` presenting Settings
was attached INSIDE that identity. Every Settings toggle bumps `dbVersion`
— it changes what every query returns — so each flip destroyed and rebuilt
the sheet, resetting its scroll. Home was the only view with both a
`dbVersion` identity and a sheet.

**Fix**: the sheet now attaches after `.id`, outside the invalidated
subtree. **Verified**: the row stays put through a flip, and all twelve
toggles flip in one Settings session without the page jumping.

**Not a defect, measured and dismissed**: the ~5s each flip takes is
dominated by XCUITest's own accessibility snapshot on an A14. The internal
control is "Transcribe films with no subtitles", which touches no catalog
data at all and still measures 3.8s — so a full catalog re-query costs about
1.2s on top of harness overhead.

---

## Harness lessons (they each cost a false finding first)

1. **`isHittable` lies.** A Settings switch at y=837.7 on an 844pt screen
   reported `hittable = true`; the tap landed off the bottom edge and read
   exactly like a dead control. Scroll into the middle band and verify by
   frame, never by the flag.
2. **A SwiftUI `Toggle` is exposed as the WHOLE ROW** (358pt wide), so
   `.tap()` hits the label and does nothing. Tap the trailing edge
   (`normalizedOffset dx: 0.92`). This produced a "9 of 9 toggles are dead"
   report against toggles that all work.
3. **Judge by EFFECT when the self-report is in doubt** — `test_13` turns a
   category off and asserts its tile leaves Home. That is what settled it.
4. **The iOS 26 search tab REPLACES the tab bar**, so visiting it mid-loop
   makes every later tab unreachable. Visit Search last.
5. **A `Form` renders lazily**: a row does not exist in the tree until
   scrolled near, so `waitForExistence` without scrolling never resolves.
6. **Index-based element iteration breaks** the moment a flip rebuilds the
   tree ("no matches for element at index 2"). Collect labels, then act.
