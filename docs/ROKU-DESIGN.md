# ROKU-DESIGN.md — the binding design doc for Archive Watch on Roku

**This document is binding.** Before proposing any new Roku view, sheet, row,
dialog or overlay, quote the rule here that justifies it. If no rule fits, the
proposal needs a NEW rule added here first, and a reason. That is the
`binding-design-doc-discipline` contract, the same one `docs/TV-DESIGN.md` and
`docs/tvOS-DESIGN.md` operate under.

Written from `docs/research/roku-design.md` (design) and
`docs/research/roku-platform.md` (engineering). Where this doc and the research
disagree, this doc wins; where this doc is silent, the research is guidance, not
licence.

The owner's instruction this serves: *"each platform should have a design that
works specifically for it and all of the design should take cues from the system
interface and other first-party apps on the platform."* This is therefore a
**Roku-native** design. `docs/TV-DESIGN.md` governs Android TV and web TV and is
NOT inherited here except where a rule is explicitly restated below.

---

## 1. First principles

**1.1 Differentiate on content, never on interface.** Roku's own guidance
discourages visual uniqueness through unconventional navigation. This is the
sharpest cultural break from tvOS, where a distinctive shell is expected. On
Roku, looking native IS the design goal, and our identity comes from the films,
the curation and the copy.

**1.2 One screen, one purpose.** Roku's rule. A screen that answers two
questions is two screens.

**1.3 Blank space is essential.** Roku states this explicitly, and it is the one
place our house density rule needs translating rather than porting. Our rule is
that density comes from REMOVING chrome, not adding decoration — that survives
unchanged. What changes is the target: a Roku screen sits noticeably airier than
the Android TV build. Remove the chrome, then spend the reclaimed pixels on air
rather than on more tiles.

**1.4 Everything critical is reachable with the d-pad, OK, Back and Home
alone.** No hidden gesture, no discovered menu, is ever the only route to a
feature. `*` may be the BEST route to a verb; it may never be the ONLY route to
a feature the viewer needs.

**1.5 The shelves are ours; the recommendation engine is not.** Restated from
`TV-DESIGN §1.4`. Every row says where its ranking comes from. Roku's Continue
Watching and Save List are compatible with this rule because they carry the
viewer's OWN state, never a model's opinion about them.

**1.6 Respond within 250 ms.** A certification number and a design constraint: a
shelf that re-queries or re-decodes on every focus move fails it on entry-level
hardware.

---

## 2. Information architecture

**2.1 The shell is a LEFT rail, never top tabs.** `ButtonBar` with
`alignment="left"`, `autoHide=true`, `overlay=true`. Roku's own 2026 home screen
is a condensed left icon rail, and the two large publishers who moved Roku
sidebars to top tabs — Plex and Pluto — drew sustained user complaints that it
costs more button presses on a d-pad. Top tabs are forbidden here.

**2.2 Seven rail surfaces, and no more:** Home · Movies · TV · Channels ·
Collections · Search · Library. An eighth requires an amendment to this section.

**2.3 Settings is NOT a surface.** It lives behind `*` on Home, per Roku's
stated best practice that settings "do not belong in primary UI such as the Home
screen of your app." This is a deliberate divergence from every other Archive
Watch platform and is recorded as such in §10.1.

**2.4 Surprise is an ACTION, not a surface.** It is the first tile of the first
Home row, an entry in the `*` dialog, and the Play/Pause shortcut target when
nothing else is featured. Roku's rail is short and its currency is surfaces; a
verb does not earn one.

**2.5 Depth is at most 2, and the panel is how we keep it there.** Rail →
surface → item. Where another platform would push a third screen, Roku shows a
right-hand panel beside the list (`GridPanel`). Series → season → episode is the
one permitted exception, and only because the season list is a panel, not a push.

**2.6 Back is sacred and it EXITS from Home.** Back returns to the previous
screen or state. From our Home it shows exactly one "Exit Archive Watch?"
confirmation and leaves to Roku Home. Never trap it. Never make Back mean
"go to our Home" from our Home.

---

## 3. The remote

**3.1 The contract, and it is not negotiable:**

| Button | On a UI screen | During playback |
|---|---|---|
| d-pad | Move focus | Left/right scrubs; up reveals our HUD |
| OK | Activate the focused item | Reveal the HUD |
| Back | Previous screen; from Home, exit | Exit playback to the referring screen |
| `*` | Options for the focused item | **Reserved by Roku.** Ours only while our HUD overlays the video |
| Instant Replay | — | Rewind **15 s** |
| Play/Pause | Play the featured item **without moving focus** | Toggle |
| Rew / FF | **Page** through grids and rows | Speed increments |

**3.2 `*` on a focused item opens that item's verbs.** Add to Favorites, Add to
Playlist, Play from start, Resume, Mark watched, More Like This, Share, Open on
archive.org, and Remove where the row is a Library row. This is where Android TV
puts a long-press and tvOS puts a context menu; a Roku remote has neither.

**3.3 `*` on Home with nothing item-specific focused opens Settings + About.**

**3.4 Rew/FF paging is required on any grid that can exceed one screen.** With
25,000 titles it is the difference between usable and not.

**3.5 Text entry is the last resort, and the keyboard is the platform's.**
`DynamicMiniKeyboard`, which brings voice entry for free. Search always offers
no-typing doors (§6.4).

---

## 4. Canvas, grid and safe area

**4.1 Design at 1920×1080.** Roku autoscales FHD→HD at exactly 2/3.

**4.2 EVERY dimension is divisible by 3.** Position, width, height, gutter, type
size, focus step. Two-thirds of a multiple of three is an integer; anything else
lands on fractional pixels at 720p. No other platform we ship has this rule, and
it is the one most likely to be forgotten.

**4.3 Two insets, and they are different.**
- **Action-safe, 96 × 54** — every interactive element, focus ring at rest, row
  title and poster caption. Identical to `TV-DESIGN §4.2` and to Roku's own
  action-safe offset.
- **Title-safe, 192 × 108** — any block of prose the viewer is meant to READ: a
  synopsis, an empty-state explanation, the TMDb notice, settings body copy.
  This is new against every other Archive Watch platform and it is Roku's rule.

**4.4 Content column is 1728 px** and begins at y = **169** (Overhang 115 +
inset 54).

**4.5 A focus ring may bleed 9 px** toward the screen edge. Nothing else may
cross the action-safe line except full-bleed artwork.

**4.6 Poster geometry.** Resting and focused sizes are STATED, never derived
from a scale factor:

| Use | Resting | Focused | Gutter |
|---|---|---|---|
| Home shelf poster | 224 × 336 | 248 × 360 | 24 |
| Browse grid poster | 192 × 288 | 210 × 315 | 24 |

(§13 amendment: the shelf poster came down from 264 × 396 so two rows sit
under the hero; the CELL (posterFW/FH) stays 24 px larger than the drawn tile
because the caption is anchored at the cell height — see ROKU-PARITY lesson 67.)
| 16:9 shelf item | 384 × 216 | 420 × 237 | 24 |

**4.7 Never reshape the art.** Decision 097 binds here without amendment: a hero
renders the image at its OWN aspect over an ambient wash of itself. Our catalog
is 2:3 for most sources and arbitrary landscape for Commons, Archive and
Wikidata stills.

---

## 5. Type, colour and focus

**5.1 Six levels, all divisible by 3. A seventh is refused.**

| Level | FHD | HD | Weight | Use |
|---|---|---|---|---|
| Marquee | 66 | 44 | Bold | Hero title, Detail title |
| Screen | 45 | 30 | Bold | Overhang title, screen headings |
| Row | 33 | 22 | Bold | Shelf titles, buttons |
| Body | 27 | 18 | Regular | Synopsis, settings rows |
| Item | 27 | 18 | Medium | Poster captions, list titles |
| Meta | 24 | 16 | Regular | Year · runtime · category · counters |

The floor is 24. Body and Item share a size and differ by weight — the "three
weights × two sizes" discipline on a ten-foot canvas.

**5.2 Use the Roku system font family.** A bundled typeface eats the 4 MB
package budget for no native gain.

**5.3 Colour. The `CLAUDE.md` split is binding and uncrossed: brand for chrome,
semantic for content meaning.**

| Token | Value | Use |
|---|---|---|
| Canvas | `#0B0B0C` | The ground. Dark-first; no light mode |
| Surface | `#16161A` | Overhang, rail, panels, dialogs |
| Marquee orange | `#FF5C35` | Focus ring, footprint, Play, trick bar, selected rail item, progress |
| Text primary | `#EBEBEB` | Titles, body |
| Text secondary | `#9A9AA0` | Meta, disabled |
| Category accents | per `CLAUDE.md` | **Content meaning only** — category tiles, the Detail category chip, a row's accent spine. Never a focus ring, never a button |

**5.3b No channel may exceed 235.** Roku requires broadcast-safe graphics:
pure white fails certification outright, and so does any fill at 255. Text
primary is therefore `#EBEBEB`, not `#F2F2F2`, and the marquee orange used in
FILLS on Roku is **`#EB5531`**, the broadcast-safe rendering of `#FF5C35`.
`#FF5C35` remains the brand value everywhere else and is what the palette in
`CLAUDE.md` still means; this is a Roku output rule, not a new brand colour.

**5.4 Accent blue `#0047FF` is not used on Roku.** It is a web link colour;
Roku has no links, and at ten feet on a dark ground it fails contrast — the same
finding that produced the iOS dark variant. Where web would use it, Roku uses
marquee orange for interactive and text-secondary for informational.

**5.5 Focus is a ring, a size step and a reveal — never a shadow, a tilt or a
scale transform.** At least two of the three are present at all times:
1. the resting/focused size pair of §4.6;
2. a 9-patch focus bitmap, 3 px, blended to `#FF5C35`, drawn ON TOP so it reads
   against a bright poster;
3. the item's caption appears only on focus.

**5.6 The footprint is required.** When a row or grid loses focus, leave a
dimmed ring at the last position. This is a Roku affordance with no tvOS or
Android TV equivalent, it is how a viewer finds their place after a trip to the
rail, and it is what lets the rail auto-hide without disorienting anyone.

**5.7 Use the Overhang's `(*)` indicator** on every screen where Options are
available. It is the platform's own "there are options here" affordance and the
cheapest way to look native.

---

## 6. The screens

**6.1 Home** is a hero row over shelves. Full-bleed hero art at its own aspect,
Marquee title, a Meta line, a focused Play button and Details. Play/Pause
anywhere on Home plays the hero without moving focus. Rows below are the shared
shelf set in the shared order: Continue Watching first when non-empty, then
curated and dynamic shelves, Top Rated, Hidden Gems, community shelves, director
shelves, Public Domain Day, then category tiles, and **decade tiles last** —
matching every other platform. Each row shows its title and, on focus, the
platform row counter. Shelf subtitles from `featured.json` render at Meta.

**6.2 Home gates on `hasProfessionalArtwork`** (Decision 097). A shelf that
cannot field six professional posters hides rather than padding itself with
frame grabs. This does NOT apply to the viewer's own Favorites.

**6.3 Browse** is an 8-column grid with scope chips above it on one focusable
row: Type, Decade, Sort. A chip opens a dialog, never a pushed screen. TV Shows
browses series cards, never loose episodes (Decision 036).

**6.4 Search** is the platform keyboard on the left, results on the right,
updating incrementally. **Below an empty query it shows browse doors** —
Categories, Decades, Collections, Surprise — because a viewer who never touches
the keyboard must still be able to leave with a film. Type and decade chips
filter the results, and only facets PRESENT in the results are offered.

**6.5 Detail** is art, title, "Also known as" when the canonical title differs
(Decision 100), a meta line, a capped synopsis, then a horizontal button row with
**Play auto-focused** and labelled with the runtime or "Resume · 21m left". Then
Cast, More Like This, and the collection it belongs to. The category chip is the
only semantic colour on the screen. The full synopsis is reachable through `*`.

**6.6 Player.** The `Video` node owns the transport; we recolour the trick bar
and change nothing structural (Decision 037, which Roku enforces anyway). OK
reveals a non-interactive HUD carrying title and description. Instant Replay
rewinds 15 s. Captions are configured through Roku's Options dialog with its four
required states, fed by our published captions — **note that side-loaded WebVTT is not confirmed
to work on Roku and SRT may be required**; measure on the device before claiming
subtitles work. Our own in-player options — speed,
subtitle track, autoplay — live in an up-revealed HUD row, because `*` belongs to
Roku during full-screen playback.

**6.6b The resilient stream loader does not exist here, and cannot.** The
`Video` node's HTTP client lives in firmware: BrightScript cannot intercept it,
issue its own ranges, proxy it, or even observe it. Decisions 021, 031 and 034
have NO Roku equivalent — this was investigated at the owner's request before
building on top of it, and the answer is not "partially", it is "not at all".
What remains is coarse and must all be used: pin redirects with
`StreamStickyHttpRedirects`, tolerate transient errors with `ignoreStreamErrors`,
and run our own position-stagnation watchdog that re-issues play at the last
known position. Every recovery is a visible cold re-buffer, and the viewer will
see it. This regression is recorded in PARITY rather than hidden.

**6.7 Channels** uses the platform EPG: channel rows, programmes sized by
duration, a now-line, join-in-progress, commercial breaks woven. Our date-seeded
scheduler is the content source; the layout is the platform's. The Now/Next view
is the degradation path for low-end hardware, not a reduced grid we invent.
Presets ship first; creating a channel needs text entry and is deferred with a
recorded reason.

**6.8 Collections** is a list with a right-hand panel describing the focused
collection, updating as focus moves. OK enters it as a grid.

**6.9 Library** is Continue Watching, Favorites, Playlists and History — and it
is **capacity-bounded**, see §7.2. It has no Clips tab; creation tools are never
on a TV.

**6.10 Settings and About** is a flat dialog behind `*`: mature-content filter on
by default (Decision 012), autoplay, category visibility, the **verbatim TMDb
notice** (Decision 007), source credits, **Donate to the Internet Archive**
(Decision 010) as a QR, and the version.

**6.11 Every list, grid, shelf and dialog defines four states beyond the happy
path** — loading, empty, error, offline (`universal-feature-states`). On Roku the
first-run loading state is a DESIGNED screen, not a spinner, because there is no
bundled catalog to paint from (§7.1).

---

## 7. The platform's hard limits, and what they mean for design

**7.0 Home must render within 20 seconds on a Roku Express**, the weakest
device certification tests. Our own measurement on a Streaming Stick 4K is a
1.06 s download and a 364 ms parse of the 6.2 MB index, so the web data plane is
comfortable HERE; it is not proven on an Express. If the Channel Store becomes
the goal, the answer is a small hydrated `roku/home.json` for the first paint
with the existing detail shards behind it — not a rewrite.

**7.1 The package is capped at 4 MB, so there is no bundled catalog.** Decision
053's "first paint from the cached catalog" has no Roku equivalent on first
launch. Design an honest, branded loading state that says what is happening. Do
not fake an instant paint.

**7.2 Persistent storage is a 32 KB registry**, and `cachefs:` is evictable at
any time so it is not storage at all. Thirty-two kilobytes is roughly 800–1,000
saved ids across favorites, playlists and progress with a compact encoding. Design response: publish progress
to Roku's own Continue Watching so it lives in Roku's cloud and syncs across the
viewer's devices, cap Favorites at a stated number, and render a real "Library is
full" state with a Remove affordance. Silent truncation is forbidden.

**7.3 There is no durable storage for media, so Downloads is `n/a`** — the same
reasoning as tvOS in Decision 099, for the same reason.

**7.4 A screensaver is prohibited** in a streaming app. Our cover-art idle mode
cannot ship inside this channel.

**7.5 Deep links have two meanings and must not be conflated.** A link from
voice or from Roku's Continue Watching row must begin **playback immediately** —
it may not land on a details screen. A link from browse or search lands on
Detail.

---

## 8. What is deliberately not built, and why

| Verb | Why |
|---|---|
| Cover-art screensaver | Prohibited in a streaming app |
| Clip Studio / Creation Studio | Never on a TV (Decisions 033/042) |
| Downloads / offline | No durable storage (§7.3) |
| Watch Together | Apple-only framework |
| Cast / AirPlay send | Roku is a receiver; sending is meaningless |
| Picture-in-Picture | Not a Roku app affordance |
| Background media controls | A video app pauses on switch-away |
| Sign-in / cross-ecosystem sync | **Blocked by Roku policy, not by plumbing.** Certification prohibits off-device sign-in, which is structurally what Google's limited-input device flow is — the one route that would have reached Drive App Data. CloudKit is doubly out. Roku's own Continue Watching gives cross-device progress without an account of ours, and that is the whole answer here |

---

## 9. The ship gate — "does this read like an Android app on a Roku?"

Any of these fails the gate:

- a top tab bar, or Settings in the navigation;
- a focused card that lifts and shadows instead of ringing;
- a scrubber we drew;
- a long-press where `*` belongs;
- no `(*)` indicator in the Overhang;
- a Back that goes to our Home from our Home;
- text entry that is not the platform voice keyboard;
- any dimension not divisible by 3;
- prose starting at the action-safe inset instead of the title-safe inset.

---

## 10. Divergences from the house rules, recorded

**10.1 Settings leaves the navigation** (§2.3) and **Surprise is demoted to an
action** (§2.4). `TV-DESIGN §2` says the IA is inherited and not a local
decision. The exception is granted here because Roku states the opposite rule
for settings, and because Roku's rail is a scarcer surface than a sidebar. This
divergence is Roku-only and does not amend `TV-DESIGN`.

**10.2 The platform row counter is kept** even though `tvOS-DESIGN §1.8` bans
raw counts in our own voice. On Roku the counter is platform chrome that a
viewer already reads as chrome, not as us talking.

**10.3 Our density rule is translated, not ported** (§1.3).

**10.4 Accent blue is dropped** (§5.4).

---

## 11. Open, and needing the owner rather than a rule

1. **Trick-play thumbnails.** Roku certification requires them for every title
   over fifteen minutes. Nothing in the catalog has one, and generating them
   across ~25,000 films is a real pipeline programme. It does not block
   sideloading. It may decide whether the Channel Store is worth it.
2. **A separate Archive Watch screensaver app** is permitted where an in-channel
   screensaver is not. On-brand, a second listing, unpaid work.
3. **How large should the Library cap be**, given §7.2 — a stated number with an
   honest full-state, or lean harder on Roku's own Save List?
4. **Should Surprise get a rail icon anyway?** Roku convention says no. The
   product says it is one of the best things about it.

---

## 12. Operational warnings

**12.1 Back up the `genkey` signing password AND one signed `.pkg`** the way the
Android upload keystore is backed up. There is no documented recovery from
losing both, and changing the key **wipes every user's registry** — which is
their favorites and their watch progress.

**12.2 ECP defaults to Limited on Roku OS 14.1 and later.** `/keypress` then
returns 403 while `/launch` and `/query/device-info` keep answering, so a
reachability check passes with every input silently rejected. No API can change
it; it gates the endpoints that would. The path is Settings → System → Advanced
system settings → Control by mobile apps → Network access.


---

## Amendments from device work (tick 9)

### §2.1a — The rail COLLAPSES; content is laid out against the collapsed width

The rail is **84 px** by default and expands to **288 px only while it holds
focus**, drawn OVER the content rather than pushing it. Content is laid out
against 84 px and never moves.

Collapsed, each surface is a 42x6 bar; the current one carries marquee orange.
That gives position — which of seven you are on — with no label to read and no
icon asset to invent, and it is legible at ten feet because it is the only
coloured thing in an 84 px column.

**Why**: a permanent 216 px rail spends 11% of a 1920 px screen on navigation
the viewer is not using, on every shelf and every grid. Measured on the glass:
the same Home row shows **6 posters collapsed where it showed 4**. Expanding
over the content rather than beside it is what keeps this cheap — a rail that
pushed 26,000 posters sideways on every focus change would be the most
expensive animation in the app.

**The trap**: the selection pill must shrink WITH the rail. Left at its
expanded width it painted a 264 px highlight across the collapsed column and
over the hero title beside it — invisible in code, obvious in a screenshot.

### §6.6a — The player draws NO transport of its own

Superseded: §6.6's custom HUD carrying title and description. Roku's `Video`
node draws its own transport overlay on OK — title, progress, trick play — and
measured on the device it rendered "The Clairvoyant" and a clock straight over
ours. Drawing a second one is not our design; it is a duplicate of something
the platform already does better. OK is no longer consumed by the player.

What remains is the one thing the system cannot say: that this film HAS
subtitles which the viewer's own device setting is suppressing. One line, at
the bottom, clear of the system overlay, only when there is something to say.

### §6.6b — Captions are the DEVICE's setting, and we never override it

Roku owns closed captions globally (`roDeviceInfo.GetCaptionsMode()` →
`On` / `Off` / `Instant replay`). An app must not override that. Measured on
this device the mode is **"Instant replay"**, which is why a correctly
side-loaded track legitimately draws nothing during normal playback.

Also measured, and better than Roku's own documentation implies: the `Video`
node **accepts our published WebVTT directly** via `SubtitleUrl` — one track,
offered and auto-selected (`eng:1:English`). No SRT conversion is needed.

### §4.2a — Chrome never composites over a playing film

The rail, the overhang, the brand mark and the clock are all hidden during
playback, and the player is full-bleed at `[0, 0]` rather than inset by the
rail. This is Decision 103's rule arriving on a fourth platform: chrome that is
right for browsing is never right over a picture.


### §2.1b — The collapsed rail carries ICONS, not bars

Amends §2.1a. The first collapsed rail drew a 42x6 bar per surface, which
carries POSITION — which of eight you are on — and not IDENTITY. Identity is
the whole point of a collapsed rail: it has to answer "which one is Search"
without expanding, or the viewer expands it every time and the collapse saved
nothing.

Eight single-colour 48x48 PNGs under `images/nav/`, tinted through `blendColor`
so one asset serves the dim, selected and focused states. The icon does NOT
disappear when the rail expands — the label appears BESIDE it — because a rail
whose glyphs vanish on expand reads as two different navigations.


### §5.4a — The selection ring goes around the ART, not the CELL

A shelf cell is always 2:3. The artwork often is not — a 16:9 still or a wide
lobby card fitted into that cell leaves broad empty margins, and a ring drawn
at cell size then encloses mostly nothing. The owner's words were "much bigger
than the poster", which is precisely what it was.

The tile therefore draws its own ring, sized from `Poster.bitmapWidth` /
`bitmapHeight` once the art has loaded, and the LIST is told to draw none. Two
traps, both found on the glass:

* A list with no `focusBitmapUri` does not draw nothing — it falls back to its
  own grey box at cell size. Silencing it needs an explicitly transparent
  9-patch (`focus_none.9.png`).
* A `.9.png` only has its guide border stripped when a LIST consumes it as
  `focusBitmapUri`. Assigned to a plain `Poster` the guide pixels are part of
  the picture, which is why the first hand-drawn ring rendered as a pale block.
  Four `Rectangle` nodes are exact and cheaper.

### §5.2a — A tile shows a title card until its own art arrives

A `RowList` RECYCLES its item components, and a `Poster` keeps the previous
bitmap until the new one finishes loading. A rebound tile therefore showed the
WRONG film's poster under the right film's caption — worse than showing no
poster. Clearing the uri first makes the typographic card the thing on screen
until the real art lands, and the card hides on `loadStatus = "ready"` (it is
declared after the Poster, so it draws over it if left visible).

### §4.4a — The hero is a picture, and the chrome sits over it

Superseded: a 792px image floating top-right of an otherwise empty band, which
read as a placeholder rather than a marquee. The hero is now full-bleed for its
whole 480px: a real landscape backdrop fills it, a poster-only item gets a
zoomed dimmed copy of itself as the surface plus the fitted poster at right
(Decision 097 — a poster is never cropped). Roku has no gradient node, so the
left-to-right fade is four stacked rectangles; at ten feet the steps do not
read.

The Overhang moved AFTER the content in the child order and became a scrim
rather than a solid bar. Chrome belongs above content, and an opaque bar would
slice the top off the picture.

An item with no art of its own leaves the previous picture up. Blanking the
marquee because the viewer moved onto a poster-less title looks like a
failure; holding the last image looks like a marquee.


### §4.4b — There is no persistent overhang

Superseded: §4.4's 115px brand bar with a clock and a "(*)" indicator. All
three were permanent elements telling the viewer nothing they did not already
know, and the owner's question — "what is the (*) in the top right corner?" —
is the whole argument against it. Roku's own channels carry no persistent title
bar, every surface already names itself in its heading, and removing it returns
115px to the hero. `*` remains the options key; it is a platform-wide
convention and does not need a badge to announce it.

### §5.2b — Every tile carries its title

Superseded: a caption shown only under the FOCUSED tile. That left a shelf of
unlabelled pictures, which is not how any other platform in this project
presents a shelf. The title is always on; the META line (year, type) stays
focus-only, because six of those per row is noise. The caption is pinned to
the UNFOCUSED poster height so it does not jump as focus travels — a row of
titles that dances while you scroll is worse than no titles.

### §4.4c — The hero ROTATES

Superseded: a hero that followed the focused tile. It changed the marquee on
every key press, and a poster-less title blanked the whole band. It now
rotates through the backdrop pool on a 9-second timer, which is what a hero is
on every other platform in this project.


---

## 13. The design upgrade (2026-09-04) — from functional to designed

**Binding.** The owner, after the channel reached functional parity: "Everything
still looks incredibly boxy and rudimentary and not as if a professional
designer actually put it together." This section is the answer, researched
against Roku's own principles ("celebrate artwork", "blank space is essential",
"one explicit primary action", "the UI is invisible"), the tvOS ramp and hero
(`docs/tvos-playbook.md` §4, §9), and the two apps this one should stand
beside — Mubi for warmth and the size of its imagery, and the Criterion Channel
as the cautionary case of an institutional grey screen with a dead corner.
Every rule below amends the section it names; §1–§12 otherwise stand.

**13.1 Typography is real, and it is the house typography.** Amends §5.1/§5.2.
The six levels were six named system fonts at whatever size Roku chose, so a
hero title, a row title and a caption were three sizes of one sans — that was
most of "rudimentary". Fraunces (the serif every other Archive Watch surface
leads with) and Inter are bundled as Latin subsets, 516 KB for six faces.

| Level | Face | Size | Use |
|---|---|---|---|
| Marquee | Fraunces Display Black | 66 | Hero title |
| Title | Fraunces Display Black | 57 | Detail / series title |
| Screen | Fraunces Display SemiBold | 45 | Screen headings |
| Row | Inter SemiBold | 33 | Shelf titles, buttons |
| Body | Inter Regular | 27 | Synopsis, prose |
| Item | Inter Medium | 27 | Captions, list rows |
| Meta | Inter Regular | 24 | Year · runtime · counters |

Two VOICES on existing sizes, not new levels: the **eyebrow** (Meta, Inter
SemiBold, caps, tracked with hair spaces because `Label` has no tracking) and
the **tagline** (Body, Fraunces Text Italic). Every size still divides by 3.

**13.2 A category is a word, never a slug.** `feature-film` was printed as
`FEATURE-FILM` on the hero and the Detail chip. `KindLabel()` is the one
place a contentType becomes a label, and nothing prints a slug.

**13.3 Focus is a light ring with a soft edge, and there is only ever ONE.**
Amends §5.5/§5.6. Orange marked focus everywhere, so it marked nothing — and
on Series and Channels two orange rectangles were lit at once. Focus is now a
3 px near-white (`#EBEBEB`) rounded ring with a 12 px soft glow; the
footprint is the same ring at 35% with no glow, and a list that is not the
active zone shows the footprint, never the ring. Marquee orange is reserved
for Play, progress, the selected rail item and the trick bar — meaning, not
attention. Tiles draw the ring from corner and edge slices
(`images/slices/ring_*`), because a `.9.png` on a plain `Poster` keeps its
guide pixels; lists take the real 9-patch (`ring_focus.9.png`).

**13.4 Corners.** Every poster, still, tile plate and button is rounded at
9 px. Roku's `Poster` has no radius, so posters take four canvas-coloured
corner overlays (`slices/corner_*`), and plates and buttons are built from
end-cap slices. A hard-edged rectangle in this channel is a bug.

**13.5 Buttons are pills; there are at most three, and one is primary.** A
button is a 60 px pill: resting = 11% white on the canvas, focused = solid
`#EBEBEB` with canvas-dark type, the primary (Play) = marquee orange with
light type when focused and outlined when not. Never a flat rectangle plate.

**13.6 No tinted-box backgrounds on rows or cards.** Restates the house
density rule for this platform: separation comes from spacing and type, not
from a `#16161A` slab behind every row. The surface colour is for the rail,
panels and dialogs — the chrome — not for content.

**13.7 Detail and Series are scenes, not forms.** Amends §6.5. Backdrop
full-bleed across the top 60% with the §13.3 gradient; the poster inset
lower-left over the seam at its own aspect (Decision 097); title in Fraunces
to the right of the poster with eyebrow above and meta below; the pill row at
the seam with Play focused; synopsis at the title-safe inset below; then
cast, More Like This. A film with no backdrop gets its own POSTER as an
ambient wash at 0.6 behind the copy (the Apple TV app's treatment for
poster-only titles) — measured on the glass against a flat accent field, the
ambient read as a designed page and the field read as a missing image. The
HERO keeps the accent field, because a hero is a rotation and a missing
picture there is one of twelve. A film whose only art is LANDSCAPE is a
still, not a poster: no inset, the copy takes the column.

**13.8 Nothing on screen tells the viewer how to navigate.** "Press OK on a
channel to tune in", "Press Right past the keyboard", "OK to open · Left /
Right for more" — all removed. A status line states a result ("300 titles
match 'noir'"); the layout carries the rest.

**13.9 No engineering talks on a consumer surface.** "121 bytes of 32 KB
used" is gone from Library. The §7.2 budget surfaces as a designed
nearly-full / full state with a Remove affordance, not as a counter.

**13.10 Rhythm.** Amends §4.6 for Browse: the 8-column grid left 126 px of
dead space between rows. Rows sit on a 24 px gutter both ways; captions ride
INSIDE the cell reserve, and the reserve is exactly caption + gutter.

**13.10a A focus bitmap that is opaque draws UNDER the text.** Roku's
`drawFocusFeedbackOnTop` was true on the option lists; with the light pill
it hid the focused row's own label. Rings go on top, fills go underneath.

**13.11 The ship gate gains four lines** (amends §9): a raw slug on screen; a
second lit focus ring; a hard-edged poster; an instruction sentence.

## 14. Amendments from the owner's feedback (2026-09-05)

**Binding.** The owner used build 18 and returned twenty defects
(`docs/ROKU-FEEDBACK-LEDGER.md`). Each rule below amends the section it
names; everything else stands.

**14.1 (amends §6.3) A chip opens a PICKER, never cycles.** The rule
already said "a chip opens a dialog"; cycling in place was the wrong
reading of it. Select on a chip opens the options panel ON the current
value; the pill states the value chosen. Applies to Browse and Search.

**14.2 (amends §6.5 / §13.7) More Like This is a shelf, and the page
scrolls.** The Detail is one Group. Down from the pill row slides it up so
the "More like this" row label sits at the heading line and the poster row
under it, exactly as the tvOS detail page scrolls; Up returns. The row is
the same PosterTile shelf Home draws. A synopsis the page had to cut is read
from More → "Read the full synopsis" (§13.12's reading block) — Down is never
a stop on the description.

**14.3 (amends §6.8) Collections is a grid of curated CARDS.** Two columns
of 852×324 cards: a three-poster montage under the §13.3 gradient, an
accent rule, the count ("120+" at the index's cap — a floor, never a false
total), the title in the display face, the blurb. A card opens the
collection as the Browse grid with the collection as its heading and no
chips. The shelf-per-collection surface duplicated Home and now serves
Cartoon Mode only.

**14.4 (amends §6.12) Twelve doors, all on screen.** Four rows of three;
a door below the fold is not a door. Random Film is a FEATURE; Random TV
Series opens a show, never a loose episode. Party Play is an ephemeral,
muted lineup: it writes no bookmark and Back returns to the doors. The
Cartoon Marathon lives on `*` in Cartoon Mode.

**14.5 (amends §2.6) Back returns to the PLACE, not the top.** Every
surface keeps its focus while hidden; Back into Home restores the row and
tile; a grid opened from a door, a tile or a card returns to that door,
tile or card; a series opened from a grid returns to the grid. Choosing
Home from the rail is the one path to the top.

**14.6 (amends §5.2b) A grid tile carries the title card too.** Every
tile type draws the designed accent-rule-and-name card until its art
arrives, and keeps it when the art never does. Home, the hero, random
picks, More Like This and collection cards require professional art;
Browse and Search may show a frame cover, never a blank plate.

**14.7 (amends §13.1) The meta line sits under the caption's rendered
height**, never under the three-line reserve — pinned to the reserve it
floated 100 px below a one-line title.
