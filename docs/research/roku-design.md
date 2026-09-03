# Roku Design Research — Archive Watch as a first-class Roku channel

> **Status:** research brief, decision-ready. Not binding. A binding
> `docs/ROKU-DESIGN.md` should be written **from** this document, quoting the
> rules it adopts and recording the conflicts it resolves.
>
> **Scope:** the DESIGN half of a research pair. A companion brief covers
> engineering (BrightScript / SceneGraph, the streaming stack, packaging). This
> document stays off implementation detail except where a platform mechanic
> *constrains what a design can be* — and where it does, it says so and cites
> the source.
>
> **Owner's instruction this serves:** *"each platform should have a design that
> works specifically for it and all of the design should take cues from the
> system interface and other first-party apps on the platform."* So the target
> is a Roku-native design, not `docs/TV-DESIGN.md` repainted.
>
> Read alongside: `CLAUDE.md` (why we build; the brand-vs-semantic colour
> split), `docs/TV-DESIGN.md` (the non-Apple ten-foot contract),
> `docs/tvOS-DESIGN.md` + `docs/tvos-playbook.md` (how Apple's version thinks),
> `PARITY.md` (every feature that must find a Roku home).

---

## 0. Executive summary — the five decisions that most shape the build

**D1. The navigation shell is a left ButtonBar rail, not top tabs, and Settings
leaves it.** Roku's own 2026 home screen is a three-column layout with a
condensed left icon rail ([PCWorld](https://www.pcworld.com/article/3149985/rokus-new-home-screen-is-a-big-change-heres-how-to-use-it.html),
[9to5Google](https://9to5google.com/2026/05/27/roku-home-screen-redesign/)),
and SGDEX's `ButtonBar` — the component Roku ships for app navigation — takes
`alignment` of `"top"` or `"left"` ([SGDEX components](https://github.com/rokudev/SceneGraphDeveloperExtensions/blob/master/documentation/1-components.md)).
The market evidence is one-sided: Plex moved its Roku app from a left sidebar to
top tabs and drew sustained complaints that it "requires more button presses and
is slower to use" with a D-pad ([Plex forum](https://forums.plex.tv/t/roku-plex-ui-regression-sidebar-removed-top-tabs-now-request-classic-sidebar-toggle/935370));
Pluto TV made the same move in 2026 ([TechTimes](https://www.techtimes.com/articles/320479/20260714/pluto-tv-tests-top-nav-redesign-backed-paramount-tech-stack-overhaul.htm)).
Separately, Roku's own best practices say Settings "do not belong in primary UI
such as the Home screen of your app" and should have "a single entry point in
the Options dialog"
([best-practices](https://developer.roku.com/docs/developer-program/design/best-practices.md)).
**Recommendation:** left rail carrying 7 surfaces; Settings behind `*` on Home;
Surprise demoted from a rail item to a persistent action. This is a deviation
from the IA inherited wholesale in TV-DESIGN §2 and needs an explicit exception
recorded (see §9.1).

**D2. Focus is a 9-patch focus bitmap plus an explicit two-size step — never a
scale transform, and never a parallax card.** Roku draws focus with
`focusBitmapUri` / `focusFootprintBitmapUri`, 9-patch images that stretch around
the item, with `drawFocusFeedback` and `drawFocusFeedbackOnTop` controlling
whether the ring sits under or over the poster
([PosterGrid](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/postergrid.md)).
`ZoomRowList` grows the focused row between explicit `rowHeight` /
`rowZoomHeight` and its items between `rowItemHeight` / `rowItemZoomHeight`
([ZoomRowList](https://developer.roku.com/dev/docs/zoomrowlist)). Because Roku
autoscales FHD→HD at exactly 2/3, every dimension must sit on **3-pixel
boundaries** ([display resolution](https://developer.roku.com/dev/docs/specifying-display-resolution)) —
so a "1.08× scale" is the wrong mental model; you name both sizes and both land
on multiples of 3. There is no tvOS parallax/floating-card idiom on Roku and
building one would read as foreign (§5).

**D3. Two certification requirements are unmet today and are pipeline work, not
UI work.** Criterion **4.7** — "Apps must display thumbnails during trick play
for VOD content longer than 15 minutes" — requires a BIF archive or HLS/DASH
standard thumbnails per title
([certification](https://developer.roku.com/docs/developer-program/certification/certification.md),
[BIF creation](https://developer.roku.com/docs/developer-program/media-playback/trick-mode/bif-file-creation.md)).
Nothing in the Archive Watch catalog carries one. And criterion **3.7** — "The
app's file size must be 4 MB or less" — forbids a bundled `seed.sqlite`
outright, which changes the *first-run* design (there is no instant first paint
to fall back on; cf. Decision 053). Both must be scoped before a Roku design is
signed off.

**D4. The player is the platform's, harder than anywhere else — and `*` is not
ours during playback.** Criterion **4.4** reserves the Options button during
video playback for Roku's own display; an app may handle it only when its own UI
components overlay the video. Criterion **4.8** requires caption settings — On /
Off / On instant replay / On mute — *in the Options menu*. Criterion **4.9**
requires instant replay to rewind 10–25 s. The `Video` node owns the transport
and exposes its internal `trickPlayBar` for **colour** customisation, not
structure ([Video node](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md)).
So Decision 037's title+description overlay survives, our in-player settings
*sheet* does not: on Roku those controls belong to the system Options dialog and
to an Up-reveals-HUD row.

**D5. Two of our surfaces cannot ship as designed and one is outright
prohibited.** The cover-art **screensaver is prohibited** — criterion 4.5 bars
apps from overriding Roku's system screensaver, and Roku's screensaver policy
permits screensavers only in standalone screensaver apps
([screensavers](https://developer.roku.com/dev/docs/screensavers)). **Library
capacity is capped at 16 KB** of registry per app
([roRegistry](https://developer.roku.com/docs/references/brightscript/components/roregistry.md)),
which bounds favorites + playlists + history the way tvOS's storage bounds
downloads (Decision 099). Channels/EPG, by contrast, maps *cleanly* — Roku ships
`TimeGrid` for exactly this shape ([TimeGrid](https://developer.roku.com/dev/docs/timegrid)).

---

## 1. Roku's own design guidance

### 1.1 The philosophy, in Roku's words

Roku's stated goal is an **invisible UI**: users focus on content, not on
operating the interface. The platform's TV UI philosophy page frames the
difference bluntly — "television displays are communal and different from
computers, phones, and tablets," people recline, and the interface must demand
minimal cognitive effort
([general TV UI philosophy](https://developer.roku.com/docs/developer-program/design/general-tv-ui-philosophy.md)).

Two consequences matter for us:

1. **Muscle memory over discovery.** Users should rely on the "4-way directional
   pad (dPad), OK, Back, and Home," and "should be able to perform all critical
   functions without ever discovering any hidden menus or special remote button
   presses" (ibid). This is `TV-DESIGN §1.3` stated by the platform vendor.
2. **Differentiate on content, not on interface.** Roku explicitly discourages
   visual uniqueness through unconventional navigation, arguing that consistency
   with platform conventions accelerates learning (ibid). This is the single
   biggest cultural difference from tvOS, where a distinctive shell is expected.

The key design principles page adds the operational rules
([key design principles](https://developer.roku.com/docs/developer-program/design/key-design-principles.md)):

| Principle | Roku's wording |
|---|---|
| Flow | "A single pass top-down, left-right flow is the best," with final actions at right/bottom |
| Purpose | "One screen, one purpose" |
| Density | "Keep screen information density low; blank space is essential" |
| Legibility | Text must be "easy to read with high contrast and large text" for 10-foot viewing |
| Focus | Users must "easily tell where the focus highlight is and where it can go" |
| Feedback | The app "must respond immediately to every user action with clear and distinct feedback" |
| Animation | "simple, clean, and minimal animations"; "UI animations should not act as a governor to throttle the pace" |
| Overscan | "At least a 5% margin" — for 1920×1080, "90 pixel left/right side margin and a 60 pixel top/bottom margin" |

Note the density line. It is the *opposite* of our house density rule as stated
in `mobile-first-density-design`. It is not actually a conflict — our rule says
density comes from *removing chrome*, and Roku's says *leave blank space* — but
a Roku design should sit noticeably airier than the Android TV build. See §9.3.

### 1.2 Performance numbers that are design constraints

These are certification criteria and they bound what a screen can be
([certification](https://developer.roku.com/docs/developer-program/certification/certification.md),
[philosophy](https://developer.roku.com/docs/developer-program/design/general-tv-ui-philosophy.md)):

| Criterion | Requirement |
|---|---|
| 3.2 | Launch to a fully rendered home screen within **15 seconds** |
| 3.3 | Scene-to-scene transitions within **3 seconds** |
| 3.4 | A loading indicator for any visible process over **3 seconds** |
| 3.5 | Respond to remote presses / move between tiles within **250 ms** |
| 3.6 | Start playing content within **8 seconds** of initiation |
| 3.7 | **App package ≤ 4 MB** |
| — | Animation at a minimum of **30 fps** |

3.5 is the one that shapes layout: a shelf that re-queries or re-decodes on
every focus move will fail it on entry-level hardware. Roku's designing-for-
devices page is explicit that the fleet runs from "entry-level set-top-boxes to
4K HDR TVs," that apps are certified on *all* currently supported models, and
that the answer is graceful degradation — fewer items per screen on lower-end
devices, limited animation, reduced overdraw
([designing for devices](https://developer.roku.com/docs/developer-program/design/designing-for-device-capabilities.md)).

3.7 deserves its own line. A 4 MB package means **no bundled catalog**, and
"most developers keep graphics external from the channel code" — the platform
expects assets to be fetched. Design implication: the first launch has a real
network-dependent loading state with nothing behind it, which is a state tvOS,
iOS and Android never have to render honestly.

### 1.3 Canvas, safe area, and the 3-pixel grid

**Design in FHD.** "Roku recommends you design and develop for an intended 1080
screen resolution." Elements scale FHD→HD at 2/3 and HD→FHD at 1.5×
automatically when `ui_resolutions=sd,hd,fhd`
([display resolution](https://developer.roku.com/dev/docs/specifying-display-resolution)).

**The 3-pixel rule.** "Positioning items on 3-pixel boundaries, and specifying
width, height, and spacing values that are divisible by three will produce the
best results" at FHD — because 2/3 of a multiple of 3 is an integer (ibid). This
is a genuine, unusual constraint: **every number in our Roku type scale, grid,
gutter and focus step must be divisible by 3.** No other platform we ship on has
this.

**Safe zones.** Two authoritative sets exist and they disagree slightly:

| Source | Zone | FHD size | FHD offset |
|---|---|---|---|
| [graphics spec](https://developer.roku.com/docs/specs/graphics.md) / [tv-safe-zone-channel](https://github.com/rokudev/tv-safe-zone-channel) | **Action safe** (90%) | 1726×970 | **(96, 53)** |
| same | **Title safe** (80%) | 1534×866 | **(192, 106)** |
| [key design principles](https://developer.roku.com/docs/developer-program/design/key-design-principles.md) | "at least 5% margin" | — | (90, 60) |

The rule Roku states for their use: "Keep text that you intend the audience to
read within the Title Safe Zone… Keep important visual elements within the
Action Safe Zone."

Our `TV-DESIGN §4.2` already mandates 96×54 — which **is** Roku's action-safe
inset, to the pixel. So our house rule already clears Roku's floor for
interactive elements. What is *new* on Roku is the title-safe expectation for
reading text (192 px side inset). Recommendation in §6.1.

**The Overhang.** Roku's `Overhang` node is the platform's standard top bar:
default height **115 px**, background `0x232323ff`, logo and optional title on
the left with a vertical divider, and on the right an optional clock and an
optional `(*)` indicator telling the user the Options key is available
([Overhang](https://developer.roku.com/docs/references/scenegraph/overhang-nodes/overhang.md)).
Content should begin below it. The `(*)` availability indicator is the
platform's own affordance for "there are options here," and using it is the
cheapest possible way to look native.

### 1.4 Typography

Roku publishes **no numeric type scale.** The Font node exposes named system
fonts — `TinySystemFont`, `SmallestSystemFont`, `SmallerSystemFont`,
`SmallSystemFont`, `MediumSystemFont`, `LargeSystemFont`, `LargestSystemFont`,
`ExtraLargeSystemFont`, `BadgeSystemFont` and Bold variants — without publishing
their sizes ([Font](https://developer.roku.com/dev/docs/font)); custom sizes are
set in points on a `Font` node. Roku's own brand typeface is **Roku Sans**
(Text / Display / UI families), which is proprietary and not licensed to
third-party channels.

So the type scale is ours to set, under two external constraints: divisible by
3, and legible at ten feet. §6.2 proposes one.

### 1.5 Colour and contrast

Roku publishes no palette for third-party apps. The guidance is functional:
"ensure that all active UI has sufficient contrast to make it readable in sunny
environments"
([best practices](https://developer.roku.com/docs/developer-program/design/best-practices.md)),
and store artwork and splash screens must use "only broadcast-safe colors"
(criterion 6.4). Roku's own brand purple is Pantone Medium Purple C / `#4F01A3`
([Roku trademark guidelines](https://docs.roku.com/published/trademarkguidelines)) —
and is *theirs*, not a colour a channel should borrow. The system chrome default
in SceneGraph is a dark grey `#232323` with `#DDDDDD` text (Overhang defaults),
which tells you the expected ground: dark, low-chroma, content-forward.

### 1.6 The certification criteria that are really design rules

Reproduced from [certification criteria](https://developer.roku.com/docs/developer-program/certification/certification.md):

| # | Rule | Design consequence for us |
|---|---|---|
| **4.4** | Roku reserves the Options (`*`) button **during video playback**; apps may use it only when their own UI overlays the video | Our in-player settings sheet cannot be bound to `*` |
| **4.5** | Apps are "prohibited from overriding or interfering with Roku's system screensaver" | Cover-art screensaver is **out** in-app |
| **4.6** | Back "must directly return the user to the previous screen and/or state"; from the app's home screen it exits to Roku Home (one confirmation dialog permitted) | Same as `TV-DESIGN §1.7`, plus an explicit exit-confirm allowance |
| **4.7** | Thumbnails during trick play for VOD > 15 min | **Unmet.** Needs BIF or HLS/DASH thumbnails per title |
| **4.8** | Accessibility + closed captions; caption settings **in the Options menu**, with On / Off / On instant replay / On mute | Caption control moves to Options, not our own sheet |
| **4.9** | Instant replay rewinds **10–25 s** | Bind the replay key |
| **4.10** | Bookmarking for all VOD > 15 min, stored **≥ 30 days** | Our `WatchProgress` verb, inside a 16 KB registry |
| **4.13 / 4.14** | Continue Watching and Instant Resume — mandatory above 5 M streamed hours/month (US), effective 1 Oct 2026 | Not mandatory for us at launch; both are *available* and worth adopting (§3.4) |
| **5.1 / 5.2** | Deep linking for all media types; **Direct to Play** for voice | Our `archivewatch://` verb becomes `contentId` + `mediaType` |
| **6.4** | Splash + store artwork in broadcast-safe colours, FHD **and** HD | Two splash sizes; check `#FF5C35` for broadcast safety |

---

## 2. What the Roku system UI actually looks and feels like in 2026

### 2.1 The home screen (redesigned May 2026 — the first major change in a decade)

Roku began rolling out a reimagined home screen on **27 May 2026** to US devices
([NewscastStudio](https://www.newscaststudio.com/2026/05/27/roku-updates-home-screen-with-personalized-recommendations-and-new-navigation-features/),
[9to5Google](https://9to5google.com/2026/05/27/roku-home-screen-redesign/)). The
shape:

- **Three columns retained** — navigation far left, apps centre, ad panel right.
  The nav column is now **condensed to icons** rather than full names, taking
  much less width (9to5Google).
- Left rail items include **For You** (formerly What to Watch), Subscriptions,
  and a categories/genres section (PCWorld).
- The centre column stacks: **Top Picks for You**, a customisable **Quick
  Access** strip of app icons and submenu links, then the **app grid** — five
  icons per row by default, adjustable to 4 or 3 via Medium/Large tile settings
  (PCWorld).
- **Continue Watching**, **Save List**, "Best Across Your Streaming Services",
  "Jump To", and genre subsections under "What Are You in the Mood For?" are
  first-class rows (PCWorld).
- **Search is now inside What to Watch**, and users can browse 20+ genres and
  themes (NewscastStudio).

**What a Roku user therefore expects, before opening our app:** a persistent
left rail of icons; vertically stacked, horizontally scrolling rows; a Continue
Watching row that is *theirs*, not an app's; and a saved list. The system home
grid is icon tiles, not posters — which is why an app's own poster rows read as
a step *into* content rather than more of the same.

### 2.2 The right-hand context panel

Roku's own `GridPanel` component exists to reproduce a system behaviour the docs
describe directly: "when you navigate up/down/left/right in the grid, a new
right panel is displayed that contains information about the currently focused
grid item," with automatic focus handling and a default fade between panels
([GridPanel](https://developer.roku.com/dev/docs/gridpanel)). Panels stack
left-to-right as the user goes deeper.

This is a real Roku idiom with no Apple TV or Android TV equivalent: **the
metadata for the focused thing appears beside the list, not on a pushed
screen.** It is worth considering for Collections and for the Channels rail
(§6.4, §6.7) because it delivers "one screen, one purpose" while keeping depth
at zero.

### 2.3 The Options dialog

Pressing `*` on a highlighted item shows "additional choices or settings for the
highlighted item, such as adjusting audio, enabling captions, or modifying
picture settings"
([remote control buttons](https://developer.roku.com/docs/developer-program/design/remote-control-buttons.md)).
During full-screen playback with no app UI overlay, the *Roku* options menu
appears — a side panel — and users reach closed captioning through it
([Roku support](https://support.roku.com/article/turn-on-closed-captioning)).
Roku expects app settings to live here too (§1.6, best practices).

### 2.4 What leading channels do — and the one lesson to take from them

- **The Roku Channel**: rows-over-hero, genre browse, robust search — the
  reference implementation of Roku's own guidance.
- **Netflix on Roku** (2026 update): larger cinematic promo units at the top,
  dedicated Originals and Coming Soon rows, more rounded title boxes
  ([Cord Cutters News](https://cordcuttersnews.com/netflix-unveils-major-roku-app-update-with-enhanced-focus-on-original-and-upcoming-content/)).
  Netflix is the one publisher with enough leverage to ship a fully custom
  shell; we do not have that leverage and should not imitate it.
- **Pluto TV** (2026): moved the live guide out of the default view toward a
  Netflix-like recommendation feed, and moved side navigation "across the top in
  a horizontal row" with Live TV / Movies / TV Shows sections
  ([Cord Cutters News](https://cordcuttersnews.com/pluto-tv-test-upgrades-to-its-roku-app-hiding-the-live-guide-pushing-a-netflix-like-user-interface/),
  [TechTimes](https://www.techtimes.com/articles/320479/20260714/pluto-tv-tests-top-nav-redesign-backed-paramount-tech-stack-overhaul.htm)).
- **Plex** (Sept 2025): the same move — sidebar removed, top tabs added — and
  the user response is the most useful design evidence in this whole brief.
  Users report it "requires more button presses and is slower to use" with a
  D-pad, that it fragments the experience against Plex's own Android TV app, and
  that the frustration has not faded
  ([Plex forum](https://forums.plex.tv/t/roku-plex-ui-regression-sidebar-removed-top-tabs-now-request-classic-sidebar-toggle/935370)).

**The lesson:** top tabs cost a D-pad user a vertical trip to the top of the
screen and back on every navigation. A left rail costs a horizontal step from
the first column — which is where focus already is, because Roku's flow rule is
left-to-right. Two big publishers made this change for cross-platform
consistency and their Roku users noticed. We should not follow them; and our own
`TV-DESIGN §8` already bans "shipping the phone layout with bigger fonts,"
which is the same failure by a different route.

---

## 3. The Roku interaction grammar

### 3.1 The buttons and what each MUST do

From [remote control buttons](https://developer.roku.com/docs/developer-program/design/remote-control-buttons.md),
cross-checked against certification:

| Button | On a UI screen | During playback |
|---|---|---|
| **dPad** | Move the focus highlight up/down/left/right | Left/right pauses and reveals thumbnail scrubbing; up/down navigates playlists |
| **OK** | "Selects or activates the item in focus" | Either reveal a HUD with video information **or** toggle play/pause |
| **Back** | Previous screen (historical navigation preferred); from the app's home screen, "exit your app or reveal a way to exit" | Exit video, return to the referring screen |
| **`*` Options** | "Access a popup menu of contextual and/or global options" | **Reserved by Roku** when no app UI overlays the video (cert 4.4); passed to the app when app UI is overlaid |
| **Instant Replay** | No system response required | "Auto rewind the video 10–25 seconds and resume playback" (cert 4.9) |
| **Play/Pause** | Shortcut to play the featured item *without moving focus* | Toggle play/pause; must also work on ads |
| **Rew / FF** | Page through lists vertically/horizontally | Multiple speed increments, typically 3; press-and-hold accelerates |
| **Home** | Leaves the app entirely — never intercepted | Same |

Two of these have no analogue in our other TV builds and are worth naming:

- **Play/Pause on a browse screen is a shortcut that plays the featured item
  without moving focus.** On Home, that means Play/Pause anywhere plays the hero
  film. This is free "minimum clicks to consumption" and no other platform we
  ship offers it.
- **Rewind / Fast-Forward page through lists.** In a 25,000-title Browse grid
  that is the difference between usable and not.

### 3.2 What `*` is expected to open

On a UI screen: a contextual/global options popup for the focused item. In
practice on Roku that is where a channel puts **Settings** (best practices) and
where a user looks for **closed captions** (support docs, cert 4.8). It is *not*
where a user looks for navigation.

Practical consequence for Archive Watch: `*` on a focused poster should offer
the per-item verbs we currently bury behind long-press on Android TV and a
context menu on tvOS — Add to Favorites, Add to Playlist, More Like This, Play
from start / Resume, and (on a Library row) Remove. `*` on Home with nothing
item-specific focused should open **Settings + About/Attribution**.

### 3.3 Deep linking, and why it is stricter than ours

A deep link arrives as `contentId` + `mediaType` query parameters, delivered
either as a **Launch** (cold) or an **Input** (app already running) command; the
app "must be designed to execute the specified behavior required by each
mediaType"
([deep linking](https://developer.roku.com/docs/developer-program/discovery/implementing-deep-linking.md)).
Criterion 5.1 makes it mandatory for public video apps, and 5.2 requires
**Direct to Play** so a voice command launches straight into playback.

The strict part, from Roku's Continue Watching integration: when content is
launched from Continue Watching, apps "may not launch into a profile selection
screen, content details screen, or any other screen" — playback must begin
immediately ([Continue Watching](https://developer.roku.com/docs/developer-program/discovery/continue-watching.md)).

This is a genuine behaviour change from `archivewatch://item/{id}` semantics,
which lands on Detail. On Roku we need both routes and must not conflate them:
`mediaType=movie` from voice/Continue Watching → **play**; a browse/search
result → Detail.

### 3.4 Roku Search, Continue Watching, Save List

These are one stack, and joining it is the platform's answer to "home-screen
integration":

- **Roku Search** takes a JSON feed of catalog metadata — content ID, type,
  title, description, genre, rating, release date, artwork — validated in the
  Developer Dashboard. Searching *outside* an app surfaces matching content
  across participating apps and deep links in; searching *inside* an active app,
  "the Roku UI displays a partial overlay with content matching the search
  request," showing the active app's matches first and other apps below
  ([Roku Search](https://developer.roku.com/dev/docs/implementing-search)).
- Participating in Roku Search makes an app eligible for **Visual Search Results
  for Roku Voice, Roku Zones, and Save List**
  ([content engagement](https://developer.roku.com/dev/docs/engagement)).
- **Continue Watching** requires Roku Search + deep linking + bookmarking, then
  POST/PUT/DELETE calls at playback start, stop and completion; it renders as a
  row on the system What to Watch screen (up to 40 tiles) with a progress bar,
  and works across a user's linked Roku devices. Long-form only — short-form
  under 15 minutes is excluded (Continue Watching doc).

Search feed artwork must be 16:9 or 2:3 (4:3, 3:4 and 1:1 also supported)
([search feed](https://developer.roku.com/dev/docs/search-feed)) — our catalog is
overwhelmingly 2:3 with a 14.3% backdrop tail (Decision 097), so this is a
straight mapping.

**Note the tension with `TV-DESIGN §1.4`** ("no opaque for-you feed"): Continue
Watching publishes *the user's own* progress, which §1.4 explicitly permits.
Roku Zones and Save List likewise carry our editorial and the user's own saves.
Nothing here asks us to publish a model's opinion. Adopting the stack is
compatible with the guardrail.

### 3.5 Screensaver

Only standalone screensaver apps may include a screensaver; non-screensaver apps
"including but not limited to video/audio streaming apps" are prohibited from
including one, the `screensaver_title` manifest entry is blocked for other apps,
and screensavers may not take user input or play video
([screensavers](https://developer.roku.com/dev/docs/screensavers)). Certification
4.5 restates it.

**Our cover-art screensaver (PARITY §5) cannot ship inside the Roku channel.**
It could ship as a *separate* Archive Watch screensaver app — a real, on-brand
option worth an owner decision (§10).

### 3.6 Text entry

Roku ships voice-enabled keyboards: `DynamicMiniKeyboard` (A–Z, 0–9 — "typically
used for entering a search query") and the `DynamicKeyboard` family, which
"support text entry in multiple languages and voice entry in English and
Spanish"
([DynamicKeyboardBase](https://developer.roku.com/docs/references/scenegraph/dynamic-voice-keyboard-nodes/dynamic-keyboard-base.md)).
Roku tells developers to upgrade legacy keyboards to the dynamic voice-enabled
ones, and criterion 4.12 *requires* Roku voice keyboards for email, PIN and
password entry.

Our search screen therefore gets voice input for free by using the platform
keyboard — which is a better answer to `TV-DESIGN §3.6` ("text entry is the last
resort") than any of our other TV builds have.

---

## 4. What differs from Apple TV and Android TV — do not port

| Concern | tvOS | Android TV | **Roku** | Do not port |
|---|---|---|---|---|
| Focus visual | Parallax + floating card lift + shadow; `.card` button style | Elevation + scale + Material ripple | **9-patch focus bitmap** (ring/footprint) + explicit two-size step ([PosterGrid](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/postergrid.md), [ZoomRowList](https://developer.roku.com/dev/docs/zoomrowlist)) | Parallax; tilt; any "floating card" |
| Focus when a list loses focus | Focus simply moves | Focus moves | **Footprint** — a dimmed indicator marks where you were (`focusFootprintBitmapUri`) | Nothing: this is a Roku affordance we should *add*, not skip |
| Sizing | Points; scale transforms fine | dp; scale transforms fine | **Pixels on 3-px boundaries**; scale factors produce fractional pixels on the 2/3 downscale | Any `scale(1.08)` |
| Type | tvOS ramp 76/57/38/29/23 pt | sp scale | Named system fonts, no published ramp; ours to define, all /3 | The tvOS ramp verbatim |
| Nav shell | Sidebar-adaptable TabView | Focusable rail that expands | **ButtonBar**, `alignment` top or left, `autoHide` + `overlay` | Top tabs (§2.4) |
| Metadata for a focused item | Revealed on the card / pushed Detail | Revealed on the card | **Right-hand panel** beside the list (`GridPanel`) | — |
| Settings | A tab / a Settings scene | A screen | **Options (`*`) dialog** — best practices: settings "do not belong in primary UI" | A Settings tab |
| Screensaver | App can ship an idle mode | App can ship an idle mode | **Prohibited** in a streaming app | Our cover-art screensaver |
| Player transport | AVPlayerViewController; overlays allowed | Media3 PlayerView | `Video` node; `trickPlayBar` colours only | A custom scrubber (already banned by Decision 037 — Roku enforces it) |
| `*` / long-press | Long-press context menu | Long-press context menu | `*` on a focused item — **and reserved by the system during playback** | Binding `*` to in-player settings |
| Package | Hundreds of MB, bundled seed DB | Tens of MB, bundled seed DB | **≤ 4 MB**, assets fetched | A bundled catalog and any first-paint-from-seed design |
| Local durable storage | SwiftData (+ CloudKit) | Room / user.sqlite | **16 KB registry**; `cachefs:` is purgeable | An unbounded Library |
| Density | Dense is a virtue | Dense is a virtue | "Keep screen information density low; blank space is essential" | The Android TV shelf density verbatim |

**The "reads like an Android app on a Roku" tell list**, for the ship gate: a
top tab bar; a Settings entry in the nav; a focused card that lifts and shadows
instead of ringing; a scrubber we drew; a long-press instead of `*`; no `(*)`
indicator in the Overhang; a Back that goes to our Home instead of exiting from
our Home; text entry that isn't the platform voice keyboard.

---

## 5. What the Roku platform gives us for free

Worth stating before the proposal, because these change the build's shape:

| Roku component | What it is | Our surface |
|---|---|---|
| `ButtonBar` (SGDEX) | Top/left nav bar, `autoHide`, `overlay`, `renderOverContent`, footprint on focused-or-selected | The shell |
| `ZoomRowList` | Vertical list of horizontally scrolling rows where the focused row zooms; per-row zoom heights; row title, row counter ("3 of 14"), custom **row decoration** | Home |
| `PosterGrid` / `MarkupGrid` | Poster grids with 9-patch focus + footprint | Browse, Search results, filtered grids |
| `GridPanel` / panel stack | Grid with a right panel describing the focused item | Collections, Channels rail |
| `TimeGrid` | An EPG: channels as rows with a name at left, programmes sized by duration to the right; plus a **Now/Next** alternative view ([TimeGrid](https://developer.roku.com/dev/docs/timegrid)) | Channels |
| `DynamicMiniKeyboard` | Voice-enabled search keyboard | Search |
| Standard dialog framework | `StdDlgTitleArea` / `ContentArea` / `ButtonArea` / `SideCardArea` ([dialogs](https://developer.roku.com/dev/docs/standard-dialog-framework-nodes)) | Options, confirms, About |
| `Overhang` | 115 px top bar with logo, title, clock, `(*)` indicator | Chrome |
| SGDEX views | `GridView` (styles `standard` / `hero` / `zoom`; shapes `16x9` / `portrait` / `4x3` / `square`), `DetailsView`, `CategoryListView`, `SearchView`, `TimeGridView`, `MediaView` | The canonical screen set |

The **row counter** ("3 of 14") on `ZoomRowList` is quietly important: it is
Roku's own answer to "how long is this row," and on a 25,000-title catalog it is
an honest orientation cue that costs nothing. It is also exactly the sort of
thing `tvOS-DESIGN §1.8` would call a parser's note if we wrote it ourselves —
but as a *platform* affordance a Roku user already reads it as chrome, not copy.

---

## 6. Proposed design for Archive Watch on Roku

### 6.1 Canvas, grid, safe area

- **Design canvas: 1920×1080 FHD**, `ui_resolutions=sd,hd,fhd`, autoscaled to
  720p at 2/3. Every value below is divisible by 3.
- **Action-safe inset — the layout gutter: 96 px horizontal, 54 px vertical.**
  All interactive elements, focus rings *at rest*, row titles and poster
  captions live inside it. (Identical to `TV-DESIGN §4.2`; equals Roku's
  action-safe offset of (96, 53), rounded to a multiple of 3.)
- **Title-safe inset — the reading gutter: 192 px horizontal, 108 px vertical.**
  Any block of prose the viewer is meant to *read* — a synopsis paragraph, an
  empty-state explanation, the TMDb attribution notice, Settings body copy —
  starts here. This is new against every other Archive Watch platform and it is
  Roku's stated rule.
- **Content column: 1728 px** (1920 − 2×96). Divides evenly by 3, 6 and 12.
- **Focus ring bleed: 9 px.** A focused item's ring may extend to 87 px from the
  screen edge; nothing else may.
- **Overhang: 115 px**, our own colours (§6.4), logo left, clock right, `(*)`
  indicator right whenever Options are available on the current screen.
  Content begins at y = 115 + 54 = **169**.

**Poster geometry** (2:3 unless the item's own art says otherwise — Decision 097
binds here: *never reshape the art*):

| Use | Resting | Focused | Gutter | Per screen |
|---|---|---|---|---|
| Home shelf poster | 264 × 396 | **288 × 432** | 24 | 6 full + a peek |
| Browse grid poster | 192 × 288 | **210 × 315** | 24 | 8 across |
| 16:9 shelf item (TV, newsreel, channel) | 384 × 216 | **420 × 237** ⟶ round to 420 × 237 | 24 | 4 full + a peek |
| Hero art | full-bleed 1920 wide, fit at the image's own aspect over an ambient wash | — | — | Decision 097 |

Note the focused sizes are *stated*, not derived from a scale factor — §0/D2.
The 264→288 step is a 1.09× growth that lands exactly on 3-px boundaries in both
axes; 192→210 is 1.09× likewise.

### 6.2 Type scale — six levels, all divisible by 3

| Level | FHD px | HD px (auto 2/3) | Weight | Use |
|---|---|---|---|---|
| **Marquee** | 66 | 44 | Bold | Hero film title, Detail title |
| **Screen** | 45 | 30 | Bold | Overhang title, screen headings |
| **Row** | 33 | 22 | Bold | Shelf titles, section headers, button labels |
| **Body** | 27 | 18 | Regular | Synopsis, blurbs, settings rows |
| **Item** | 27 | 18 | Medium | Poster captions, list item titles |
| **Meta** | 24 | 16 | Regular | Year · runtime · category · row counter |

Floor is **24 px**, matching `TV-DESIGN §4.3`. A seventh level is refused
(`mobile-first-density-design`). Body and Item share a size and differ by weight
— that is the "three weights × two sizes" discipline expressed on a ten-foot
canvas.

Typeface: a bundled TTF is permitted but eats the 4 MB budget; the pragmatic
answer is **the Roku system font family** (`MediumSystemFont` /
`MediumBoldSystemFont` etc. with explicit sizes), which is also the most native
choice and costs zero bytes. Revisit only if the brand demands it (§10).

### 6.3 Focus treatment

Three signals, of which at least two are always present (`TV-DESIGN §3.2`):

1. **Size step** — the resting/focused pair in §6.1, via `ZoomRowList`'s
   `rowItemHeight` / `rowItemZoomHeight` on Home, and a swapped item component
   in grids.
2. **Ring** — a 9-patch `focusBitmapUri`, 3 px stroke, blended to **marquee
   orange `#FF5C35`** via `focusBitmapBlendColor`, drawn *on top*
   (`drawFocusFeedbackOnTop = true`) so it reads against a bright poster.
3. **Reveal** — the item's caption (title + Meta line) appears only on focus.
   Unfocused items carry no competing decoration (`TV-DESIGN §1.2`).

Plus the Roku-only fourth:

4. **Footprint** — when a row or grid loses focus, `focusFootprintBitmapUri`
   leaves a dimmed ring at the last position, blended to `#FF5C35` at ~35%
   opacity. This is how a Roku user finds their place after a trip to the rail
   or an Options dialog, and it is why the rail can `autoHide` without
   disorienting anyone.

**Never** an elevation shadow, a parallax tilt, or a scale transform.

### 6.4 Colour

The `CLAUDE.md` split is binding and unchanged: **brand for chrome, semantic for
content meaning, never crossed.**

| Token | Value | Use on Roku |
|---|---|---|
| Canvas | `#0B0B0C` | The ground. Dark-first; no light mode (`TV-DESIGN §4.4`) |
| Surface | `#16161A` | Overhang, rail, panels, dialog grounds (replaces Roku's stock `#232323`) |
| Marquee orange | **`#FF5C35`** | Focus ring, footprint, primary CTA (Play), trick bar fill, selected rail item, progress bars |
| Text primary | `#F2F2F2` | Titles, body |
| Text secondary | `#9A9AA0` | Meta lines, disabled |
| Category accents | Feature Film `#FF5C35` · Classic TV `#2D5BFF` · Silent `#C9A66B` · Animation `#FF4D8D` · Newsreel `#8A8F98` · Documentary `#3FA796` · Ephemeral `#7C5BBA` · Short `#E8A317` | **Content meaning only** — category tiles, the category chip on Detail, the collection spine. Never a focus ring, never a button |

**Accent blue `#0047FF` is not used on Roku.** It is a link colour from the web
palette; at ten feet on a dark ground it fails contrast, which is exactly why
iOS shipped a dark-appearance variant `#4D7DFF` (session log 2026-06-10). Roku
has no links. Where the web build would use accent blue, Roku uses marquee
orange (interactive) or text-secondary (informational). Record this as a Roku
row in the design system, not as a new colour.

Check `#FF5C35` against broadcast-safe limits before the splash and store
artwork are cut (criterion 6.4) — saturated orange is the classic offender.

### 6.5 The shell

```
┌──────────────────────────────────────────────────────────────────┐
│ [logo]  ARCHIVE WATCH            │            4:32 PM  │  (*)     │  Overhang 115px
├────┬─────────────────────────────────────────────────────────────┤
│ ⌂  │                                                             │
│ 🎞  │              content column, 1728px wide                    │
│ 📺 │              starts at y = 169                              │
│ 📡 │                                                             │
│ ▦  │                                                             │
│ 🔍 │                                                             │
│ ★  │                                                             │
└────┴─────────────────────────────────────────────────────────────┘
   ButtonBar, alignment="left", autoHide=true
```

- **`ButtonBar alignment="left"`, `autoHide = true`, `overlay = true`.** The
  rail is a column of icons + labels; it collapses to a hint when it does not
  have focus, so the content column gets the full 1728 px. Left from the first
  column of any row reveals it. This is the 2026 Roku home-screen shape and the
  shape Plex users are asking for back.
- **Rail items (7):** Home · Movies · TV · Channels · Collections · Search ·
  Library.
- **Settings + About/Attribution** live behind `*` on Home, per Roku best
  practices, in a Standard Dialog with a flat structure and one-click sub-screens
  (also best practices).
- **Surprise** is a *persistent action*, not a rail item: it is the first tile of
  the first Home row, an entry in the `*` dialog, and the Play/Pause shortcut
  target when nothing else is featured. It is a verb Roku's "minimum clicks to
  consumption" wants at hand, and a place Roku's rail does not want to spend an
  icon on. **This needs an IA exception (§9.1).**
- **Back** pops the panel/screen stack; from Home it shows a single "Exit
  Archive Watch?" confirmation and exits to Roku Home (cert 4.6 permits exactly
  one dialog).

### 6.6 Home

`ZoomRowList`, hero-led.

- **Hero (row 0).** Full-bleed art at the item's own aspect over an ambient wash
  (Decision 097 — never crop a 2:3 poster into a 2.4:1 box). Marquee title (66),
  a Meta line (24), and a focusable **Play** button in marquee orange plus
  **Details**. Rotates on the same pool as the other platforms. Play/Pause
  anywhere on Home plays this film without moving focus (§3.1).
- **Rows below** are the shared shelf set: Continue Watching first when
  non-empty, then curated + dynamic shelves, Top Rated, Hidden Gems, Community
  shelves, Director shelves, Public Domain Day, then **category tiles** and
  **decade tiles last** (matching every other platform).
- Each row gets a **row title** at 33 and the platform **row counter**, shown on
  focus. Shelf subtitles from `featured.json` render at Meta 24 under the title —
  the programmer's-note voice of `tvOS-DESIGN §1.8` transfers unchanged.
- Home gates on `hasProfessionalArtwork` (Decision 097). A shelf that cannot
  field 6 professional posters hides rather than pads.
- **Row decoration** (a `ZoomRowList` feature) carries the **category accent** as
  a 6 px spine to the left of a category row's title. This is the one place a
  semantic colour appears in the shell, and it is legitimate — the row *is* the
  content meaning.

### 6.7 Browse (Movies / TV)

- `MarkupGrid`, **8 columns × 192×288**, gutter 24, inside the content column.
- **Scope chips** sit above the grid on a single focusable row: Type · Decade ·
  Sort. Left/right moves between chips, OK opens a Standard Dialog list, not a
  pushed screen (depth ≤ 2 — `TV-DESIGN §2`).
- **Rew/FF page the grid** — a documented Roku behaviour and the only humane way
  through 25,000 titles.
- Focus-driven paging: fetch the next page when focus enters the last visible
  row. Item count and the active facets read in the Overhang title ("Movies —
  25,417 titles").
- TV Shows browses **series cards**, never loose episodes (Decision 036), and
  series → season → episode is the one place we accept depth 3 because the
  season list is a panel beside the grid, not a push (§2.2).

### 6.8 Search

- `DynamicMiniKeyboard` — the platform keyboard, so **voice entry comes free**
  and the app satisfies Roku's push toward dynamic voice keyboards.
- Layout: keyboard left, results grid right, updating incrementally as the query
  changes ("support incremental search" — best practices).
- **The no-typing doors are non-negotiable** (`TV-DESIGN §3.6`). Below an empty
  query, Search shows browse doors: Categories, Decades, Collections, Surprise.
  A Roku user who never lifts a finger to the keyboard must still be able to
  leave this screen with a film.
- Type/decade filter chips over the results — the parity gap tvOS closed in
  2026-08 and Roku should ship with from day one.

### 6.9 Detail

Roku's own shape (backdrop → title → meta → a horizontal button row → rows
below), which also keeps depth at ≤ 2:

```
  full-bleed art (own aspect, ambient wash), scrim to the bottom
  ┌ 192px reading gutter ─────────────────────────────────┐
  │  TITLE                                        (66)     │
  │  Also known as …                              (24)     │  Decision 100
  │  1943 · 50 min · Feature Film · ★ 6.8          (24)     │
  │  Synopsis, ≤ 3 lines at ten feet               (27)     │
  │                                                        │
  │  [ ▶ Play · 50m ]  [ ♥ Save ]  [ ⋯ More ]              │  Play auto-focused
  └────────────────────────────────────────────────────────┘
  Cast ▸ (16:9 person chips)
  More Like This ▸
  Part of: <Collection>  ▸
```

- **Play is auto-focused on entry** (`tvOS-DESIGN §3.4`), labelled with the
  runtime or "Resume · 21m left".
- The **category chip** carries the semantic accent; nothing else on the screen
  does.
- `*` here opens the item options: Add to Playlist, Play from start, Mark
  watched, Share (a QR to `archivewatch.org/item/{id}` — a Roku has no share
  sheet), Open on archive.org.
- Synopsis is capped and the full text is reachable through `*` → "Full
  description" in a Standard Dialog. Roku's density rule and the reading gutter
  both push against a wall of text here.

### 6.10 Player

- The **`Video` node owns the transport.** We recolour `trickPlayBar` to marquee
  orange and change nothing structural (Decision 037; Roku enforces it anyway).
- **OK reveals the HUD** carrying title + description — Decision 037's overlay,
  appearing and disappearing with the transport, non-interactive.
- **Instant Replay rewinds 15 s** (inside the required 10–25 s band, cert 4.9).
- **Captions** are configured through the Options dialog with Roku's four
  required states — On / Off / On instant replay / On mute — driven by the
  system caption preference (cert 4.8). Our WebVTT `vttURL` contract feeds it
  directly.
- **`*` is the system's during full-screen playback** (cert 4.4). Our in-player
  settings (speed, subtitle track, autoplay override) live in an **Up-reveals-
  HUD options row**, which also makes `*` legal for us while the HUD is up.
- **Bookmarking**: resume position stored per title, ≥ 30 days (cert 4.10),
  inside the 16 KB budget (§6.13).
- **Trick play thumbnails** (cert 4.7) — see §7.

### 6.11 Channels (EPG)

The single cleanest map in this brief. `TimeGrid` is literally our design:
"channels are represented as horizontal rows, one for each channel… a channel
name on the left, and a set of programs airing on that channel to the right. The
size of each program depends on its duration" — plus a **Now/Next** alternative
view ([TimeGrid](https://developer.roku.com/dev/docs/timegrid)).

- Our date-seeded `ChannelScheduler` ports as the content source; the *layout*
  is the platform's.
- Now-line, join-in-progress, commercial breaks woven — all unchanged verbs.
- Channel rail on the left carries the preset icons; the **Now/Next view is the
  low-end-device degradation path** (designing-for-devices) rather than a
  reduced grid we design ourselves.
- User-created channels: creating one needs a form, which needs text entry —
  ship the *presets* at v1 and defer creation with a recorded reason.

### 6.12 Collections

`GridPanel`: the collection list on the left, a **right panel** describing the
focused collection — blurb, count, a strip of its posters — updating as focus
moves. OK enters the collection as a full grid. This is Roku's own home-screen
behaviour (§2.2) and it delivers `tvOS-DESIGN §1.1`'s "one door to curiosity"
without a navigation push.

### 6.13 Library

Sections: Continue Watching · Favorites · Playlists · Watched/History.

**The constraint that shapes this screen:** `roRegistry` caps an app's
persistent storage at **16 KB**
([roRegistry](https://developer.roku.com/docs/references/brightscript/components/roregistry.md)),
and Roku offers no durable file storage beyond it (`cachefs:` is purgeable). Our
`archiveID`s average ~25 bytes. Budgeting ~12 KB for user state gives roughly
**400–500 saved items total** across favorites, playlists and progress with a
compact encoding.

Design response:

- Publish to **Roku Continue Watching** (§3.4) so progress lives in Roku's cloud
  and syncs across the user's devices, rather than competing for the registry.
- Cap Favorites at a stated number and render an honest **"Library is full"**
  state with a Remove affordance — a `universal-feature-states` requirement, and
  a place where honesty beats silent truncation.
- **Downloads: `n/a`**, exactly as tvOS (Decision 099) — Roku has no durable
  storage for a film either.
- No Clips tab (Clip Studio is never on a TV — Decisions 033/042).

### 6.14 Settings + About

A Standard Dialog opened by `*` on Home. Flat, one click to any sub-screen (Roku
best practices). Contents: mature-content filter (default on, Decision 012),
autoplay, category visibility, **TMDb attribution verbatim** (Decision 007),
source credits, **Donate to the Internet Archive** (Decision 010) as a QR, app
version. No sign-in at v1 (no CloudKit off Apple; Drive App Data is the
Android-family path — `TV-DESIGN §10`).

---

## 7. Feature mapping — what ports, what changes shape, what is dropped

Against `PARITY.md`.

### Maps cleanly (same verb, native component)

| Verb | Roku idiom |
|---|---|
| Home hero + shelves | `ZoomRowList` + hero row |
| Category / decade tiles | Tile row with accent spines |
| Continue Watching | Local bookmark **+ Roku Continue Watching** |
| Movies / TV browse + facets + paging | `MarkupGrid` + chips, Rew/FF paging |
| Series → season → episode | Grid + right panel |
| Collections | `GridPanel` |
| Search (FTS5) | `DynamicMiniKeyboard` + results grid, incremental |
| Detail + More Like This + cast | Roku details shape, Play auto-focused |
| "Also known as" | One line under the title (Decision 100) |
| Playback + resume | `Video` node + bookmarks ≥ 30 days |
| Subtitles | WebVTT via the Options caption control |
| Channels EPG | `TimeGrid` (+ Now/Next) |
| Surprise | Persistent action (see §9.1) |
| Cartoon Mode | A filtered grid + marathon lineup |
| Favorites / Playlists / Watched | Library, capacity-bounded |
| Mature filter, attribution, donate | Options dialog |
| Deep links | `contentId` + `mediaType`; Direct to Play |

### Changes shape on Roku

| Verb | Why it changes | New shape |
|---|---|---|
| **Settings** | Roku: settings "do not belong in primary UI" | Behind `*`, not a rail item |
| **In-player settings sheet** | `*` is reserved during playback (4.4); captions belong to Options (4.8) | Up-reveals-HUD options row + system Options |
| **Per-item context actions** | No long-press on a Roku remote | `*` on the focused item |
| **Share** | No system share sheet | QR to `archivewatch.org/item/{id}` (the tvOS pattern) |
| **Surprise** | Roku's rail is short; the verb is an action | First Home tile + `*` entry + Play/Pause shortcut |
| **First launch** | 4 MB package: no bundled seed | An honest, designed catalog-loading state; not a fake instant paint |
| **Library** | 16 KB registry | Capacity-bounded with a real full-state; progress pushed to Roku's cloud |
| **User-created channels** | Requires text entry | Presets at v1; creation deferred with a reason |

### Deliberately dropped, with reasons

| Verb | Why |
|---|---|
| **Cover-art screensaver** | **Prohibited** — cert 4.5 + screensaver policy (only standalone screensaver apps). Could ship as a separate app (§10) |
| **Clip Studio / Creation Studio** | Never on a TV (Decisions 033/042; `TV-DESIGN §2`) |
| **Downloads / offline** | No durable storage — same reason as tvOS (Decision 099) |
| **SharePlay / Watch Together** | Apple-only framework; no Roku equivalent |
| **Cast / AirPlay send** | Roku is a *receiver* platform; sending is meaningless here |
| **Picture-in-Picture** | Not a Roku app affordance |
| **Background media controls** | `TV-DESIGN §5.4` — a video app pauses on switch-away |
| **Sign-in + cross-device sync** | `TV-DESIGN §10`, first wave. Roku's own Continue Watching gives cross-device *progress* without an account of ours |
| **VHS effect / Party Play** | Ambient polish; 30 fps floor and low-end hardware make it a poor first bet. `🔮` |

### Blocked on new pipeline work (not design)

| Requirement | Gap |
|---|---|
| **Cert 4.7 — trick-play thumbnails for VOD > 15 min** | No BIF archives and no HLS/DASH thumbnail tracks exist for the catalog. The `bifTool` generates SD/HD/FHD `.bif` per title ([BIF creation](https://developer.roku.com/docs/developer-program/media-playback/trick-mode/bif-file-creation.md)); ~30k titles is a real CI programme, and every title over 15 minutes needs one. **This is the largest single unknown in the Roku build and it is not a design problem.** |
| **Cert 3.7 — ≤ 4 MB package** | Catalog delivery must be entirely remote from first launch |
| **Roku Search feed** | A new JSON feed from the pipeline; unlocks Continue Watching, Save List, Roku Zones, Visual Search |

---

## 8. States, and the ship gate

Every list, grid, shelf and dialog declares **loading · loaded · empty · error**,
each user-visible (`universal-feature-states`, `CLAUDE.md`). Roku adds a hard
one: any visible process over 3 seconds shows a loading indicator (cert 3.4),
and there is no bundled seed to paint from, so **the cold-start loading state is
a designed screen, not a spinner** — a marquee, the brand, and honest progress.

Empty states must contain a focusable element (the Favorites focus-trap lesson,
`tvos-playbook §2.5`) — on Roku that means a real button, because with `autoHide`
on the rail an empty screen with nothing focusable is a dead end from which even
Left does nothing.

**The four tests before any Roku surface ships** (extending `TV-DESIGN §9`):

1. **The remote test.** D-pad + OK + Back + `*` only. Every function reachable,
   every screen exitable, Back from Home offers exit.
2. **The ten-foot test.** Shrink a screenshot to 25%. Focus obvious? Primary text
   readable? Reading text inside the title-safe box?
3. **The parity test.** Is this verb defined elsewhere in `PARITY.md`? Implement
   *that verb* in this idiom.
4. **The Roku test (new).** Does anything on this screen appear on the §4
   "reads like an Android app" tell list? And does every dimension divide by 3?

---

## 9. Conflicts between Roku convention and house style

### 9.1 Settings and Surprise leaving the nav vs. the inherited IA — **Roku wins, with an amendment**

`TV-DESIGN §2` says the top-level surfaces are *exactly* those of
`tvOS-DESIGN §2` and that "adding, removing, or renaming a top-level surface on
a TV build is a change to tvOS-DESIGN, not a local decision." Roku's own best
practices say settings "do not belong in primary UI such as the Home screen of
your app," and Roku's rail is an icon column of ~5–6 entries.

Nine rail items would be un-Roku; and a Settings tab on Roku is the same
category of error as a bottom tab bar on a TV.

**Recommendation:** Roku wins on placement, and the resolution is an amendment,
not a local exception. `tvOS-DESIGN §2` should gain a distinction the IA does
not currently make — **surface vs. action**. Settings and Surprise are already
treated differently across our platforms (macOS puts Settings in a Settings
scene; iOS removed the modes row). Write the rule once: *a surface owns a place;
an action owns a verb and may be reached from several places.* Then Roku's
7-item rail + `*` Settings + ambient Surprise is a faithful expression of the
same IA, not a deviation from it.

### 9.2 `*` vs. the in-player settings sheet — **Roku wins, no contest**

`tvOS-DESIGN §8.2` puts subtitles, audio, speed and the autoplay override in one
transport sheet. Roku reserves `*` during playback (4.4) and requires caption
settings in the Options menu (4.8). This is certification, not taste. The sheet
becomes an Up-reveals-HUD options row for the controls Roku does not claim, and
captions go to Options.

### 9.3 "Blank space is essential" vs. our density rule — **both, correctly read**

Roku: "keep screen information density low; blank space is essential."
`mobile-first-density-design`: density comes from removing chrome, not adding
decoration. These agree on the mechanism and differ on the target. **Resolution:
keep the six-level type discipline and the no-decoration rule, and spend the
saved pixels on air rather than on a seventh row.** Concretely: 6 posters per
Home row where Android TV shows 6–7 in a tighter gutter, an 8-column browse grid
rather than a 9- or 10-column one, and a Detail synopsis capped at three lines.

### 9.4 Accent blue `#0047FF` — **drop it on Roku**

Not a real conflict; a colour with no job. Roku has no links, and at ten feet on
a dark ground a saturated blue at that luminance fails the contrast rule. It is
the same finding that produced iOS's `#4D7DFF` dark variant. Record a Roku row:
interactive = marquee orange, informational = text-secondary.

### 9.5 The row counter and shelf subtitles — **the platform affordance wins**

`tvOS-DESIGN §1.8` bans "raw counts as the whole subtitle" and pipeline
language. `ZoomRowList` renders "3 of 14" as *platform chrome*, in the same place
every Roku app puts it. **Keep it.** The rule is about our *voice* in our own
copy; the platform's position indicator is not our voice. Shelf subtitles in
`featured.json` are unchanged and still carry the programmer's note.

### 9.6 Roku Continue Watching / Save List vs. "no opaque for-you feed"

`TV-DESIGN §1.4` permits publishing "our own editorial shelves and the user's own
Continue Watching" to a platform home surface, and forbids a black-box model
row. Roku's Continue Watching row is the user's own progress; Save List is the
user's own saves; Roku Zones carries our editorial. **No conflict — adopt the
stack.** What §1.4 would forbid is us *rendering* a Roku-generated "Top Picks"
row inside our app, which we will not do.

---

## 10. Needs the owner's taste, not a rule

1. **Does Archive Watch ship a separate Roku screensaver app?** The cover-art
   screensaver is prohibited inside the channel but permitted as a standalone
   screensaver app — no user input, no video. A slowly drifting wall of
   public-domain poster art with a small "Archive Watch" mark is on-brand, is a
   second Roku store listing, and is the kind of thing Roku users install and
   keep. It is also unpaid work with no engagement metric. Ship it, defer it, or
   never?
2. **Is trick-play thumbnail generation worth the pipeline?** Cert 4.7 makes it
   mandatory for VOD over 15 minutes, which is most of the catalog. Generating
   BIF archives for ~25,000 titles is a substantial CI programme touching every
   film. There is no design workaround. This may be the number that decides
   whether Roku is funded at all (`PARITY §8b` still lists Roku as "a separate
   funded decision").
3. **How much Library does a Roku user get?** 16 KB is the platform's answer to
   a question we have never had to ask. A stated cap of, say, 300 favorites with
   a visible full-state is honest; silently dropping the oldest is not. What is
   the number, and does Roku Save List do the heavy lifting instead?
4. **Custom typeface or the Roku system font?** The system font costs nothing
   and looks most native; a bundled TTF costs real bytes against a 4 MB budget
   and makes Archive Watch look like itself. Every other platform uses the
   system face.
5. **Does the rail auto-hide?** `autoHide = true` gives the content 1728 px and
   matches how Roku's own condensed rail feels; `false` keeps the app's structure
   permanently visible, which serves the "learn how the archive is organised"
   goal in `TV-DESIGN §1.4`. This is a taste call about how much the shell should
   teach.
6. **Does Surprise deserve a rail icon after all?** It is our most distinctive
   verb and the one that best embodies wandering a repertory cinema. Roku's
   convention says an action does not spend a rail slot; our product says this
   action *is* the product. Worth an owner ruling before the rail is fixed.

---

## 11. Sources

**Roku official design guidance**
- [Designing Roku apps (overview)](https://developer.roku.com/docs/developer-program/design/design-overview.md)
- [General TV UI philosophy](https://developer.roku.com/docs/developer-program/design/general-tv-ui-philosophy.md)
- [Key design principles](https://developer.roku.com/docs/developer-program/design/key-design-principles.md)
- [Best practices](https://developer.roku.com/docs/developer-program/design/best-practices.md)
- [Designing for device capabilities](https://developer.roku.com/docs/developer-program/design/designing-for-device-capabilities.md)
- [Remote control buttons](https://developer.roku.com/docs/developer-program/design/remote-control-buttons.md)
- [Roku's master UI](https://developer.roku.com/dev/docs/masterui)

**Certification and specs**
- [Certification criteria](https://developer.roku.com/docs/developer-program/certification/certification.md)
- [Streaming Store graphics + safe zones](https://developer.roku.com/docs/specs/graphics.md)
- [tv-safe-zone-channel sample](https://github.com/rokudev/tv-safe-zone-channel)
- [Specifying display resolution (3-pixel rule)](https://developer.roku.com/dev/docs/specifying-display-resolution)
- [Screensavers policy](https://developer.roku.com/dev/docs/screensavers)
- [Closed caption](https://developer.roku.com/dev/docs/closed-caption)
- [Trick mode](https://developer.roku.com/docs/developer-program/media-playback/trick-mode/trick-mode.md) · [BIF file creation](https://developer.roku.com/docs/developer-program/media-playback/trick-mode/bif-file-creation.md)

**Components (design-relevant only)**
- [Overhang](https://developer.roku.com/docs/references/scenegraph/overhang-nodes/overhang.md)
- [PosterGrid (focus bitmaps)](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/postergrid.md)
- [ZoomRowList](https://developer.roku.com/dev/docs/zoomrowlist) · [Lists and grids](https://developer.roku.com/dev/docs/list-and-grid-nodes)
- [GridPanel](https://developer.roku.com/dev/docs/gridpanel)
- [TimeGrid (EPG)](https://developer.roku.com/dev/docs/timegrid)
- [DynamicKeyboardBase / voice keyboards](https://developer.roku.com/docs/references/scenegraph/dynamic-voice-keyboard-nodes/dynamic-keyboard-base.md) · [MiniKeyboard](https://developer.roku.com/docs/references/scenegraph/widget-nodes/minikeyboard.md)
- [Standard dialog framework](https://developer.roku.com/dev/docs/standard-dialog-framework-nodes)
- [Font](https://developer.roku.com/dev/docs/font)
- [Video node](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md)
- [roRegistry (16 KB limit)](https://developer.roku.com/docs/references/brightscript/components/roregistry.md)
- [SGDEX components (ButtonBar, GridView, DetailsView, CategoryListView, SearchView, MediaView, TimeGridView)](https://github.com/rokudev/SceneGraphDeveloperExtensions/blob/master/documentation/1-components.md)

**Discovery / engagement**
- [Deep linking](https://developer.roku.com/docs/developer-program/discovery/implementing-deep-linking.md)
- [Implementing Roku Search](https://developer.roku.com/dev/docs/implementing-search) · [Search feed (JSON)](https://developer.roku.com/dev/docs/search-feed)
- [Continue Watching](https://developer.roku.com/docs/developer-program/discovery/continue-watching.md)
- [Content engagement (Save List, Roku Zones)](https://developer.roku.com/dev/docs/engagement)
- [Roku trademark guidelines (brand purple)](https://docs.roku.com/published/trademarkguidelines)

**The 2026 system UI, and what other channels do**
- [Roku updates home screen with personalized recommendations and new navigation features — NewscastStudio, 27 May 2026](https://www.newscaststudio.com/2026/05/27/roku-updates-home-screen-with-personalized-recommendations-and-new-navigation-features/)
- [Roku rolling out home screen redesign — 9to5Google, 27 May 2026](https://9to5google.com/2026/05/27/roku-home-screen-redesign/)
- [Roku's new home screen is a big change — PCWorld](https://www.pcworld.com/article/3149985/rokus-new-home-screen-is-a-big-change-heres-how-to-use-it.html)
- [Plex Roku UI regression: sidebar removed, top tabs now — Plex forum](https://forums.plex.tv/t/roku-plex-ui-regression-sidebar-removed-top-tabs-now-request-classic-sidebar-toggle/935370)
- [Pluto TV tests top-nav redesign — TechTimes](https://www.techtimes.com/articles/320479/20260714/pluto-tv-tests-top-nav-redesign-backed-paramount-tech-stack-overhaul.htm)
- [Pluto TV test upgrades to its Roku app — Cord Cutters News](https://cordcuttersnews.com/pluto-tv-test-upgrades-to-its-roku-app-hiding-the-live-guide-pushing-a-netflix-like-user-interface/)
- [Netflix unveils major Roku app update — Cord Cutters News](https://cordcuttersnews.com/netflix-unveils-major-roku-app-update-with-enhanced-focus-on-original-and-upcoming-content/)
- [How to enable closed captioning (the Options side menu) — Roku Support](https://support.roku.com/article/turn-on-closed-captioning)
