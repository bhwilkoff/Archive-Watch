# Archive Watch — tvOS Design (BINDING)

**Binding.** Every new view, tab, shelf, sheet, overlay, mode, filter, or
toolbar item on the Apple TV app must trace to a rule in this document. When
something feels overwhelming or inconsistent, **fix this document first, then
fix the feature.** Proposals (and commits) cite the rule they implement,
e.g. "per tvOS-DESIGN §2.3."

Division of labor with the other docs:
- **This doc** = the *binding contract*: information architecture, surface
  taxonomy, the design system, and the per-feature IA decisions.
- **`docs/tvos-playbook.md`** = the *implementation recipes* (focus APIs, card
  sizes, image pipeline, animation values). Non-binding how-to; cite it for
  mechanics.
- **`DECISIONS.md`** = the *why* behind non-obvious rules. Each binding rule that
  isn't self-evident has a DECISIONS entry.

---

## §1 — Principles (the why)

1.1 **Lean-back, then lean-in.** The default mode is wandering a repertory
cinema at 10 feet. Every surface must work as pure browse, but should offer at
least one door to curiosity (a connection, a "what is this?", a fact). A surface
that only enables passive consumption violates CLAUDE.md "Why we build" — give it
one lean-in affordance. (Applies hardest to the ambient modes, §9.)

1.2 **Focus does the work.** The focused element is the chrome. Surrounding
elements stay quiet. Density comes from removing chrome, not adding decoration.

1.3 **One verb per top-level surface.** Each tab owns a distinct user verb
(browse / tune in / search / save). Two surfaces competing for the same verb is a
structural bug — resolve before shipping (the verb test, §12.2).

1.4 **Depth ≤ 2 from any tab root.** Tab → list/grid → detail. A would-be third
push must instead be a scope, a sheet/overlay, or a different tab (§12.3).

1.5 **Back is sacred.** Never intercept Back outside the player or a modal
(playbook §8.2 — App Store rejection risk). Every full-screen mode (§9) has a
visible exit and honors Back.

1.6 **Highest quality, faithfully presented.** Archival content gets the same
visual dignity as modern streaming. Never degrade source quality for convenience
(Decision 021); never show a placeholder where real art can be earned (§7).

1.7 **No new state without a home.** Any persisted user state (favorites,
playlists, progress, watched, preferences) maps to the data model in §10 and, for
synced state, the account store (Decision 022).

1.8 **Voice: a programmer's note, never a parser's.** Every shelf/section
**subtitle** reads like a line from a repertory cinema's programme — a knowing,
warm invitation to *watch*, written the way the curator actually talks. It names
what makes the films worth your evening, not how the database found them. This is
the operational form of CLAUDE.md "Why we build": copy should open a door to
curiosity.
- **Banned** (the parser tells): pipeline/metric language — "Most downloaded",
  "catalogued on Wikidata", "filter: X", "Pre-1970 animation", "items", "results",
  "tap to…", raw counts as the whole subtitle. The viewer never sees how the
  sausage is made (downloads, sources, tiers, queries).
- **Wanted** (the programmer's note): evocative + specific, ≤ ~8 words, present
  tense, concrete nouns. The bar is the copy that already works —
  *"The magician who invented cinema"*, *"How they reported the 20th century"*,
  *"Shadows and second thoughts"*, *"High craft, low traffic"*. Popularity becomes
  *"What everyone's watching this week"*, not "Most downloaded".
- **Titles stay plain.** Nav/section *titles* ("Collections", "Continue Watching",
  "Directors") and empty-state guidance stay clear and scannable (§1.2, clarity
  over cleverness) — the voice lives in the **subtitle**, not the label. Don't make
  a heading cute at the cost of legibility at 10 feet.
- Shelf copy lives in `featured.json` (`subtitle`) and
  `shared/editorial/collection_metadata.json` (`blurb`); curators edit it there,
  not in Swift. New shelves cite this rule.

---

## §2 — Information architecture

2.1 **Tab budget = 9, hard ceiling.** The sidebar (`TabView(.sidebarAdaptable)`)
currently holds 8. A new surface earns a tab ONLY if it owns a distinct top-level
verb (§1.3) AND would be buried if nested. Default to nesting. Adding a 10th tab
requires removing or merging one first.

2.2 **The canonical tab set** (v1 target):
Home · Movies · TV Shows · **Channels** · Collections · Search · **Library** ·
Surprise · Settings. Changes from today: **Channels** is added (§9.1 earns a tab
— a distinct verb, "tune in," and the flagship differentiator); **Library**
replaces the standalone Favorites tab and absorbs Favorites + Playlists + Watched
(§10). That is 9 — the ceiling. Anything else nests.

2.3 **What nests, and where** (binding placement for the backlog):
- **People / cast / crew / characters (#4)** → reached from Detail; a
  detail-class destination in the active tab's `NavigationStack`. NOT a tab.
- **Documentary (#7)** → a category: a Movies facet + a Home shelf. NOT a tab.
- **Public Domain Day (#15)** → a Home seasonal section + a "by year" scope
  inside Browse. NOT a permanent tab.
- **Cartoon mode (#2), Party/background play (#3)** → **modes** (§9), launched
  from Home and Settings, NOT tabs.
- **Cover-art screensaver (#14)** → system idle surface (§9.4), not navigable.
- **Sharing (#16)** → an action on Detail/player (§8), not a surface.

2.4 **Home is the front page, not a junk drawer.** Home composes hero + a bounded
set of shelves (curated, dynamic, Continue Watching, category, decade, director,
hidden gems, seasonal). New Home shelves must declare a removal/empty rule
(universal-feature-states) and respect the post-1977 rights gate
(home_filters memory / CatalogDB `homeAnd`).

2.5 **Every list/grid/shelf/sheet declares all states.** loading · loaded ·
empty · error — each user-visible (CLAUDE.md). Empty states must contain a
focusable element or focus traps (playbook §2.5; the Favorites empty-state bug).

---

## §3 — Surface taxonomy (the only allowed shapes)

Every UI maps to exactly one. A new shape needs a new rule here first.

3.1 **Tab** — a top-level verb (§2.1). Sidebar entry + `NavigationStack`.
3.2 **Shelf row** — horizontal, lazy, focus-reveals title (playbook §3.3, §9.3).
3.3 **Grid** — paged/lazy browse with facets (Movies, Collections, search results).
3.4 **Detail** — hero backdrop + metadata + actions + "more like this"; Play
auto-focused (playbook §9.4). People pages are a detail variant.
3.5 **Sheet / overlay** — transient, dismissible, focus-restoring (player info,
settings, share, skip). Never a nav push (§1.4).
3.6 **Mode** — a full-screen lean-back takeover that replaces the shell while
active, with a visible exit + Back (§9). Channels, Cartoon, Party, Screensaver.
3.7 **Player** — `AVPlayerViewController` baseline + the resilient loader
(Decision 021). Custom chrome only as overlays (§8).

---

## §4 — Typography (binding; mechanics in playbook §4)

4.1 **Six levels, period.** Three weights × two sizes, on the tvOS ramp
(76/57/38/29/23). Body floor 29pt; never below 23pt. A seventh level is refused —
refactor (CLAUDE.md density rule). Use the playbook's tokens, never hardcode.

4.2 **No synopsis at 10 ft on transient surfaces** (hero, shelf, channel banner).
Synopsis lives on Detail and the player info overlay only.

---

## §5 — Color & materials (binding)

5.1 **Brand vs semantic split is absolute** (Decision 013). Brand chrome:
marquee orange `#FF5C35` (primary/CTA), accent blue `#0047FF`. Per-category
semantic accents (Feature Film/Classic TV/Silent/Animation/Newsreel/Documentary/
Ephemeral/Short) carry *content meaning only* — never use a brand color for
meaning, never a semantic color for chrome.

5.2 **Dark-first.** Reserve brightness for the focused element. Liquid Glass
(`.glassEffect`, tvOS 26) is the material; no `.ultraThinMaterial` holdouts
(prior native pass). Per swiftui-liquid-glass: glass on key interactive surfaces
only, never decorate everything.

---

## §6 — Focus contract (binding; APIs in playbook §2)

6.1 The five unbreakable rules hold everywhere: dark-first/29pt/90×60 safe area ·
Back sacred · full reachability · **never `.buttonStyle(.plain)`** · preserve
focus by stable id, not index.

6.2 Initial-focus surfaces (hero, first landing, mode entry, player) claim focus
imperatively on appear (playbook §2.4). Every new mode/overlay declares its
default focus and its focus-restoration target on dismiss.

---

## §7 — Artwork (binding)

7.1 **Real art first.** Posters resolve through the enrichment cascade
(Decision 008). Where none exists, generate a cover from frames + faces (#13,
Phase 4) before falling back to the procedural poster. Never ship a modern poster
on a vintage title — image, synopsis, and title must agree (the #20 rule; metadata
quality program).

7.2 Decode to displayed size via the custom `ImageLoader` (playbook §7), never
raw `AsyncImage` in grids.

---

## §8 — Player surfaces (binding; governs #5, #8, #9, #10, #16)

8.1 **The native player owns transport.** We add only overlays/sheets, never a
parallel transport. All remote video flows through `ResilientStreamLoader`
(Decision 021); buffering per `tunePlaybackBuffering`.

8.2 **In-player settings are one sheet (§3.5), not nav.** Subtitles, audio track,
playback speed, and the per-video autoplay override live in a single transport
sheet. Surface a control only when it has ≥2 real options (hide a single audio
track / single quality) — honest affordances (§1.2).

8.3 **Info overlay** shows title/synopsis/cast + next/prev episode; dismissible;
does not pause unless the user does (#9).

8.4 **Skip intro/credits (#8)** is a transient, focusable, auto-appearing/-fading
affordance anchored to per-title timestamps; pairs with autoplay-next (§9.5).

8.5 **Autoplay (#10)** has a global default (Settings) and a per-video override
(8.2 sheet): same show / same category / same year / off. Runs on the §9.5 engine.

8.6 **Sharing (#16)** is an action surfaced on Detail and in the player sheet.
tvOS has no share sheet → hand-off via QR + deep link (`archivewatch://item/{id}`)
and archive.org URL; AirPlay is native.

8.7 Suppress the asset's bogus embedded year and publish Now Playing artwork via
`commonIdentifierArtwork` (prior work, playbook §8.6).

8.8 **Watch Together Studio is the PLAYER plus overlays (§3.7 + §8.1), never a
§3.6 mode.** The Apple TV is the box the owner watches on, so it is also where
a watch-along is produced: the film on the television, an iPhone on the table
as the camera and microphone through Continuity Camera. The Studio adds a
health readout, a layout/faders/cards sheet (§8.2's one-sheet rule) and go-live
as overlays over the same `AVPlayerViewController` and the same resilient
asset. Its frames reach the encoder through an `AVPlayerItemVideoOutput` and
its audio through an `MTAudioProcessingTap` — both OUTPUTS on the item the
player already has, so §8.1 and §11.4 hold. Specifics:

- **The Continuity Camera picker is a §3.5 sheet presented FULL-SCREEN**, which
  is Apple's own requirement for `AVContinuityDevicePickerViewController`. It
  is a **one-time** step: a paired phone is found by a discovery session
  afterwards, so the Studio must never demand the picker per show.
- **The microphone is an `AVAudioSession` port, not a capture device**, and
  `.playAndRecord` is only legitimate once such a port exists — raising it
  earlier fails and a failed activation stops `AVPlayer` dead
  (docs/WATCH-TOGETHER.md §9).
- **No camera is not an error.** A paired phone may be absent, asleep or
  carried away mid-show; the program continues film-only and says so.
- Only films `StudioRights.canGoLive` clears are offered (WATCH-TOGETHER §3.4).
- **A ONE-TIME CONFIRMATION carries the §3.4a warning, because a television
  has no informed moment.** On iOS and macOS a host reads
  `StudioRights.hostWarning` on the surface where they then press Go Live, so
  pressing it IS an informed action. tvOS starts the Studio straight from the
  transport menu — there is no sheet to read and nowhere to put a paragraph —
  so the first broadcast on a device asks for the risk to be accepted
  explicitly: the warning, **Start the broadcast** and **Not now**. It is
  asked ONCE per device and never again, because a dialog a host has already
  answered is chrome, and chrome in front of a broadcast is worse than
  nothing. Stored in `UserDefaults` — there are no accounts on this platform
  (§10.2) and this is a device fact, not an identity one.
  An ineligible film still shows the entry point, disabled WITH its reason —
  §2.5's "no empty state without a focusable element" applies to explanations
  too.

---

## §9 — Modes: lean-back takeovers (binding; governs #1, #2, #3, #14)

9.0 **Definition.** A mode replaces the navigation shell with a full-screen
experience driven by the **continuous-playback engine** (one shared service:
queue → autoplay-next → transition; roadmap F4). Every mode: (a) has a visible
exit + honors Back (§1.5); (b) declares default focus (§6.2); (c) includes one
lean-in affordance (§1.1) — a press reveals "now playing / what is this / more
like this"; (d) never degrades quality (§1.6).

9.1 **Channels (#1)** — a tab (§2.2). A channel = a saved query (era / genre /
collection / user-built from full-DB filters) realized as a continuous now/next
lineup with a guide. The lean-in affordance is the guide + "jump to this title's
detail."

9.2 **Cartoon mode (#2)** — a mode scoping the catalog to animation with a
simplified, large-target, kid-safe shell (adult filter forced on) and autoplay.
Launched from Home/Settings. Lean-in: big "what's this?" reveal.

9.3 **Party / background play (#3)** — a mode: video-only, **muted by default**
with an audio toggle, autoplaying a curated high-contrast / visually-interesting
queue. Lean-in: a press reveals title + "play with sound / open."

9.3a **Every ephemeral lineup owes the viewer three verbs** (2026-09-14). A
lineup the viewer did not choose — Party Play, a channel, a marathon — raises
exactly three questions, and each is a transport-bar action on `PlayerScreen`:
**Play with Sound / Mute** (the audio toggle 9.3 promised), **Open Title**
(leave the lineup for the film's own Detail — favorite, playlist, read about
it; Back returns to the lineup's landing page), and **Remember** (write the
watch-history record NOW, without the 60 s gate the automatic write keeps so
a channel-surf is not "watched"). The owner sat through a Party Play film they
could not identify, could not hear, and could not keep: 9.3's lean-in was
written but only the toggle was built. Android TV and Roku carry the same
three in their player options (TV-DESIGN §5.6, ROKU-DESIGN §6.9).

9.4 **Cover-art screensaver (#14)** — the system idle surface; an iTunes-style
animated cover wall over catalog art. Adapt BOBA-Playbook's **Showcase**
(`BOBAPlaybook/Views/Collection/CollectionShowcaseView.swift` — an
AlbumArtwork-style tile grid with flip/drop/roll/spin animation variants + a
`ShowcaseSession` orchestrator). Not navigable; any remote press exits to where
the user was.

9.5 **The engine is shared.** Channels, Party, Cartoon autoplay, and in-player
autoplay (#10) all use the F4 engine. Do not write a second queue/transition
system — extend F4 (the "fix the document, then the feature" reflex).

---

## §10 — Personalization & data (binding; governs #11, #12, #17)

10.1 **Library** (tab, §2.2) is the home for all saved state: Favorites,
Playlists/custom collections (#12), and Watched. One tab, sections — not three
tabs (§1.4).

10.2 **Account & sync (#11, Decision 022 pending Phase 3).** Sign in with Apple
(`AuthenticationServices`) for identity + CloudKit private DB for cross-Apple-TV
sync of favorites, progress, and playlists. No external auth **for identity**.
Sign-in is optional for browsing/playback — it gates only sync (no funnel;
§1.1, Decision 009 spirit).

10.2a **The one external sign-in, and why it does not break 10.2.** Watch
Together Studio (§8.8) publishes to the viewer's **own** YouTube or Twitch
channel, which those platforms will only permit an authorised app to do. That
is not identity for Archive Watch and it is not a funnel: nothing about
browsing, playback, favorites or sync changes if a viewer never signs in, the
consent screen appears only after the viewer has chosen to broadcast a
specific film, and the scopes requested are exactly the three the feature uses
(create a broadcast, read the stream key, read chat). The rule 10.2 exists to
protect — **the app never asks who you are in order to show you a film** —
holds unchanged. `ASWebAuthenticationSession` is available on tvOS 16+ and is
the path (checked in the tvOS 27 SDK, 2026-09-17). A stream key is fetched by
API and never typed or displayed.

**PROPOSED Rule 8.8a — going live on a television requires NO TYPING, and the
host chooses a PLATFORM, not a form. NOT YET APPROVED; nothing is built against
it.**

*Why this is proposed*: `docs/WATCH-TOGETHER.md` §9.ccc found that tvOS cannot
broadcast at all, and §9.lll found why it is not merely a missing call: after
the rights gate, the configuration check and §3.4a's confirmation, the menu
simply sets `studioFilm = film`. **There is no way for a host to say WHERE the
broadcast goes or what it is called.** iOS collects platform, title, privacy or
category and layout in its §8.9 sheet; macOS now mirrors that sheet under
§B13g. A television cannot mirror it, because that sheet's centre is a text
field.

*The rule proposed*: the "with the world" menu item opens a FOCUS-DRIVEN
confirmation, not a form. It states the film, the destination platform, and
§3.4a's warning, and its default action goes live. Specifically:

- **The title is not typed.** It comes pre-filled from the catalog's own
  audited record — the same `suggestedTitle` iOS pre-fills — because that
  record is already checked (Decision 124) and a remote keyboard is the worst
  text-entry surface in the house. §2's agency test is satisfied by the title
  being SHOWN and the broadcast being refusable, not by making someone spell it
  out with a d-pad.
- **The platform is a CHOICE, and the only one.** Where a host is signed in to
  both, "with the world" expands to one item per platform, which is the same
  device tvOS already uses for "with friends / with the world".
- **Privacy and category take documented defaults** — the iOS default of
  `unlisted` for YouTube, and no category for Twitch — because both are
  changeable afterwards on the platform itself, and neither is worth a
  d-pad form.

*What is NOT decided here, and is the reason this is a proposal*:
1. whether a host may EDIT the title on a television at all (a remote keyboard
   is hostile, but never offering it is a decision, not an oversight);
2. whether `unlisted` is the right tvOS default when the whole point of the
   feature is that the world can watch — iOS chose it for a phone, and a
   television audience may not be the same audience;
3. what happens when a host is signed in to NEITHER platform, which today
   refuses with §10.2b's sentence and would, under this rule, be the moment to
   offer sign-in instead.

All three are the owner's calls. Until they are made, tvOS keeps the engine,
the gates, the verified hardware encoder (§9.vv) and no way to broadcast.

**Correction to the line above, same day.** This rule originally added "it
hands off to a nearby device rather than demanding typing on a remote". That
was an assumption, not a reading, and it is withdrawn — what the tvOS 27
header actually proves is narrower and is worth having exactly:
`ASWebAuthenticationSession` is `tvos(16.0)`, while
`presentationContextProvider`, `prefersEphemeralWebBrowserSession` and even
`cancel` are `API_UNAVAILABLE(tvos)`. So the television presents the flow
ITSELF and there is no anchor to hand it — which is consistent with a hand-off
but does not establish one. **The screen cannot be seen until a client id
exists** (Decision 128), so nobody has looked at it. Marked rather than
rewritten, because a confident sentence that was read and believed is worth
seeing (Decision 121).

10.2b **Where the tvOS sign-in appears.** Inside the existing Watch Together
flow off the player's transport menu (§8.8) — never a Settings row, never a
§3.6 player mode, and never a pre-flight the viewer must clear before they
have chosen to broadcast anything. A host who is not signed in is told so
where they asked to go live, in the same alert that already carries a rights
refusal, with the platform's own flow the only thing behind it. **Built and verified
on an Apple TV, 2026-09-17**: choosing "With the world…" applies the rights
gate first and then `StudioPlatformAuth.anyConfigurationProblem`, and a build
with no client ids shows *"Streaming is not set up yet"* with the sentence
naming what is missing. The alert's TITLE changes with the reason — a build
with no credential is not a film that cannot be streamed, and putting "This
film cannot be streamed" over it would tell the viewer something false about
the film and about the public domain, which is the one thing that alert exists
to teach (§2.1). The message names BOTH platforms: a surface with no platform
picker must not pick one arbitrarily, because a host told only about YouTube
reasonably asks what about Twitch.

**Correction, 2026-09-18 — the predicate was a proxy, and it came apart.** The
gate above read `StudioPlatformAuth.anyConfigurationProblem`, which answers
"can this BUILD sign in". The question this rule actually asks is "can this
TELEVISION reach an audience", and the two were the same thing only while
NEITHER platform was configured. Registering the YouTube client id (§9.nnn)
made that predicate nil — so a change in a gitignored config file, nowhere
near tvOS, opened the menu onto exactly what this rule exists to prevent: a
production mode that can never reach an audience. tvOS has no platform picker
and `DetailView.runStudio` starts the engine with `destination: nil`, so the
Studio would have encoded at 6 Mbps to nobody with nothing on the glass saying
so. The gate now asks the right question (`studioTVBroadcastProblem`) and says
the true thing — going live from Apple TV is not built yet, start it from
iPhone, iPad or Mac — while keeping the credential sentence for the case it
still describes, a build with no ids at all. **A guard written against a proxy
expires the day the proxy stops tracking the thing it stood for**, and nothing
about registering a client id looks like it touches a television.

10.3 **Watched state (#17).** Completed titles (`WatchProgress.isComplete`) are
hidden from Home shelves by default (Settings toggle to show), but remain in
Search/Browse and a Library → Watched section. Hiding ≠ deleting.

10.4 Continue Watching uses timecode, not percent (playbook); it is exempt from
the §10.3 hide (it shows in-progress, not completed).

---

## §11 — Anti-patterns (never)

11.1 A new tab to avoid nesting (§2.1). 11.2 A third nav push (§1.4) — make it a
scope/sheet/mode. 11.3 `.buttonStyle(.plain)` (kills focus). 11.4 A parallel
transport or second autoplay/queue engine (§8.1, §9.5). 11.5 A control shown with
only one real option (§8.2). 11.6 A mode/overlay with no exit or no default focus
(§9.0). 11.7 Degrading video quality for convenience (§1.6). 11.8 A modern poster
on a vintage title (§7.1). 11.9 A seventh type level (§4.1). 11.10 An empty state
with no focusable element (§2.5).

---

## §12 — The three tests (run before any surface ships)

12.1 **Competent-designer test** — could a peer rebuild this screen from a
one-paragraph description? If no, you added decoration; strip.
12.2 **Verb test** — what verb does this own? Colliding with a sibling? Structural
bug; resolve first.
12.3 **Depth test** — count pushes from the tab root. >2 → scope/sheet/tab, not
another push.

---

## §13 — Out of scope (intentional gaps for v1)

On-device upscaling (#6 dropped, Decision D-B; Apple TV 4K upscales natively).
Third-party/external auth (Apple-native only, §10.2). Multiple user profiles per
device. A consumer web/iOS client (the web stays the editorial dashboard,
Decision 006). Live/linear broadcast **received** beyond the §9.1 channel
simulation — we do not become a TV tuner. **Producing** a live broadcast is a
different thing and is IN scope as of Decision 127 (§8.8): the Apple TV
encodes a watch-along and sends it to the viewer's own YouTube or Twitch. The
gap this line names is inbound, not outbound.

---

## §14 — Per-feature IA decision table (the backlog, bound)

| # | Feature | Surface (§3) | Placement | Key rule |
|---|---|---|---|---|
| 1 | 24-hr channels | Mode + Tab | Channels tab | §9.1, §2.2 |
| 2 | Cartoon mode | Mode | launched Home/Settings | §9.2 |
| 3 | Party play | Mode | launched Home/Settings | §9.3 |
| 4 | Cast/crew/characters | Detail variant | in-stack from Detail | §2.3 |
| 5 | Subs/audio/quality/speed | Sheet | player transport sheet | §8.2 |
| 7 | Documentary | Grid + Shelf | Movies facet + Home shelf | §2.3 |
| 8 | Skip intro/credits | Overlay | player affordance | §8.4 |
| 9 | Info overlay + ep nav | Overlay | player | §8.3 |
| 10 | Autoplay options | Sheet + Settings | per-video + global | §8.5 |
| 11 | Accounts + sync | (data) | Library + Settings | §10.2 |
| 12 | Playlists | Grid/Detail | Library sections | §10.1 |
| 13 | Cover generation | (pipeline) | build-time → artwork | §7.1 |
| 14 | Screensaver | Mode | system idle | §9.4 |
| 15 | Public Domain Day | Shelf + Grid | Home section + Browse-by-year | §2.3 |
| 16 | Share | Action | Detail + player sheet | §8.6 |
| 17 | Hide watched | (data) | Home filter + Library/Watched | §10.3 |
| 18 | Episode reclassification | (pipeline) | canonical TV | Decision 016 |
| 19 | No-entry play bug | (bug) | player failure state | §2.5, §8.1 |
| 20 | Wrong poster/desc | (pipeline) | metadata matching | §7.1 |
| 22 | **Watch Together (with friends)** | Action | Detail menu | Decision 098, `docs/SHAREPLAY.md` |
| 23 | **Watch Together Studio (with the world)** | Player + overlays | Detail menu → player | §8.8, §10.2a, `docs/WATCH-TOGETHER.md` |

| 21 | Top Shelf | System surface | tvOS Home top row | §15 |

---

## §15 — Top Shelf: the system surface (binding; governs #21)

The Top Shelf is not a §3 surface — it lives on the tvOS Home screen, outside our
navigation — so §2's tab ceiling and §12.3's depth test do not apply. These rules
do.

15.1 **Shape is `TVTopShelfSectionedContent`, poster tiles.** Named rows of 2:3
posters, never the carousel as the permanent default: a single rotating hero is
the most passive shape we could pick, and rows are doorways (§1.1). Reserve the
carousel for a genuine moment (a Public Domain Day, a retrospective).

15.2 **A row is named by its REASON, never "For You".** "Silent Era", "Film
Noir", "Watching Now on the Archive", "Public Domain Day" — the row title teaches
the catalog's organizing concepts, the same vocabulary Home and Browse use
(§1.2). An opaque personalized row is an anti-pattern here for the same reason
it is on Home: the user learns nothing from it.

15.3 **It must CHANGE.** A deterministic `ORDER BY … LIMIT n` renders the same
titles forever and reads as broken (measured: the shipped feed was byte-identical
for three weeks). Both which rows appear and which titles fill them rotate on a
fixed time window — stable while someone is looking at it, different by the next
sitting. Rotation is a time bucket over a published pool, not a model: predictable
and debuggable (§1.2, clarity over cleverness).

15.4 **Continue Watching leads when it exists**, carries `playbackProgress`, and
drops a title the moment it completes (§10.3/§10.4 — same in-progress semantics as
the Home row). It is the one personal row; it comes from the app's App Group
snapshot, which must be rebuilt whenever a POSITION changes, not merely when the
set of watched titles changes.

15.5 **Two actions, two verbs.** `displayAction` (Select) opens Detail — a look, a
choice, never autoplay. `playAction` (the Play button) plays, resuming where the
viewer left off. Every route either action emits must be handled by
`IntentInbox`; an unrouted deep link is a dead tile, indistinguishable from a
broken app.

15.6 **Editorial content comes from the published feed, personal content from the
snapshot, and the two MERGE.** Never either/or — a snapshot that exists must not
suppress the fresher feed. The feed is cached on device so a network blip degrades
to yesterday's rows, not to the static app image.

15.7 **A tile must be playable and have designed art** (§7.1, Decision 023/044
gates: `playable = 1`, real artwork, rights-gated). A poster-less or dead tile on
the system Home screen is the most visible quality failure the app can have.

15.8 **Budget: ≤5 rows, ≤8 tiles each** (WWDC guidance). The extension is a
separate ~16 MB process — hand the system image URLs, never decode or resize
art there, and never block first paint on the network.
