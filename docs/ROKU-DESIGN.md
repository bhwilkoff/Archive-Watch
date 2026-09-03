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
| Home shelf poster | 264 × 396 | 288 × 432 | 24 |
| Browse grid poster | 192 × 288 | 210 × 315 | 24 |
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
