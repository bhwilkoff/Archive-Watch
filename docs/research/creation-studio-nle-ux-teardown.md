# Creation Studio — NLE timeline + stock-browser UX teardown (native macOS)

**Status:** research brief. Feeds the binding `CREATE-STUDIO-PLAN.md` /
`docs/macOS-DESIGN.md` work. Companion to:
- `docs/research/creation-studio-avfoundation-engine.md` (the export/compositing engine)
- `docs/research/creation-studio-proxy-remote-editing.md` (streaming-source editing)
- `docs/research/social-clip-creation.md` + `docs/research/video-clipping-native-frameworks.md` (the iOS Clip Studio basis)

**Why this doc exists.** Archive Watch's native macOS "Creation Studio" is a
multi-clip, multi-track timeline editor over archive.org public-domain video,
with a built-in stock-style clip browser (drawing clips from *many* archive
titles). The Mac app must be a **first-class Mac-native editor — keyboard-,
mouse-, and menu-driven — not the iOS Clip Studio touch UI shrunk onto a
trackpad.** This teardown (1) defines the timeline-editing mechanics of FCP /
Premiere / CapCut and recommends a v1 vs later split, (2) tears down
Storyblocks' (and the free-tier Pexels/Pixabay) browse/search/preview UX, and
(3) maps both onto native macOS SwiftUI/AppKit patterns with the SwiftUI-vs-
AppKit split called out.

**Audience reality (learning-orientation, CLAUDE.md).** Our users are *curious
archive browsers, not pro editors.* So the lodestar is **CapCut's
approachability layered on Mac-native precision** — direct-manipulation as the
default, the full ripple/roll/slip/slide tool model deferred, but with the
hover / right-click / keyboard-shortcut affordances a Mac power-user expects.
We do **not** ship a one-tap "auto fan-edit" (Decision 033 / CREATE-STUDIO-PLAN
§1): automate the mechanical (encode, reframe, thumbnails, attribution),
preserve the meaningful (which moment, what caption, where to cut).

A cross-app shortcut hazard to note up front: letter keys **collide** across
editors — `B` is FCP Blade but Premiere Ripple; `N` is FCP Snapping but
Premiere Roll. We pick *one* coherent scheme (§1.13), we don't blend theirs.

---

## Part 1 — Timeline editing mechanics (FCP vs Premiere vs CapCut)

Framing: **FCP and Premiere share the classic NLE vocabulary** — ripple / roll
/ slip / slide are the four canonical trim types, plus three-point editing and
source/program monitors. **CapCut deliberately omits that whole multi-mode
model**: it ships only split, drag-trim, ripple-style delete, and snapping on
one direct-manipulation timeline. That contrast *is* the design decision for
our audience.

### 1.1 Magnetic timeline (FCP) vs track-based (Premiere); CapCut's hybrid

- **FCP — Magnetic Timeline.** Trackless. A **primary storyline** (the spine)
  holds the main video/audio; supplementary media attaches as **connected
  clips** above/below. Adding/moving/deleting auto-adjusts neighbors to "close
  up gaps, avoid clip collisions, and keep all the elements of your story in
  sync"; moving a storyline clip moves its connected clips with it. Relation =
  *attachment + adjacency*, not a track address.
  ([Apple — Intro to the Magnetic Timeline](https://support.apple.com/guide/final-cut-pro/intro-to-the-magnetic-timeline-verb8fcfc133/mac); [Larry Jordan — Primary Storyline](https://larryjordan.com/articles/explaining-the-primary-storyline-in-apple-final-cut-pro/))
- **Premiere — track-based.** Clips sit on fixed lanes (V1/V2/V3, A1/A2/A3);
  relation = *track address + timecode*. Clips never auto-rearrange; deleting
  leaves a gap unless you ripple-delete. Track targeting governs where edits
  land. ([Adobe — Track targeting](https://helpx.adobe.com/premiere/desktop/edit-projects/intro-to-editing/work-with-clips-on-the-timeline-using-track-targeting.html))
- **CapCut — simplified hybrid.** One **main track** that behaves *magnetically*
  (clips snap together to avoid gaps; toggleable) plus stacked **overlay
  tracks** above for picture-in-picture; choosing "overlay" auto-creates a new
  track. ([Filmora — CapCut timeline](https://filmora.wondershare.com/advanced-video-editing/capcut-timeline.html))

**Core difference:** FCP clips ripple to stay gapless and synced; Premiere
clips move only when you move them. **Trade-off:** magnetic = no accidental
gaps, story-first speed, but ripple can move things you didn't intend (FCP adds
a Position tool + gap clips to fight this); tracks = deterministic control and
mature compositing, but manual gap management and easy sync drift.

> **Our pick:** a **CapCut-style hybrid** — a magnetic **main track** (no
> accidental gaps for novices) + a few **overlay/audio tracks** above/below for
> picture-in-picture, text, and music. This is also what the iOS Clip Studio's
> single-clip model grows into naturally. We do **not** expose Premiere's
> free-floating track grid in v1 (too much rope for a non-pro).

### 1.2 Core trim/edit operations (defined)

| Op | Definition | FCP | Premiere | CapCut |
|---|---|---|---|---|
| **Trim (regular)** | Shorten a clip; leaves a gap | — | Selection `V` drag edge | — |
| **Ripple trim** | Trim a clip *and* shift downstream clips to close the gap (changes total duration) | **default** (Select `A`/Trim `T`) | Ripple Edit `B` | drag end-handle (auto-ripples) |
| **Ripple delete** | Remove clip/gap *and* close the gap (vs lift = leaves gap) | `Delete` ripples; `Shift-Delete` lifts | `Shift+Delete` ripples; `Delete` lifts | Delete / Delete-left/right |
| **Roll** | Move the shared cut between two adjacent clips — one grows as the other shrinks; total length constant | Trim `T` | Rolling Edit `N` | — |
| **Slip** | Change *which portion* of a clip's source shows (in/out shift together); position + duration unchanged; neighbors unaffected | Trim `T` | Slip `Y` | — |
| **Slide** | Move a clip along the timeline keeping its own in/out; neighbors ripple to absorb; total length constant | Trim `T` | Slide `U` | — |
| **Blade / split / razor** | Cut one clip into two at a frame | Blade `B`; at playhead `Cmd-B` | Razor `C`; Add Edit `Cmd/Ctrl+K` | Split (`Cmd/Ctrl+B`) |
| **Snapping** | Dragged items jump to align with edges / markers / playhead | toggle `N` | toggle `S` | auto-align toggle |
| **Three-point editing** | Set 3 of {source-in, source-out, timeline-in, timeline-out}; the app infers the 4th | Mark In `I` / Out `O` → Insert/Connect/Overwrite | `I`/`O` → Insert `,` / Overwrite `.` | *none* (direct manipulation only) |

Sources: [Apple — Extend or shorten clips](https://support.apple.com/guide/final-cut-pro/extend-or-shorten-clips-ver9847ec25/mac), [Apple — Slip edits](https://support.apple.com/guide/final-cut-pro/make-slip-edits-ver1632d8e4/mac), [Apple — Cut clips in two](https://support.apple.com/guide/final-cut-pro/cut-clips-in-two-ver4e30479/mac), [Apple — Snap to items](https://support.apple.com/guide/final-cut-pro/snap-to-items-in-the-timeline-ver9f7888dc3/mac), [Apple — Intro to three-point editing](https://support.apple.com/guide/final-cut-pro/intro-to-three-point-editing-ver549f2208/mac); [Adobe — Ripple](https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-ripple-edits.html), [Rolling](https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-rolling-edits.html), [Slip](https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-slip-edits.html), [Slide](https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-slide-edits.html), [Lift/extract/ripple-delete](https://helpx.adobe.com/premiere-pro/how-to/lift-extract-ripple-delete-premiere.html); [CapCut — Split](https://www.capcut.com/resource/split-video-into-parts).

> **The simplification that defines CapCut (and us):** CapCut has **no separate
> trim tools or modes.** You tap a clip and **drag the white end-handles** to
> trim, and tap **Split** to cut — one gesture replacing the entire
> ripple/roll/slip/slide toolset, and dropping the source/program three-point
> model entirely. This is *the* approachability move and our v1 default.

### 1.3 Multi-track layering & compositing order

All three converge on the same three per-upper-element controls — **opacity,
blend mode, scale/position** — and in all three an opaque upper element fully
obscures what's below unless alpha/keying/opacity/blend applies.

- **Premiere:** higher-numbered video tracks render **above** lower; composites
  bottom-up; alpha shows through. ([Adobe — Compositing/alpha/opacity](https://helpx.adobe.com/premiere-pro/using/compositing-alpha-channels-adjusting-clip.html))
- **FCP:** *vertical screen position* (not a track number) determines stacking;
  a connected clip above the storyline is on top and "completely obscures" it
  unless transparency/keying applies. ([Apple — Connect clips](https://support.apple.com/guide/final-cut-pro/connect-clips-ver7a77ef9e/mac), [Use compositing settings](https://support.apple.com/guide/final-cut-pro/use-compositing-settings-ver52cf3376/mac))
- **CapCut:** "top layers visible in front; bottom behind" — drag to reorder.
  ([CapCut blend modes](https://www.capcut.com/create/blend-modes-creative-video-photo-effects))

> **Our pick:** overlay tracks stack **higher = on top**, with per-overlay
> **opacity + scale/position** in the inspector for picture-in-picture and text.
> Blend modes are a later addition (the AVFoundation
> `AVMutableVideoCompositionLayerInstruction` opacity/transform ramps in the
> engine doc already cover opacity + transform; blend modes need the CIFilter
> pass).

### 1.4 Playhead / scrubber / skimming

- **FCP has two distinct cursors.** The **playhead** is the persistent line
  where playback/edits originate; the **skimmer** is a separate cursor that
  follows the pointer to preview *without moving the playhead*, and takes edit/
  playback priority when both are in the same clip. Toggles: Skimming `S`,
  Audio Skimming `Shift-S`. ([Apple — Intro to playback](https://support.apple.com/guide/final-cut-pro/intro-to-playback-veradb8241c/mac), [Skim media](https://support.apple.com/guide/final-cut-pro/skim-media-vere9ba3609/mac))
- **Premiere & CapCut:** playhead only; preview is by dragging the playhead.

> **Our pick:** FCP's **skimmer is a genuinely Mac-native idea worth stealing —
> it depends on pointer hover, which touch can't do** (this is exactly the kind
> of affordance that proves the Mac app isn't an iOS retread). Hovering the
> timeline previews that frame in the program monitor + shows a time readout,
> without disturbing the playhead. Implement via `.onContinuousHover` over the
> timeline (§3.11). Spacebar plays from the playhead.

### 1.5 Markers

Non-destructive reference points (cues, sync points, notes, to-dos, chapters,
beats). Add `M` in all three. FCP types: Standard/To-Do/Chapter
(`Option-M` to edit). Premiere: Comment/Chapter/etc. (`M` again to edit). CapCut
is known for **beat markers** auto-placed on detected audio beats.
([Apple — Intro to markers](https://support.apple.com/guide/final-cut-pro/intro-to-markers-ver397279dd/mac), [Adobe — Markers](https://helpx.adobe.com/premiere-pro/using/markers.html), [CapCut — markers/labels](https://www.capcut.com/create/timeline-organization-markers-labels))

> **Our pick:** simple **markers (`M`)** for v1 — a single type, name optional.
> Beat-sync markers are a later, high-delight addition (deferred to match the
> CREATE-STUDIO-PLAN v2 "beat-sync" item).

### 1.6 J-cuts and L-cuts

Both are **split edits** — the audio cut and video cut fall at different frames
(named for the timeline shape, audio below video).
- **J-cut:** the *incoming* clip's audio starts **before** its picture (sound-
  first reveal) → audio extends leftward → "J".
- **L-cut:** the *outgoing* clip's audio **continues after** its picture cuts
  away (holds a reaction / smooths dialogue) → audio extends rightward → "L".
Creation rule across all editors: **detach/unlink audio from video, then offset
one track past the other.**
([Adobe — L and J cuts](https://www.adobe.com/creativecloud/video/post-production/cuts-in-film/l-and-j-cut.html), [Create J/L cuts](https://helpx.adobe.com/premiere/desktop/edit-projects/trim-clips/perform-j-cuts-and-l-cuts.html), [StudioBinder — J-cut](https://www.studiobinder.com/blog/what-is-a-j-cut-in-film/))

> **Our pick:** **later, not v1.** J/L cuts require detach-audio + independent
> audio-track trimming — meaningful only once we ship multi-track audio editing.
> v1's audio is "a music/voice overlay track," not frame-offset dialogue
> editing. Capture the requirement so the data model (separate audio sub-clips
> with independent in/out) doesn't preclude it.

### 1.7 Keyframing UI (opacity / volume / position / scale)

A keyframe records a property value at a time; 2+ keyframes interpolate between.
All three anchor keyframe creation to the **playhead**.
- **Premiere:** Effect Controls **stopwatch** to enable, plus clip **rubber-
  band** lines (Cmd/Ctrl-click to add opacity/volume keyframes, drag up/down).
  ([Adobe — Add keyframes](https://helpx.adobe.com/premiere/desktop/add-video-effects/control-effects-and-transitions-using-keyframes/add-keyframes.html))
- **FCP:** inspector **Keyframe button** (`Option-K`) + the Video/Audio
  Animation editor (`Control-V`) with per-parameter lanes + editable curves.
  ([Apple — Add video effect keyframes](https://support.apple.com/guide/final-cut-pro/add-video-effect-keyframes-ver8e3f20ea/mac))
- **CapCut:** a **diamond button** next to each property; set one, move playhead,
  change value → CapCut auto-creates the second keyframe + smooth interpolation.
  ([CapCut — keyframes](https://www.capcut.com/resource/how-to-add-keyframes-in-capcut))

> **Our pick:** **later.** The single highest-value keyframe case for our
> audience is a **volume rubber-band** (audio fade in/out) and an **opacity
> fade** on overlays — both expressible as a simple two-handle ramp on the clip
> (CapCut's diamond model is the friendliest reference). Full keyframe lanes /
> position animation are a power-user v2 feature. v1 ships fixed
> opacity/scale/position per overlay (no animation) + simple fade handles.

### 1.8 Zoom / fit-to-window; on-clip thumbnails & waveforms

- **FCP:** zoom `Cmd-+`/`Cmd--` (+ Zoom slider/tool `Z`); **fit project
  `Shift-Z`**. Clip Appearance toggles filmstrip thumbnails / waveforms / both /
  height. ([Apple — Zoom the timeline](https://support.apple.com/guide/final-cut-pro/zoom-in-to-and-out-of-the-timeline-ver4e2edcc/mac))
- **Premiere:** zoom `=`/`-`; **fit sequence `\`**. Display Settings toggles
  thumbnails / waveforms. ([Adobe — Navigate sequences](https://helpx.adobe.com/premiere/desktop/edit-projects/change-clip-sequence/navigate-sequences-in-the-timeline.html))
- **CapCut:** pinch / slider zoom; clips always render thumbnails + waveforms.

> **Our pick (v1):** filmstrip thumbnails + audio waveforms **on by default**
> (CapCut model — no toggle to learn). Zoom via **⌘-scroll / pinch** and a zoom
> slider; **fit-to-window** on a key. This drives the timeline-rendering
> architecture in Part 3.1 (thumbnails via `AVAssetImageGenerator`, waveforms
> via `AVAssetReader`).

### 1.9 Selection, drag-and-drop, adding clips from a browser

- **FCP:** click / marquee / Cmd-click / Range `R`. Browser→timeline keyboard
  edits: Append `E`, Insert `W`, Overwrite `D`, Connect `Q`; or drag-and-drop
  where drop position picks the mode. ([Apple — Select clips](https://support.apple.com/guide/final-cut-pro/select-clips-ver28912fd/mac), [Insert clips](https://support.apple.com/guide/final-cut-pro/insert-clips-ver4e2eff6/mac))
- **Premiere:** Selection (click / Shift-click / marquee); add via three-point
  Insert `,` / Overwrite `.` or **drag-and-drop from the Project bin** (the
  beginner path). ([Adobe — Three-point edits](https://helpx.adobe.com/premiere-pro/how-to/three-point-edits.html))
- **CapCut:** tap to select (handles appear); drag to reposition; **drag media
  onto the timeline to add** — no insert/overwrite distinction.

> **Our pick:** **drag-and-drop from the browser onto a track at a point in
> time is the primary "add" gesture** (CapCut/Premiere-beginner model), plus a
> double-click / "Add to timeline" button that appends at the playhead. No
> three-point editing in v1. This is the load-bearing browser↔timeline
> interaction (Part 3.9).

### 1.10 CapCut's approachability — what it removed / auto-handled

CapCut is built around **direct manipulation + AI automation on one timeline**,
collapsing the pros' multi-mode, multi-monitor, keyboard-driven workflow
(productive in ~15 min vs ~10–20 hrs to basic Premiere competence).
([sendshort — CapCut vs Premiere](https://sendshort.ai/guides/capcut-vs-premiere/))
- **Removed:** ripple/roll/slip/slide toolset + Trim mode; source/program three-
  point editing; multicam; deep color (scopes/Lumetri); pro audio mixing;
  nested sequences. ([miracamp — CapCut vs Premiere](https://www.miracamp.com/learn/premiere-pro/vs-capcut))
- **Auto-handled:** auto-captions (speech-to-text), caption templates, **Auto
  Cut** (AI rough cut), **beat sync**, templates/stickers/transitions libraries.
  ([CapCut — Auto Caption](https://www.capcut.com/tools/auto-caption-generator), [Auto Cut](https://www.capcut.com/resource/capcut-auto-cut), [Beat Sync](https://www.capcut.com/explore/beat-sync))

> **Our stance:** adopt CapCut's *interaction* simplicity (one timeline, drag-
> trim, tap-split, snapping, thumbnails/waveforms always on) but **reject its
> AI auto-edit** — the learning-orientation guardrail (Decision 033 §1) forbids
> a one-tap auto fan-edit. We automate the mechanical (encode/reframe/
> thumbnails/attribution); the human keeps the cut. Caption *styling* (not auto-
> transcription) and our auto-provenance credit are the parts we *do* take.

### 1.11 Recommended v1 timeline feature set (vs later)

**v1 (ship):**
- CapCut-style **hybrid timeline**: one magnetic main track + 1–2 overlay tracks
  (video/text) + 1 audio track.
- **Drag-trim** (drag clip end-handles; ripple-closes by default) — *the* trim
  model; no separate trim tools.
- **Split / blade** at playhead (key + button).
- **Ripple delete** (delete closes the gap) + plain delete (leaves gap on
  overlay tracks).
- **Snapping** to clip edges / playhead / markers (toggle).
- **Drag-and-drop from the browser** onto a track at a time-point; double-click
  to append at playhead.
- **Playhead + hover-skim preview** (Mac-native; §1.4).
- **Markers** (`M`, single type).
- **Zoom** (⌘-scroll / pinch / slider) + **fit-to-window**.
- **Thumbnails + waveforms** rendered on clips (always on).
- **Per-overlay opacity + scale/position** (static, in the inspector) for PiP /
  text placement.
- **Simple audio + opacity fade handles** (two-handle ramp, not full keyframes).
- **Provenance credit auto-burned** on export (carried from iOS Clip Studio).

**Later (v2+, same composition spine):**
- Ripple / roll / slip / slide as explicit tools (only if power users ask).
- Three-point editing (source/program in/out).
- J-cuts / L-cuts (needs independent audio-track trimming).
- Full keyframe lanes + position/scale animation + interpolation curves.
- Blend modes.
- Beat-sync markers; caption auto-transcription styling.
- Transitions between clips (cross-dissolve first).
- Multicam, nested sequences, color scopes — explicitly out of scope.

### 1.12 Where this lands vs the iOS Clip Studio

iOS Clip Studio (Decision 033) is **single-clip**: trim one archive film,
reframe, caption, export. The macOS Creation Studio is **multi-clip / multi-
track / multi-title** — the timeline + browser are the new surface area. The
**engine is shared** (AVFoundation `AVMutableComposition` /
`AVMutableVideoComposition`; see `creation-studio-avfoundation-engine.md`) — the
macOS port is a port, not a rewrite. The **interaction layer is fully re-
authored** for pointer + keyboard + menu bar (Part 3).

### 1.13 One coherent keyboard scheme (don't blend the editors' collisions)

Pick a single set, lean FCP-ish where it's the platform-native editor, but keep
the universal ones:

| Action | Key | Note |
|---|---|---|
| Play / pause | `Space` | universal |
| Split at playhead | `Cmd-B` | FCP/CapCut agree (`B` alone reserved-free to avoid the FCP/Premiere collision) |
| Ripple delete | `Delete` | FCP model (closes gap) |
| Delete (leave gap) | `Shift-Delete` | overlay tracks |
| Snapping toggle | `N` | FCP |
| Add marker | `M` | universal |
| Mark in / out (range) | `I` / `O` | universal (used for export range + trim) |
| Zoom in / out | `Cmd-+` / `Cmd--` | FCP |
| Fit to window | `Shift-Z` | FCP |
| Nudge selection ± frame | `,` / `.` | |
| Add selected browser clip at playhead | `E` | FCP "append" |

Every one of these is **also** a menu-bar item (the Mac discoverability layer,
Part 3.8) so users *learn* the shortcuts.

---

## Part 2 — Stock-library browse/search/preview teardown (Storyblocks et al.)

Goal: replicate the **browse → search → preview → add-to-timeline** UX of a
stock-video site for our archive.org clip browser, minus all licensing. The
closest analog is **Storyblocks** (curated library, rich faceting, folders); the
**free** peers (Pexels, Pixabay) show the no-paywall version of the same
patterns and are a better fit for our free model.

### 2.1 Browse by category / subject (Storyblocks)

Top level splits **Video / Audio / Images**, with a dedicated **Collections**
surface separate from search. The library is *deliberately curated and kept
small* — underperformers are pruned. ([storyblocks.com](https://www.storyblocks.com/), [/video/collections](https://www.storyblocks.com/video/collections), [shortgenius guide](https://shortgenius.com/blog/storyblocks))

Collections are organized on several axes at once: aesthetic/style, geographic,
lifestyle/activity, thematic/seasonal/emotional, creator spotlights. Each
**collection card** = thumbnail + title + asset-count + "View Collection". A
separate flat **Category** vocabulary (~19 subjects) powers the search facet:
*360°/VR, Aerial, Animals, Business, Effects, Food, Green Screen, **Historical &
Archival**, Holidays, Lifestyle, Medical, Nature, People, Places & Landmarks,
Slow Motion, Sports, Technology, Time Lapse, Transportation*.
([/video/search/filter](https://www.storyblocks.com/video/search/filter))

> **Note:** "Historical & Archival" already exists as a Storyblocks category —
> proof the curated-collection model fits archival content. We map our existing
> taxonomy (Decision 013 categories: Feature Film, Silent Era, Newsreel,
> Ephemeral, Animation…) + curated `featured.json` collections directly onto
> this two-tier (Collections + Category-facet) model.

### 2.2 Search

Top search bar with **related-search suggestion chips** below it (e.g. "filter"
→ "water filter, air filter"); a **Sort By** dropdown top-right; a prominent
total result count ("3,022,445 results found"). Results = a **multi-column
thumbnail grid** (~3–4 cols), each tile showing **duration overlaid on the
thumbnail**, a title beneath, and "NEW" badges. ([/video/search](https://www.storyblocks.com/video/search))

### 2.3 Hover-to-preview (the key mechanic)

- **Storyblocks:** hover surfaces inline **action affordances** — a "More Like
  This" button, a **heart** (favorite), and (if supported) an AI-edit icon;
  sibling variations render a "stacked cards" motif. Documented behavior
  emphasizes hover *controls* over hover *autoplay*. ([Storyblocks — favorites & more-like-this](https://www.storyblocks.com/resources/blog/favorites-and-more-like-this))
- **Pexels (the cleaner autoplay model):** hovering a tile **plays a truncated
  preview** of the clip *and* reveals Download / Edit / Add-Text buttons.
  ([musicformakers](https://musicformakers.com/blog/free-stock-video-footage), [pexels.com/videos](https://www.pexels.com/videos/))

> **Our pick:** **Pexels-style hover = autoplay a muted looping preview + reveal
> inline action buttons** (Add to timeline, Favorite/heart, More Like This,
> duration badge). Hover-autoplay is a pointer-only affordance — another place
> the Mac app earns its native-ness vs the touch iOS app. (Implementation
> gotcha: SwiftUI `.onHover` is unreliable on a fast grid — use `NSTrackingArea`
> / `NSCollectionViewItem`; Part 3.2.)

### 2.4 Filtering / faceting (Storyblocks)

Filters live in a **collapsible panel opened by a "Filters" button** (with an
**active-filter count badge** + **Clear All**), not a permanent sidebar.
([/video/search](https://www.storyblocks.com/video/search))

| Facet | Values | Keep for us? |
|---|---|---|
| Media Type | Footage / Backgrounds / Templates | partial (we have one media type) |
| **Orientation** | Vertical / Horizontal (Adobe adds Square/Panoramic) | **yes** |
| **Resolution** | HD / 4K / 8K | **yes** (archive derivative quality) |
| **Frame Rate** | 24 / 25 / 30 / 50 / 60 | maybe (if archive metadata carries it) |
| **Duration** | range slider | **yes** |
| Media Details | Model/Property Released | **drop** (licensing) |
| Usage Rights | Commercial / Editorial | **drop** (we're free PD/CC) |
| **Categories** | ~19 subjects | **yes** (map to our taxonomy) |

> **Our pick:** keep **Orientation, Duration (slider), Resolution, Category**
> (+ **decade/era**, which is the archive-native facet stock sites don't have —
> a real differentiator), invoked via a **Filters button + active-count badge +
> Clear All**. Drop every rights/release facet (Decision 027 already gates
> rights upstream).

### 2.5 Collections / favorites / boards

Storyblocks: **Favorites = folders.** Hover a clip → click the **heart** → a
dropdown of existing folders (searchable) + "create new folder." A "View All"
manager edits/copies/shares/deletes folders; inside a folder, select-all or
per-item to download/move/remove + search; folders are **shareable via link**.
([favorites & more-like-this](https://www.storyblocks.com/resources/blog/favorites-and-more-like-this), [Storyblocks support](http://support.storyblocks.com))

> **Our pick:** **folders/boards are the "add to project / save for later"
> primitive.** Hover heart → pick/create folder; a board manager with multi-
> select. This dovetails with our existing **playlists/collections** model
> (IndexedDB/SwiftData) — a Creation-Studio "shot bin" is just a board the
> timeline can pull from. (Local-only; cross-device follows the per-ecosystem
> sync islands, Decision 028 — not a stock-site account.)

### 2.6 "Preview then add/download" flow

Storyblocks: clicking goes to an **overview/detail page** (not just a modal)
where you can **download, search for similar, or open in their editor
("Maker")**; free tier = **watermarked** previews until licensed.
([EXPERTE review](https://www.experte.com/stock-photos/storyblocks)) Pexels:
click → **detail page** (`/video/{slug}`) with tags + related videos + multi-
resolution download, **no registration**. ([musicformakers](https://musicformakers.com/blog/free-stock-video-footage))

> **Our pick:** clicking a clip opens a **large preview** (a detail panel/sheet,
> or our existing Detail surface) with: scrub-able preview, **Add to timeline**
> (primary), **Add to board** (heart), **More Like This** strip, and **source
> provenance** (archive.org title/year/link — our attribution-as-feature wedge).
> **No watermark, no paywall, no license CTA** — we're free PD/CC.

### 2.7 "Similar / More Like This" (all three converge here)

Storyblocks surfaces "More Like This" on hover *and* on detail (contributor
variations) + a "search for similar" action; Pexels shows related videos on the
detail page. We already ship a **"More Like This"** in the apps — this validates
surfacing it both on hover (§2.3) and on the detail preview (§2.6).

### 2.8 Overall layout (and the free-tier peers)

- **Storyblocks:** top-nav + invoked filter panel (not a persistent left
  sidebar), 3–4 column thumbnail grid, duration-on-thumbnail, sort + count up
  top.
- **Pexels:** top nav, ~3–4 col grid, **infinite scroll with a Load-More
  fallback**, per-thumbnail Download/Edit on hover, detail page with related +
  resolution picker, **no login**. ([pexels.com/videos](https://www.pexels.com/videos/), [CapCut on Pexels](https://www.capcut.com/resource/pexels-videos))
- **Pixabay** *(page 403'd; search-excerpt sourced)*: resolution / effects /
  category filters, preview-before-download, 4 size options, **likes +
  collections**, full-res requires sign-up. ([pixabay.com/videos](https://pixabay.com/videos/), [moonb](https://www.moonb.io/blog/best-stock-video-sites))
- **Adobe Stock** *(contrast)*: facets add **Square + Panoramic** orientation;
  its **in-Premiere Stock panel** (browse + filter + drop watermarked comps
  straight into the timeline) is the closest paradigm to our **in-app browser
  feeding the timeline** — minus the watermark. ([helpx — Adobe Stock](https://helpx.adobe.com/stock/help/using-adobe-stock-website.html), [Stock panel in Premiere](https://helpx.adobe.com/premiere/desktop/edit-projects/intro-to-editing/use-built-in-adobe-stock.html))

> **Our pick:** **sidebar (source list of collections/categories/boards) →
> browser grid → detail preview**, 3–4 column grid, infinite scroll, sort +
> count header, **Filters button** for facets. On the Mac this becomes a
> `NavigationSplitView` (Part 3.6) — the *in-app browser feeding the timeline*
> is exactly the Adobe-Stock-panel paradigm, done free and native.

### 2.9 Patterns to lift (synthesis)

1. **Two-tier browse:** curated **Collections** cards (thumbnail + title +
   count) + a flat **Category/era** facet vocabulary.
2. **Hover = autoplay muted preview + inline actions** (Pexels), duration badge
   on the thumbnail.
3. **Faceting via a Filters button + active-count badge + Clear All**;
   Orientation / Duration-slider / Resolution / Category / **Era** — drop all
   rights facets.
4. **Folders/boards** as the save / "add to project" primitive (hover heart →
   pick/create), reusing our playlists model.
5. **Detail = large preview** with Add-to-timeline (primary) + Add-to-board +
   More-Like-This + provenance. No watermark/paywall.
6. **Grid:** 3–4 cols, infinite scroll + Load-More, count + sort header.

---

## Part 3 — Native macOS UI mapping (SwiftUI vs AppKit)

The guiding architecture: a **SwiftUI shell** carries most surfaces (sidebar,
inspector, toolbar, context menus, menu-bar commands, document scaffolding) with
**targeted AppKit bridges** where SwiftUI provably can't keep up (the timeline,
the dense hover-preview grid, modeless transport keys, the live drop indicator,
and the document backbone). **The whole point is pointer + keyboard + menu-bar
first — not the iOS Clip Studio touch UI on a trackpad.**

> Sourcing caveat: Apple's `developer.apple.com/documentation` + HIG pages are
> JS-rendered and returned empty bodies to the fetcher; those URLs are cited as
> canonical references, with the load-bearing claims corroborated from named
> Mac-dev blogs. Exact `@available` minor versions and the churning
> AVFoundation async-export signature must be confirmed against the live macOS
> SDK with `swift-api-digester` (the same probe the iOS Clip Studio migration
> used, Decision 033 §5c) — don't trust a blog's spelling.

### 3.1 High-performance custom timeline — **AppKit `NSView` + `CALayer`**

A scrolling, zoomable, multi-track timeline with per-clip thumbnails + waveforms
must stay smooth. **Recommendation: AppKit `NSView` + layer-backed `CALayer`,
hosted in SwiftUI via `NSViewRepresentable`. Do not ship a SwiftUI view-per-clip
timeline beyond a few hundred subviews.**

- **SwiftUI view-per-clip breaks down early.** Each clip needs container +
  thumbnail strip + waveform + trim handles; SwiftUI doesn't pool/reuse like
  AppKit, so stutter arrives at far fewer *clips* than raw counts suggest.
  ([DigitalBlake — SwiftUI vs AppKit perf](https://digitalblake.com/2026/04/28/swiftui-vs-appkit-macos-ui-performance/))
- **SwiftUI `Canvas`** draws much lighter than stacked shape views, but the
  enclosing `ScrollView` becomes the bottleneck on very large content and you
  lose native `NSScrollView` magnification + precise hit-testing. Viable only
  SwiftUI-only with your own viewport culling. ([swdevnotes — Canvas perf](https://swdevnotes.com/swift/2022/better-performance-with-canvas-in-swiftui/), [HWS — ScrollView+Canvas bottleneck](https://www.hackingwithswift.com/forums/swiftui/how-to-prevent-swiftui-scrollview-from-bottlenecking-performance-of-canvas/25306))
- **AppKit `NSView` + Core Animation = the sweet spot.** `wantsLayer = true`;
  back each clip with a `CALayer` (or `CATiledLayer` for very long strips);
  `drawsAsynchronously`, `shouldRasterize` for cached static art. GPU-composited,
  cheap to scroll/zoom, full hit-testing. ([Cameron Little — SwiftUI + Core Animation](https://camlittle.com/posts/2024-11-14-swiftui-core-animation/))
- **Metal (`CAMetalLayer`/`MTKView`)** = reserve for the heaviest continuous
  redraw (full-timeline waveform render, live scrub thumbnails) as a sublayer.
  ([CAMetalLayer](https://developer.apple.com/documentation/quartzcore/cametallayer))
- **Scroll + zoom:** `NSScrollView` `allowsMagnification`/`magnification`/
  `setMagnification(_:centeredAt:)` + `NSRulerView` for the time ruler. Drive
  **points-per-second from your own zoom factor and re-lay-out clip widths +
  waveforms** (keep track height fixed) rather than a uniform pixel scale that
  blurs everything. Trackpad pinch → `magnify(with:)` / `NSEvent` monitors.
  ([NSScrollView.magnification](https://developer.apple.com/documentation/appkit/nsscrollview/1403497-magnification))

(No primary source confirms FCP's internal renderer; the defensible claim is the
platform stack AppKit → Core Animation → optional Metal, not "FCP uses X.")

### 3.2 Media browser grid — **SwiftUI `LazyVGrid` → AppKit `NSCollectionView`**

**Start with SwiftUI `LazyVGrid` (fine to a few thousand items); migrate to
`NSCollectionView` once counts pass ~a few thousand *or* hover-preview stutters.**
Each cell carries a live hover-preview, so effective cell weight is high — plan
the NSCollectionView path as a likely destination.

- **What `NSCollectionView` adds:** real cell reuse (bounds memory),
  `NSCollectionViewPrefetching` (warm thumbnails before scroll-on),
  `NSCollectionViewDiffableDataSource` (animated batch updates on a changing
  library). ([Eon — diffable NSCollectionView macOS](https://eon.codes/blog/2021/08/25/diffable-collection-view-for-macOS/))
- **Async thumbnails:** `AVAssetImageGenerator` async batch APIs
  (`generateCGImagesAsynchronously(forTimes:)` / the WWDC22 `images(for:)`
  AsyncSequence), `maximumSize` for low-res, large `requestedTimeTolerance` when
  the exact frame doesn't matter; cache in `NSCache`; cancel on scroll-off.
  ([WWDC22 — responsive media app](https://developer.apple.com/videos/play/wwdc2022/110379/))
- **Hover-preview gotcha:** bare SwiftUI `.onHover` is unreliable on a fast grid
  (exit closures don't always fire → stuck previews). Use `NSTrackingArea`
  (`.mouseEnteredAndExited`, `.activeInKeyWindow`, `.inVisibleRect`) via
  `NSViewRepresentable`, or naturally inside the `NSCollectionViewItem`; on
  hover-in swap the static thumb for a muted looping `AVPlayer`, tear down on
  hover-out. ([importRyan — NSTrackingArea hover gist](https://gist.github.com/importRyan/c668904b0c5442b80b6f38a980595031))

### 3.3 Inspector panels — **SwiftUI `.inspector()`**

**Right tool, works on macOS.** `inspector(isPresented:content:)` (macOS 14+)
adds a trailing-edge column — the right-hand properties idiom for selected-clip
opacity/scale/position/volume. `.inspectorColumnWidth(min:ideal:max:)` to resize;
`InspectorCommands` for the Show/Hide menu item + shortcut. Content = a `Form` of
`LabeledContent` rows. Drop to a trailing `NSSplitViewItem`
(`behavior = .inspector`) only for multi-pane / custom collapse.
([inspector docs](https://developer.apple.com/documentation/SwiftUI/View/inspector(isPresented:content:)), [nilcoalescing — Inspector in SwiftUI](https://nilcoalescing.com/blog/InspectorInSwiftUI/), [Majid — Inspectors](https://swiftwithmajid.com/2024/04/30/inspectors-in-swiftui/))

### 3.4 Multi-window / document architecture — **`DocumentGroup` prototype → likely `NSDocument` backbone**

**The weakest SwiftUI seam.** Use `DocumentGroup` + `ReferenceFileDocument` for a
prototype, but **budget for an AppKit `NSDocument` backbone** (hosting SwiftUI via
`NSHostingController`) for a serious project editor — and **de-risk it with a
spike first.**

- A `.awproj` project = a `ReferenceFileDocument` (class/`ObservableObject`,
  snapshot save, undo hook) — fits "complex object graph mutated incrementally,"
  unlike value-semantic `FileDocument`. ([Building a document-based app with SwiftUI](https://developer.apple.com/documentation/swiftui/building-a-document-based-app-with-swiftui))
- **Limitations that bite:** the SwiftUI document model gives **no ready access
  to the document URL** (needed for relative media paths / render caches /
  security-scoped bookmarks to the user's archive cache), and
  `ReferenceFileDocument` saves have been observed **on the main thread** (UI
  hangs on big projects). Drop to `NSDocument`/`NSDocumentController` when you
  need reliable async/atomic save, the URL, autosave + versions, or robust menu
  control. ([eclecticlight — SwiftUI Documents](https://eclecticlight.co/2024/05/16/swiftui-on-macos-documents/), [ReferenceFileDocument writeup](https://medium.com/@acwrightdesign/using-referencefiledocument-in-swiftui-e54ef75a14b8))
- A separate single `Window` (non-document) for a **Render/Export Queue** is the
  right scene for that utility surface.

### 3.5 Toolbar — **SwiftUI `.toolbar(id:)` + `.windowToolbarStyle(.unified)`**

Customizable, unified-look toolbar in SwiftUI; `NSToolbar` only for advanced item
types. `.windowToolbarStyle(.unified)` for the single-row title+toolbar;
`.toolbar(id:) { ToolbarItem(id:) … }` for drag-rearrange + "Customize Toolbar…"
(auto-saved/restored); `ToolbarItemGroup` + `ToolbarSpacer` to cluster; `.navigation`
placement to fill from the left. Drop to `NSToolbar` for a tracking separator
aligned to a split divider (`NSTrackingSeparatorToolbarItem`) or pro segmented
groups. ([nilcoalescing — macOS toolbar styles](https://nilcoalescing.com/blog/AGuideToMacOSToolbarStylesInSwiftUI/), [Ohanaware — toolbar examples](https://ohanaware.com/swift/macOSToolbarExamples.html))

### 3.6 Sidebar / source list — **SwiftUI `NavigationSplitView` + `.listStyle(.sidebar)`**

`NavigationSplitView` (macOS 13+) three-column maps cleanly onto **sidebar
(collections / categories / boards) → browser grid → detail/inspector**, with the
translucent macOS sidebar + toggle for free. Leading column = `List(selection:)`
`.listStyle(.sidebar)` with `Section` headers + `DisclosureGroup`; widths via
`.navigationSplitViewColumnWidth`. Drop to `NSOutlineView` only for a deep,
drag-reorderable project navigator. ([NavigationSplitView docs](https://developer.apple.com/documentation/SwiftUI/NavigationSplitView), [Majid — Mastering NavigationSplitView](https://swiftwithmajid.com/2022/10/18/mastering-navigationsplitview-in-swiftui/))

### 3.7 Contextual menus / right-click — **SwiftUI `.contextMenu(forSelectionType:)`**

`.contextMenu { }` for single items; the selection-aware
`.contextMenu(forSelectionType:menu:primaryAction:)` for the browser grid /
timeline — `menu:` gets the Set of selected IDs (adapt to "Add 3 Clips to
Timeline"), `primaryAction:` runs on double-click/Return (double-click clip →
preview / add). Make the whole row a hit target with `.contentShape(Rectangle())`;
drop to `NSMenu` for right-click on empty canvas. ([contextMenu(forSelectionType:) docs](https://developer.apple.com/documentation/swiftui/view/contextmenu(forselectiontype:menu:primaryaction:)), [SerialCoder — selection/context menus macOS](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/))

### 3.8 Keyboard-shortcut-driven editing — **hybrid: SwiftUI `.commands` + AppKit `NSEvent` monitor**

The crux for a pro-feeling editor. **SwiftUI `.commands` for the menu-bar surface
+ `.keyboardShortcut`/`.onKeyPress` for view-local shortcuts; AppKit `NSEvent`
local monitor for the high-frequency modeless transport keys (Space, J-K-L,
arrow nudge, I/O).**

- **Menu bar (discoverability):** `.commands { CommandMenu("Timeline") … }` +
  `CommandGroup(after:/replacing:)` to splice `.undoRedo`/`.pasteboard`; each
  `Button` + `.keyboardShortcut(_:modifiers:)` auto-renders as a key equivalent
  *and teaches the shortcut*. ([danielsaidi — customizing the macOS menu bar](https://danielsaidi.com/blog/2023/11/22/customizing-the-macos-menu-bar-in-swiftui), [Majid — Commands](https://swiftwithmajid.com/2020/11/24/commands-in-swiftui/))
- **View-local:** `.keyboardShortcut(KeyEquivalent, modifiers:)` (chars, arrows,
  `.delete`/`.return`/`.space`); `.onKeyPress` (macOS 14+) for raw keys — but
  it's **focus-gated** (view must be `.focusable()` + hold focus; a parent
  returning `.handled` swallows children). ([onKeyPress docs](https://developer.apple.com/documentation/swiftui/view/onkeypress(_:action:)), [avanderlee — key press detection](https://www.avanderlee.com/swiftui/key-press-events-detection/))
- **Why AppKit for transport keys:** Space / J-K-L / nudge must fire regardless
  of which sub-panel has focus — routing through per-view focus is brittle. Use
  `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` inside an
  `NSViewRepresentable` scoped to the window; **gate on
  `NSApp.keyWindow?.firstResponder` not being a text view** so you don't steal
  typing. ([swiftjectivec — keyboard presses SwiftUI macOS](https://swiftjectivec.com/Handling-Keyboard-Presses-in-SwiftUI-for-macOS/))

This is where the §1.13 scheme lives.

### 3.9 Drag and drop (browser → timeline @ time) — **SwiftUI `.draggable`/`.dropDestination` + a `Transferable` clip-ref**

The load-bearing browser↔timeline interaction. **SwiftUI `.draggable` +
`.dropDestination` + a custom `Transferable` `ClipReference` type; add an AppKit
`NSDraggingDestination` lane only for a live, pointer-following drop indicator.**

- **Source cell:** `.draggable(_:)` with a lightweight `Transferable`
  `ClipReference` (archive id + in/out), keyed to a custom
  `UTType(exportedAs: "org.archivewatch.clipref")` — no media serialization.
- **Timeline destination:** `.dropDestination(for: ClipReference.self) { items, location in … }`
  — the `location: CGPoint` is exactly the hook for track + time:
  `track = Int(location.y / laneHeight)`,
  `time = (location.x + scrollOffset) / pixelsPerSecond`, snapped to edit points;
  `isTargeted:` to highlight. Also accept Finder files via
  `.dropDestination(for: URL.self)`. ([Adopting drag and drop in SwiftUI](https://developer.apple.com/documentation/SwiftUI/Adopting-drag-and-drop-using-SwiftUI), [dropDestination docs](https://developer.apple.com/documentation/swiftui/view/dropdestination(for:istargeted:action:)))
- **Limitation → AppKit:** SwiftUI gives the drop location only at *drop* time
  (`isTargeted` is a bool, not a position). For a **continuous "lands here, track
  2, 00:04:12" indicator**, wrap an `NSView` conforming to
  `NSDraggingDestination`, implement `draggingUpdated(_:)` (per-move
  `draggingLocation`). Practical split: SwiftUI for the data contract, an
  `NSViewRepresentable` lane purely for the live indicator. ([eclecticlight — SwiftUI drag and drop macOS](https://eclecticlight.co/2024/05/21/swiftui-on-macos-drag-and-drop-and-more/))

### 3.10 AVFoundation (playback + compositing + export) — **confirmed native spine**

The right native APIs, all macOS-supported, and **the same engine the iOS Clip
Studio already ships** (so this is a port — see
`creation-studio-avfoundation-engine.md`):
- **Preview:** `AVPlayer` + `AVPlayerItem` with `item.videoComposition` set;
  `AVPlayerView` (AVKit) for stock transport, or `AVPlayerLayer` in an
  `NSViewRepresentable` for the editor's custom program-monitor transport.
- **Composition:** `AVMutableComposition` (a track per lane,
  `insertTimeRange(_:of:at:)`) + `AVMutableVideoComposition`
  (`renderSize`/`frameDuration`/instructions with
  `AVMutableVideoCompositionLayerInstruction` opacity/transform ramps).
- **Modern (anchor on current SDK):** `AVVideoComposition(applyingFiltersTo:applier:)`
  + `AVAssetExportSession` async `export(to:as:)`. **Carry the iOS lesson:** the
  CIFilter (grade/blur) pass and the CALayer-overlay (caption/credit) pass
  **can't coexist in one `AVVideoComposition`** → two passes (grade →
  reframe+overlay). **Verify the async-export signature with `swift-api-digester`.**
- **Filmstrip thumbnails:** `AVAssetImageGenerator` async `images(for:)`
  (`requestedTimeTolerance = .zero` for frame-accurate strips, `maximumSize` for
  speed).
- **Waveforms:** `AVAssetReader` + `AVAssetReaderTrackOutput` over the audio
  track (Linear PCM), downsample to min/max per bucket (or `DSWaveformImage`).
([AVMutableComposition](https://developer.apple.com/documentation/avfoundation/avmutablecomposition), [AVMutableVideoComposition](https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition), [AVAssetImageGenerator](https://developer.apple.com/documentation/avfoundation/avassetimagegenerator), [WWDC22 — responsive media app](https://developer.apple.com/videos/play/wwdc2022/110379/), [DSWaveformImage](https://github.com/dmrschmidt/DSWaveformImage))

> **One caveat for *our* sources:** archive.org clips stream (Decision 021/031
> `ResilientStreamLoader`), but a multi-clip editor needs complete, seekable,
> `moov`-bearing local files for frame-accurate composition + thumbnails. See
> `creation-studio-proxy-remote-editing.md` — v1 downloads/proxies the clip
> window locally before editing (the iOS Clip Studio already downloads to
> Caches first, Decision 033). The timeline edits proxies; export can relink to
> full-res.

### 3.11 macOS vs iOS interaction — don't retread the touch UI

Design for **pointer + keyboard + menu bar** from the start. The iOS Clip Studio
*engine* ports ~1:1; the *interaction layer is re-authored.* HIG: Mac controls
are compact (~22–28pt, precise input) and **every mouse action needs a keyboard
equivalent** (primary ⌘-letter, secondary ⌘⇧/⌘⌥). Mac-only affordances to build
around (each one is a reason the Mac app isn't an iOS port):

| Mac affordance | API | Use in Creation Studio |
|---|---|---|
| **Hover** (no touch equivalent) | `.onHover`, `.onContinuousHover(coordinateSpace:)` → `HoverPhase.active(CGPoint)` | hover-skim the timeline (§1.4); browser hover-autoplay (§2.3) |
| **Cursor styling** | `.pointerStyle`/`.pointerVisibility` (macOS 15+) or `NSCursor.push()/pop()` | resize cursor on trim edges, crosshair on the timeline |
| **Right-click** | `.contextMenu(forSelectionType:)` | primary affordance, not afterthought (§3.7) |
| **Multi-select** | ⌘-click toggle / ⇧-click range / marquee, reading `KeyPress.modifiers`/`NSEvent.modifierFlags` | select clips + browser items |
| **Scroll-wheel + pinch zoom** | `MagnifyGesture`/`magnify(with:)`, ⌘-scroll | timeline zoom (§1.8) |
| **Menu bar** | `.commands` | the shortcut-discoverability layer (§3.8) |
| **Hover-reveal affordances** | `.onHover` | trim handles / per-clip overflow buttons appear on hover → dense-but-quiet timeline (the Mac analogue of tvOS "focus does the work" — here *hover does the work*) |
([HIG — Pointing devices](https://developer.apple.com/design/human-interface-guidelines/pointing-devices), [HIG — Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [PointerStyle docs](https://developer.apple.com/documentation/swiftui/pointerstyle), [nilcoalescing — tracking hover location](https://nilcoalescing.com/blog/TrackingHoverLocationInSwiftUI/))

### 3.12 The SwiftUI-vs-AppKit split (bottom line)

A **SwiftUI shell** with a small set of **AppKit bridges**:

| Surface | Choice | Why |
|---|---|---|
| Sidebar / source list | **SwiftUI** `NavigationSplitView` `.listStyle(.sidebar)` | native idiom, free toggle |
| Inspector | **SwiftUI** `.inspector()` + `Form`/`LabeledContent` | macOS-supported, low code |
| Toolbar | **SwiftUI** `.toolbar(id:)` + `.unified` | customizable, unified look |
| Context menus | **SwiftUI** `.contextMenu(forSelectionType:)` | selection-aware + double-click |
| Menu-bar commands | **SwiftUI** `.commands` | shortcut discoverability |
| Browser grid | **SwiftUI `LazyVGrid` → AppKit `NSCollectionView`** | reuse/prefetch/diffable + reliable hover at scale |
| **Timeline** | **AppKit `NSView` + `CALayer`** (`NSViewRepresentable`) | view-per-clip + Canvas-in-ScrollView stutter; need `NSScrollView` magnification + hit-testing |
| Transport keys | **AppKit `NSEvent` local monitor** | modeless Space/JKL/nudge SwiftUI focus-gating can't model |
| Live drop indicator | **AppKit `NSDraggingDestination`** lane (optional) | SwiftUI gives drop location only at drop |
| Drop data contract | **SwiftUI** `.draggable`/`.dropDestination` + `Transferable` | clean clip-ref transfer |
| Document backbone | **`DocumentGroup` prototype → likely `NSDocument`** | URL access, async save, security-scoped bookmarks |
| Engine (compose/export/thumbs/waveform) | **AVFoundation** (shared w/ iOS) | confirmed native spine; port not rewrite |

**De-risk first with a spike:** the **Documents** save/URL/bookmark path (§3.4)
and the **AppKit timeline** scroll/zoom/hit-test prototype (§3.1) — these are the
two places the architecture can go wrong late.

---

## Appendix — cross-app shortcut reference (source material)

| Operation | Final Cut Pro | Premiere Pro | CapCut |
|---|---|---|---|
| Ripple edit | default trim (Trim `T`) | `B` | drag handle (auto-ripple) |
| Ripple delete | `Delete` (ripples); `Shift-Delete` lifts | `Shift+Delete` (`Delete` lifts) | Delete / Delete-left/right |
| Roll | Trim `T` | `N` | — |
| Slip | Trim `T` | `Y` | — |
| Slide | Trim `T` | `U` | — |
| Blade / razor / split | `B`; at playhead `Cmd-B` | Razor `C`; Add Edit `Cmd/Ctrl+K` | Split; `Cmd/Ctrl+B` |
| Snapping toggle | `N` | `S` | auto-align |
| Mark in / out | `I` / `O` | `I` / `O` | — |
| Insert / overwrite | Insert `W` / Overwrite `D`; Append `E`; Connect `Q` | Insert `,` / Overwrite `.` | drag (no distinction) |
| Add marker | `M` (`Option-M` edit) | `M` (`M` again edit) | `M` |
| Set keyframe | `Option-K`; Animation editor `Control-V` | stopwatch + rubber-band | diamond button |
| Zoom in / out | `Cmd-+` / `Cmd--` | `=` / `-` | pinch / slider |
| Fit to window | `Shift-Z` | `\` | — |
| Skimming | `S` (skimmer is FCP-only) | n/a | n/a |

*Sourcing note (from research): several `helpx.adobe.com` article bodies timed
out on direct fetch, so a few Premiere lettered shortcuts (B/N/Y/U/C/S, `,`/`.`/
`\`/`=`/`-`) are corroborated from Adobe's own search-result excerpts + cross-
checked against FCP/CapCut pages rather than full-page reads; all sources agree.
The four canonical trim definitions and all FCP/CapCut mechanics were confirmed
from full page bodies. Apple developer/HIG pages are JS-rendered (empty to the
fetcher) — cited as canonical, claims corroborated via named Mac-dev blogs;
confirm `@available` versions + the AVFoundation async-export signature against
the live macOS SDK with `swift-api-digester` before relying on them.*
