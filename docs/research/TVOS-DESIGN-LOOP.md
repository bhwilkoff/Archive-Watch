# tvOS design loop (2026-09-28)

Owner, starting the loop: *"I'd like you to complete a similar design audit and
feature evaluation on the tvOS app as you have on the MacOS and iOS versions of
Archive Watch. Pay particular attention to button presses that pull up
additional information or windows, as I notice frequent truncation of long
sentences or paragraphs. Additionally, please pay attention to speed on the
slower 2nd generation Apple TV 4k. A full audit of every surface and
improvements across the board for buttons, text, and native implementations of
key features for a smooth search, find, and play video experience. Additional
research should be relied upon for native Apple TV interface elements and
design patterns as well as opportunities to leverage the latest APIs and
features of tvOS 27. However, I would also like you to investigate if it is
possible for making a version of the app functional on older apple tv hardware
as well. The goal is not full parity for older hardware, but rather a fully
functional experience in the same way that we have been able to manage on old
Roku and Android hardware."*

Test device: **Ben Bedroom** (Apple TV 4K 3rd gen, tvOS 27.2), driven over
Companion (`atvremote`) with `tools/atv_shot.sh` for fresh screenshots.
**Movie Room** is on tvOS 26.6, which is the floor. **Fireplace** is the only
2nd-gen box and is the owner's living-room TV: it is off limits until the owner
offers a window.

## Older hardware (answered 2026-09-28)

| Model | Chip / RAM | Last tvOS | Runs Archive Watch? |
|---|---|---|---|
| Apple TV 3rd gen and earlier | A5 | no App Store | no, and never can |
| Apple TV HD (2015) | A8, 2 GB | 26 (dropped in 27) | **yes, today** (floor is 26.0) |
| Apple TV 4K 1st gen (2017) | A10X, 3 GB | 26 (dropped in 27) | **yes, today** |
| Apple TV 4K 2nd gen (2021) | A12 | 27 | yes |
| Apple TV 4K 3rd gen (2022) | A15 | 27 | yes |

The floor has been tvOS 26.0 since 2026-04-19, so every Apple TV that can run an
App Store app can already install it. What the old boxes lack is a **guarded
floor** (raising it to 27 would silently cut both off) and **verification on an
Apple TV HD** (A8, no HEVC, 2 GB, ~148 MB catalog DB to open). Lowering the
floor to 17/18 would help nobody: every box on 17/18 can update to 26 for free,
and tvOS cannot be downgraded to test it. Test builds: 18.0 fails in 4 files
(~16 errors), 17.0 in 7 (~75, most in `RootView`'s tab API). Sources and build
logs: session scratchpad `tvos-legacy.md`.

## Findings (first sweep, Ben Bedroom)

| Surface | Finding |
|---|---|
| Sidebar | 13 entries (Home, Movies, TV Shows, Channels, Cartoons, Party Play, Screensaver, Collections, Search, Library, Surprise, Watch Together, Settings) against tvOS-DESIGN §2.1's hard ceiling of 9; §2.3 says modes launch from Home/Settings, not tabs |
| Launch | the sidebar opens expanded over the hero on launch |
| Detail | six icon-only circles (favorite, watched, share, playlist, versions, subtitles) with no label even when focused; nothing tells a viewer what the stack or the speech bubble does |
| Detail > Subtitles | the sheet is two paragraphs explaining OpenSubtitles and generated captions; explanation copy the essential-information rule removes, and generated captions are now on by default (Decision 147) |
| Data | `gov.archives.arc.38638` "Bomber" (1941), a 9-minute government short, wears Warner's *Dive Bomber* (132 min): still, synopsis, tagline, cast, studio; it rotates through the Home hero |
| Remote | a Companion `select` right after a focus move is sometimes dropped; re-press and re-shoot before calling a button dead |

## Research (session scratchpad `tvos-research.md`, sources there)

- **tvOS 27 added Dynamic Type** (Settings > Accessibility > Text Size, WWDC26
  session 221). This app sets most text at fixed point sizes, so at the largest
  size little grows; what does grow (semantic fonts: Play, "Show more", the
  sidebar) now sits beside fixed text. Measured on Ben Bedroom at
  accessibility5 with the new `AW_TYPE_SIZE` door.
- **Apple's long-text pattern** is TVML's `handlesOverflow`: a focusable
  description with MORE, opening the full text on its own page. Expanding in
  place fails on a TV: a block taller than the screen is one focusable element,
  so the remote cannot scroll to its end.
- Search: `searchSuggestions`, `searchScopes`, recent searches; most relevant
  results first. Player: `customInfoViewControllers`, `contextualActions`,
  `AVContentProposal` for Up Next. Glass: never per card.

## Truncation audit (code, 36 findings; scratchpad `tvos-truncation.md`)

Root patterns: `lineLimit` on data prose with no way to the rest; full-screen
VStacks with no ScrollView; fixed heights around text that grows on focus;
character-count guesses for "Show more"; system-owned clamps (transport menu
titles, alert bodies, the caption label's 4 lines).

## Done

- v1.42.840: **More opens the whole text** (synopsis, series overview, archive.org
  reviews) on a scrolling page of focusable paragraphs; whether to offer it is
  measured, not guessed from a character count. Series overview 22pt -> 29pt,
  episode captions 21/17pt -> 29/23pt (the §4.1 floor). **Search** leads with
  Films & Shows, episodes after at five with Show all (seen on Ben Bedroom,
  "keaton"). **Channels** guide blocks fit their row. **Join a room / Go Live /
  mixer** keep every sentence at full height. **TV rights**: the audit judges
  each episode by its own year; 166 late episodes (143 of them SNL) are now
  checked on the next run where archive.org answers.

## Queue

1. Detail action row: six unlabeled icons; show what the focused one does
2. Dynamic Type: move the fixed sizes onto the ramp as relative fonts
3. Sidebar budget: 13 -> 9 (owner call: which modes leave the sidebar)
4. Search -> find -> play path, timed; SILENT badge collides with poster art
5. 2nd-gen speed (needs a Fireplace window) and a floor rule for tvOS 26
6. Wrong TMDb match by runtime (pipeline, agent measuring)
7. Uploader-style titles (`Buster Keaton's "The Goat"`) on display
8. Episode player's Info panel carries no description
