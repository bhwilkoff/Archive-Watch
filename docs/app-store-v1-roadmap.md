# Archive Watch — App Store v1 Roadmap

Status: **planning** (created 2026-06-03). This is the cross-session source of
truth for the v1 backlog. Working tracker lives in the task list; this doc holds
the detail, sequencing, research notes, and decisions. Update it as phases land.

## How we work this backlog
- **Per feature**: invoke `learning-orientation-design` (the four-question test)
  before building, consult `docs/tvos-playbook.md`, then the relevant
  `all-ios-skills:*` / `KUI:*` skills. New UI surfaces are gated by the binding
  design doc (see F1).
- **Build before device test**: everything is verified on the tvOS 26.5 simulator
  first (build clean + on-sim screenshot/observability). Owner does on-device
  passes at phase boundaries.
- **Diagnostics-first**: reuse/extend the diagnostics harness (F3) for any
  behavior we can't directly observe; strip temporary overlays before a phase is
  declared done (CLAUDE.md debugging philosophy).
- **Quality bar**: scoped diffs, no feature creep, commit messages quote the ask.

## Decisions this backlog forces (resolve before the dependent phase)
- **D-A (accounts/sync, blocks Phase 3):** #11 reverses Decision 009 ("no
  accounts; all state local"). Recommended: **CloudKit private DB with the
  device's iCloud account — no Sign-in-with-Apple UI** — favorites/progress/
  playlists sync across the owner's Apple TVs automatically, zero login friction
  (keeps Decision 009's "no funnel" spirit while reversing "all local"). Needs a
  new DECISIONS entry once chosen. *Pending owner answer.*
- **D-B (upscale, #6):** real-time custom upscaling means replacing
  AVPlayerViewController with a manual AVPlayerItemVideoOutput→MetalFX→custom-layer
  pipeline (loses native transport + Now Playing + our resilient loader benefits),
  and Apple TV 4K already upscales to the panel. Recommended: **defer past v1**
  (spike only if owner wants). *Pending owner answer.*
- **D-C (#14 source):** BOBA-Playbook repo not present locally. Either owner
  supplies it or we build the cover-flow screensaver fresh. *Pending owner answer.*

---

## Phase 0 — Foundations (do first; unblocks the rest)
- **F1 — `docs/tvOS-DESIGN.md` binding design doc.** Invoke
  `binding-design-doc-discipline`. The app is well past 5 views and this backlog
  adds ~8 new surfaces (channels, cartoon/party overlays, people screens,
  playlists, screensaver, PD-day). Define the IA, navigation contract, shelf/
  overlay taxonomy, focus contracts, and the six-level type system so every new
  view quotes a rule. Highest leverage — prevents rework across Phases 1–5.
- **F2 — Resolve D-A/D-B/D-C** and log decisions (`/decision`).
- **F3 — Reusable diagnostics harness.** Generalize the playback overlay into a
  small toggleable on-screen + console diag framework (perf/focus/network/state),
  reused by every later phase. Owner explicitly wants robust diagnostics.
- **F4 — Continuous-playback engine (design + core).** A shared
  "queue → autoplay next → transition" service underpinning channels (#1), party
  play (#3), cartoon mode (#2), the screensaver (#14), and autoplay (#10). Build
  the engine once; the features are thin presentations over it.

## Phase 1 — Core quality & ship-blockers (bugs + data) — REQUIRED for submit
- **#19 — "no-entry" (crossed circle) on play.** Investigate with diagnostics.
  Likely a non-playable derivative / unresolved URL / decode reject surfacing the
  failure state. Determine the population (which items), fix matching/repair, and
  make the failure state recover or re-roll rather than dead-end.
- **#20 — wrong poster/description on vintage titles.** Modern poster + matching
  modern synopsis on an old film = a bad external match. Strengthen
  `remediate_catalog.py` wrong-match detection (year disagreement, era vs poster
  date) and the source-of-truth matching (TMDb/OMDb/Wikidata) so image + synopsis
  + title agree. Ties into the metadata-quality program (Tiers 0/1/3).
- **#18 — TV episodes mislabeled as movies.** Route the remaining single-item
  "films" that are really episodes into their show/season via the canonical TV
  spine (Decision 016, `build_canonical_tv.py` + `reconcile_tv_catalog.py`).
- **#17 — hide already-watched on Home.** Use `WatchProgress.isComplete` to
  filter completed titles out of Home shelves (keep them in Search/Browse and a
  "Watched" surface). Setting to toggle.
- **#7 — Documentary category surface.** Taxonomy already supports it; add the
  Documentary browse category + Home shelf + facet. Small.

## Phase 2 — Player completeness — REQUIRED for a credible streaming app
- **#5 — subtitles + audio language + video quality + speed.** Subtitles: prefer
  Archive sidecar caption files (SRT/VTT/SCC) as `AVMediaSelection`/sideloaded
  text tracks; research auto-generation (on-device `Speech` / `SFSpeechRecognizer`
  is heavy and English-biased — likely a post-v1 fallback, sidecar first). Audio/
  quality: expose `AVMediaSelectionGroup`s when present (progressive MP4 often has
  one of each — surface honestly, hide when single). Speed: `player.rate` presets.
- **#9 — info overlay + episode navigation.** Surface title/synopsis/cast and
  next/prev episode from the transport; episode prev/next already exists in
  `EpisodePlayerScreen` — generalize and add the info overlay.
- **#8 — skip intro / skip credits.** Per-title intro/credit timestamps (heuristic
  + optional curated data); a focusable "Skip" affordance. Pairs with autoplay-next.
- **#10 — autoplay options (global + per-video).** "Up next" engine (F4): same
  show / same category / same year / off. Global default in Settings + an override
  in the in-player settings for the current video.

## Phase 3 — Account & personalization (per D-A)
- **#11 — accounts + cross-Apple-TV sync.** Per D-A. Migrate favorites + watch
  progress (+ playlists) to the chosen store; conflict-resolution on sync.
- **#12 — playlists / custom collections.** Beyond Favorites: user-created lists,
  saved to the account store. New "Library" IA (per F1).
- **#16 — share a video.** AirPlay-to-phone is native; add a share surface
  (deep link `archivewatch://item/{id}` + archive.org URL, QR for phone hand-off
  — tvOS has no share sheet, so QR/handoff is the pattern).

## Phase 4 — People & connections, generated art
- **#4 — cast/crew + character connections.** People browse (scroll cast/crew
  images) → person page → other titles with that person; connect titles sharing a
  character. Needs people/character data (TMDb credits already partially present;
  characters need a join model). Strongly learning-oriented (invites exploration).
- **#13 — cover generation from video frames.** When no poster: extract candidate
  frames (`AVAssetImageGenerator`), score for actor faces (`Vision`
  `VNDetectFaceRectangles`) + visual interest, compose a cover. Build-time pipeline
  (CI) writing into the catalog; feeds #20's gaps.

## Phase 5 — Signature ambient / discovery features
- **#1 — 24-hour programming channels.** Era/genre/collection channels + a
  user-built channel from full-DB filters. A channel = a query + the F4 engine
  with a continuous "now/next" lineup and a guide. The flagship differentiator.
- **#2 — Cartoon mode ("cartoon wonderland").** A kid/ambient overlay scoping the
  whole app to animation (filter + simplified, big-target UI), with autoplay.
- **#3 — Party / background play.** Video-only, muted by default (audio toggle),
  autoplaying a curated high-contrast / visually-interesting queue.
- **#14 — iTunes-style cover-art screensaver.** Per D-C (BOBA-Playbook or fresh).
  A `tvOS` screensaver-style cover-flow over the catalog art.
- **#15 — Public Domain Day.** A "what entered the public domain in year N" browse
  + an annual celebration surface. Learning-oriented (teaches the PD calendar).

## Phase 6 — Advanced / uncertain
- **#6 — on-device upscale.** Per D-B; spike or defer.

---

## Suggested submit points
- **Minimum submittable:** end of Phase 2 (attribution, privacy manifest, icon,
  Top Shelf already done in prior hardening).
- **Recommended v1:** through Phase 3.
- **Signature v1 (owner's stated goal — build all before testing):** through
  Phase 5; Phase 6 optional.

## App Store review watch-items
- Sign in with Apple required *only if* we offer third-party login (we won't —
  CloudKit-auto avoids it). - Subtitles/accessibility are a plus. - All content
  is public domain (fine). - Privacy manifest already shipped; revisit if
  CloudKit/account data changes the data-collection disclosure.
