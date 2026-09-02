# Archive Watch — iOS / iPadOS Design (BINDING)

**Binding.** Every new view, tab, shelf, sheet, grid, route, or toolbar item in
the iPhone/iPad app must trace to a rule in this document. When something feels
overwhelming or inconsistent, **fix this document first, then fix the feature.**
Proposals (and commits) cite the rule they implement, e.g. "per iOS-DESIGN §2.3."

Division of labor with the other docs:
- **This doc** = the *binding contract* for the iOS/iPadOS surface: navigation
  shell, touch idioms, Home composition, player rules, state rules.
- **`docs/tvOS-DESIGN.md`** = the tvOS contract. The two share verbs, never
  idioms (PARITY "same verb, native idiom"). When a rule below inverts a tvOS
  rule, that inversion is deliberate — do not "harmonize" them.
- **`PARITY.md`** = what ships where. Updated in the SAME change set as any
  user-facing feature (§12.4).
- **`DECISIONS.md`** = the why behind non-obvious rules (esp. 013, 017, 021,
  022, 025, 028).

All iOS UI lives in `ArchiveWatch/ArchiveWatch/iOS/*_iOS.swift` inside
`#if os(iOS)` guards, in the same universal target as tvOS. Shared logic
(CatalogDB, ResilientStreamLoader, ChannelScheduler, ContinuousPlayback,
SeriesStore, CloudKitSyncService) is consumed from Core, never duplicated —
the few deliberate iOS copies (SplitMix, Color hex, KidsContent) carry a
"don't let them drift" comment and are unification debt, not a pattern.

---

## §1 — Principles (the why)

1.1 **Same verb, native idiom** (Decision 028). The feature set matches tvOS;
the expression is whatever iOS users already know — tab bar, `.searchable`,
segmented pickers, swipe-to-delete, ShareLink, sheets with detents, pull
navigation. Never port a 10-foot layout to the phone; never invent a custom
control where a native one exists (`native-platform-first`).

1.2 **Touch replaces focus.** There is no focus engine. The tap is the verb;
the tile is the chrome. Density comes from removing decoration, not adding it
(`mobile-first-density-design`). Design for iPhone portrait first (~3 visible
poster tiles per shelf), then let iPad adapt (§2.2, §5.6).

1.3 **One shared data plane** (Decisions 017/028). The phone consumes the same
`catalog.sqlite` (seed → cached → downloaded), the same `featured.json`, the
same `series/*.json`, and the same CloudKit private database as the Apple TV.
No iOS-only catalog reads, hosts, or pipelines.

1.4 **Lean-in companion.** The Apple TV is the lean-back cinematheque; the
phone is where you wander, search, queue, and carry the archive with you.
Pure lean-back idioms (idle screensaver, muted Party wall) do not belong on
the phone (§10).

1.5 **Depth ≤ 2 from any tab root.** Tab → list/grid → detail. A would-be
third push must be a scope (segmented picker, Menu facet), a sheet, or a
different tab. Player and pickers present modally and don't count as pushes.

1.6 **Highest quality, faithfully presented.** Same as tvOS §1.6: never
degrade source quality (Decision 021); never crop or zoom real artwork into a
sliver (the Detail hero fits, never fills, §4.6); never ship a modern poster
on a vintage title.

1.7 **Voice: a programmer's note, never a parser's.** Shelf/section subtitles
follow tvOS-DESIGN §1.8 verbatim — evocative, ≤ ~8 words, no pipeline language
("most downloaded", "items", raw counts as the whole subtitle). Titles stay
plain. Copy lives in `featured.json` / `collection_metadata.json`, not Swift.

---

## §2 — Navigation shell

2.1 **Five content tabs, hard set: Home · Browse · Channels · Search ·
Library.** (Amended 2026-06-10, owner: "Channels should be a top level
navigation and not just a pill on the home page" — Channels graduated from
the Home modes row, which was removed in the same change.) Settings is
intentionally NOT a tab — it lives behind the gear in Home's nav bar,
presented as a sheet (a destination, not a peer of the content verbs). The
tab bar is reserved for content verbs; adding a sixth tab requires amending
this rule first. Search uses `role: .search` so the system places it
natively.

2.2 **One shell, both form factors.** The root is
`TabView(selection:)` + `.tabViewStyle(.sidebarAdaptable)` — bottom tab bar on
iPhone, sidebar on iPad/regular width. Do not add a parallel
`NavigationSplitView` code path; adaptivity comes from the one control. Views
adapt to regular width via `@Environment(\.horizontalSizeClass)` (the Home
hero's width-capped card is the pattern), never via `UIDevice` checks.

2.3 **One destination registry: `withItemDestination()`.** Every tab's
`NavigationStack` applies the single shared registry in `RootView_iOS.swift`
(`Catalog.Item` → Detail, `SeriesRef`, `CollectionRef`, `BrowseFilterRoute`,
`SurpriseRoute`, `PublicDomainRoute`, `ChannelsRoute`, `CartoonRoute`,
`ChannelScheduleRoute`). **A new pushable destination MUST be a `Hashable`
route registered there — never a per-view `navigationDestination`.** This is
what lets Home's tiles, Surprise's actions, and Search results all push the
same screens from any tab.

2.4 **Router owns navigation state.** `Router` (@Observable) holds the
selected tab and one `NavigationPath` per tab. Views navigate via
`router.push(_:)` / `router.openDetail(_:)`, which append to the *active*
tab's path — never construct `NavigationLink(destination:)` to a catalog
screen and never mutate another tab's path directly (Library's in-place
playlist drill-in is the one allowed `NavigationLink`, a value-less local
push).

2.5 **Siri, widgets, and deep links land in the `IntentInbox`** — the intent
or `onOpenURL` drops a `Request`; `RootView` consumes it once foregrounded.
New entry points (intents, widget URLs, `archivewatch://` hosts) extend
`IntentInbox.Request` + the `RootView.handle` switch; they never touch
`Router` directly from outside the view tree.

2.5b **Channels is a true EPG grid** (owner direction 2026-06-12: "the true
grid that is essential for it to feel like you are looking at a tv
listing"): pinned half-hour ruler (LazyVStack section header), fixed channel
rail (tap → full-day schedule), program blocks proportional to runtime on a
shared window (120 min compact / 180 min regular), vertical scrolling only —
the window pages via chevrons or a deliberate horizontal swipe (±90 min,
clamped to the broadcast day), with a NOW snap-back and red now-line. Never
regress it to a tile list.

2.6 **Modes are pushes on iOS, not takeovers.** Cartoon Mode, Surprise, and
Public Domain Day are ordinary pushed screens reached from Home's shuffle
toolbar button → Surprise grid (and registered per §2.3) — back-swipe always
works. (Channels is a tab per §2.1 since 2026-06-10; the Home modes pill row
was removed the same day — owner: the pills "are all accessible from the
'shuffle' button".) Only the player goes full-screen (§4.4). This
deliberately inverts tvOS-DESIGN §9 ("a mode replaces the shell"): on the
phone the nav bar IS the exit affordance.

---

## §3 — Surface taxonomy (the only allowed shapes)

Every iOS screen maps to exactly one. A new shape needs a new rule here first.

3.1 **Tab** — one of the four §2.1 verbs. `NavigationStack` +
`withItemDestination()`.
3.2 **Shelf row** — horizontal `ScrollView` + `LazyHStack` of `PosterTile`,
title + optional subtitle header, `.scrollIndicators(.hidden)` (Home, Detail
"More Like This", Cast, Cartoon shelves).
3.3 **Grid** — `LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))])` of
`PosterTile`, infinite-scroll paged where the set is large (Browse,
FilteredGridView at 60/page). The adaptive minimum is what makes one grid
serve iPhone and iPad.
3.4 **List** — native `List`/rows where the content is textual or row-shaped:
Collections, Channels guide, episodes, playlists, schedule. Swipe actions for
destructive verbs (§4.3).
3.5 **Detail** — scroll view: hero artwork → title/meta → action row (Play
prominent, Favorite, Add-to-playlist, Share) → synopsis → cast shelf → More
Like This. Series detail is the variant with season Menu + episode list.
An "Also known as …" line sits directly under the title when the film's
primary title differs from the Archive uploader's (Decision 100) — quiet and
secondary, never a second title competing with the first.
3.6 **Sheet** — transient pickers and forms: Settings (from the Home cog),
Add to Playlist (`presentationDetents([.medium, .large])`), Create Channel.
Pickers default to medium detent; forms that need a keyboard may open large.
3.7 **Full-screen cover** — the player, and ONLY the player (§4.4).
3.8b **Banner** — a full-width strip pinned above the tab shell, stating a
CONDITION that changes what the app can do (currently: offline). One line,
one action at most, no dismiss (it is not a message; it goes away when the
condition does). It is not an error toast and never carries content. A second
condition needs a rule here first — two stacked banners is a redesign signal,
not a layout.

3.8 **Tile** — `PosterTile` (2:3 poster + caption) for content;
gradient-on-accent compact tiles (category/decade/mode/surprise) for
navigation chips. New tile shapes extend these two, not a third family.

---

## §4 — Touch idiom (binding)

4.1 **`.buttonStyle(.plain)` on tiles is CORRECT on iOS.** Poster tiles,
category/decade tiles, and shelf cards wrap in
`Button { router… } label: { tile }.buttonStyle(.plain)`. This is the exact
inverse of the tvOS guardrail (tvOS-DESIGN §6.1) — there is no focus engine to
destroy here, and `.plain` keeps the artwork from being tinted as a button.
List rows that contain two tap targets use `.borderless` so both hit-test
(the Channels row pattern). Never apply the tvOS rule to iOS files or vice
versa.

4.2 **Native controls only.** Scopes = segmented `Picker` (Browse, Library).
Facets/sort = a toolbar `Menu` of Pickers (Browse's filter menu). Forms =
`Form`/`Section` (Settings, Create Channel). Search = `.searchable` with
`.navigationBarDrawer(displayMode: .always)` + a ~180 ms debounced
`.task(id: query)`. Sharing = `ShareLink`. Empty/error =
`ContentUnavailableView` (every list/grid/sheet declares loading · loaded ·
empty · error — `universal-feature-states`).

4.3 **Destructive verbs are swipe actions** (`onDelete`) on List rows —
playlists, user channels. Deletion of synced models goes through
`SyncNudge.recordDeletion`, never a bare `ctx.delete` (§9.4).

4.4 **`fullScreenCover` is for playback only.** Everything else transient is
a `.sheet`. Cover presentation binds to an **item**, not a Bool, whenever the
content is data-dependent — `fullScreenCover(item:)` for episodes and
`ChannelLineup` boxes (the `isPresented:` race shipped a black player once;
see the `unsolved_tv_episode_playback` memory). The cover content applies
`.ignoresSafeArea()`.

4.5 **Pickers open at medium detent.** Selection sheets that act on the
current screen (Add to Playlist) use `presentationDetents([.medium, .large])`
so the context stays visible behind them.

4.6 **Artwork is never silently cropped where it is the subject.**
`PosterImage` defaults to `.fill` for fixed-frame tiles; the Detail hero shows
the real art `.fit` over a blurred fill of itself so letterboxing reads as
intentional. `Text(verbatim:)` for years and decades ("1,960s" locale bug,
playbook §7.6).

4.7 **Image loading** rides `AsyncImage` over the launch-configured
`URLCache` (64 MB / 400 MB) with the quiet film-frame placeholder. Don't add
per-view caches or third-party loaders.

---

## §5 — Home composition (binding)

5.1 **The order is fixed:** hero carousel → Continue Watching → category
tiles → first two featured shelves → Hidden Gems → Public Domain Day →
director shelves → remaining featured shelves → decade tiles (last, matching
tvOS Home — owner direction 2026-06-11; the Modes row was removed 2026-06-10,
see §2.6). Inserting a section means amending this rule, not appending
wherever.

5.1b **Category tiles must open robust grids.** A tile only shows when its
content type has ≥30 browseable items (`browseCount` gate, both platforms —
the classifier emits almost no "documentary", and a near-empty grid reads as
broken). The grid's Popular sort leads with designed (non-generated) artwork,
then popularity; the tv-series category browses SERIES CARDS (deepest shows
first by episode count) and routes to SeriesDetail.

5.2 **Shelves resolve by id through the prebuilt `item_shelves` map**
(`store.items(forShelf:)`, Decision 017). Never resolve a featured shelf by
browsing its `contentType` — that is the duplicate-shelf bug (every
feature-film shelf returning the same popular list).

5.3 **Dedup downward.** An item shown in the hero, Continue Watching, gems,
Public Domain Day, or a director shelf is excluded from later featured
shelves; each shelf also excludes items an earlier shelf took
(`dedupedPayloads`). Home must never be five aliases of the same popular list.

5.4 **Min 6 per shelf (the stub rule).** A phone shelf shows ~3 tiles; below
6 items a row reads as a ragged stub — drop the shelf entirely rather than
show it thin. Featured shelves additionally require professional artwork; the
hero requires designed, non-generated art and prefers wide backdrops.

5.5 **Shuffles are seeded once per Home lifetime** (`SplitMix` + per-shelf
seed) so the layout is stable across body recomputes and re-rolls only on a
fresh Home.

5.6 **Hero adapts by size class:** full-bleed ~16:9 banner on iPhone
(compact), width-capped centered card (~760 pt) on iPad/regular so a wide
screen never stretches the strip into an extreme crop. Auto-advance every 7 s;
page dots always visible; tap opens Detail.

5.7 **Hide-watched (#17) applies to Home only.** Completed titles
(`WatchProgress.isComplete`, fed into `store.completedArchiveIDs` by the view
that owns the @Query) are filtered from hero + shelves via
`store.filteringWatched`; Search, Browse, and Library are unaffected.
Continue Watching is exempt (it shows in-progress, threshold > 10 s, by
timecode).

5.8 **Home feeds the widgets.** Whenever Home rebuilds, it writes the App
Group snapshot via `WidgetSnapshotWriter` (Continue Watching + Editor's
Picks). New widget data extends that one writer/snapshot shape — the widget
target duplicates the Codable shape, so both sides change together.

---

## §6 — Typography & density (binding)

6.1 **Native Dynamic Type styles only** — `.title`, `.title3`, `.headline`,
`.subheadline`, `.body`, `.caption`, `.caption2`, with weight modifiers. The
ONLY sanctioned custom sizes are inside compact navigation tiles (decade
numeral, tile icon), where the tile is effectively an illustration. A new
`font(.system(size:))` outside a tile is a rule violation; refactor to a
style.

6.2 **Six hierarchy levels, period** (CLAUDE.md density rule). Three weights ×
two sizes per surface; refuse a seventh — refactor.

6.3 **Synopsis lives on Detail (and episode rows, 2-line clamped).** Hero,
shelves, tiles, and the channel guide never carry synopsis — title, year, and
one meta line at most (the touch analog of tvOS-DESIGN §4.2).

6.4 **Section headers are `.title3.semibold` + optional `.subheadline`
secondary subtitle**, padded horizontal — the one shelf-header pattern,
everywhere (Home, Detail, Cartoon).

---

## §7 — Color & materials (binding)

7.1 **Brand vs semantic split is absolute** (Decision 013, tvOS-DESIGN §5.1).
Chrome and CTAs use `Brand.primary` (`#FF5C35`) / `Brand.accent` (`#0047FF`)
from `Design_iOS.swift`. Per-category semantic accents carry *content meaning
only* — category tiles, collection cards, decade eras, surprise/mode chips,
channel icons — sourced from `featured.json` / `CollectionMetadata` /
`Channel` definitions via `Color(hex:)`, never hardcoded into a chrome role.
Never a brand color for meaning, never a semantic color for chrome.

7.2 **Dark-first.** The app pins `preferredColorScheme(.dark)` — a cinema, not
a settings app. System semantic styles (`.primary/.secondary/.tertiary`,
`.quaternary` fills) do the rest; no hand-rolled grays.

7.3 **Accent tiles use the gradient-to-black pattern** (accent →
`accent.mix(with: .black, …)`) with white text — the one decorative device for
navigation chips. Content tiles get no decoration; the poster is the design.

---

## §8 — Player (binding)

8.1 **`AVPlayerViewController` owns transport; assets ALWAYS come from
`ResilientStreamLoader.makeAsset(for:)`** (Decision 021). Never
`AVPlayerItem(url:)` for remote video. Retain the returned loader on the
Coordinator (the delegate is weak), set
`preferredForwardBufferDuration = 300`, enable PiP. We add only overlays;
never a parallel transport.

8.2 **Activate the audio session before playing.** iOS requires
`AVAudioSession` category `.playback` (mode `.moviePlayback`) set + activated
before `play()`, or AVPlayer stalls, fails to start, or plays silently behind
the ringer switch — this is the documented iOS-vs-tvOS playback gap. Every
playback entry point goes through `PlayerView`, which does this; do not
create a second player surface that skips it.

8.3 **One queue family.** Continuous play is the shared `ContinuousPlayback`
engine surfaced through the `PlaybackQueue` protocol — `MovieAutoplayQueue`
(gated by `store.autoplayMode`; `.off` returns nil), `EpisodeQueue` (binge
always advances), `LineupQueue` (channels straight through, skipping
unplayable). Advancing swaps items on the SAME `AVPlayer`
(`replaceCurrentItem`), never re-presents. A new "what plays next" behavior is
a new `PlaybackQueue`, never a second engine (tvOS-DESIGN §9.5 spirit).

8.4 **Resume is per-title `WatchProgress`,** persisted every 10 s and on
dismantle, resumed when saved position > 10 s. **Channel/lineup playback never
persists progress** (`persistsProgress = false`) — live TV doesn't resume, and
a 30-second commercial must not pollute Continue Watching or Watched.
Join-in-progress (`startOffset`) beats per-title resume.

8.5 **Episode prev/next is the overlay capsule.** AVPlayerViewController has
no custom-transport API on iOS, so manual episode navigation lives in
`EpisodePlayerContainer`'s top-trailing capsule (chevrons + SxE label);
switching recreates the player via `.id(episode.archiveID)`, and auto-advance
reports back through `onAdvance` so the capsule stays anchored to what's
actually playing. New in-player affordances follow this overlay pattern.

8.6 **Channels weave commercials** between programs (vintage PD ads from
`randomCommercials`), schedule deterministically via the shared date-seeded
`ChannelScheduler`, and emphasize color for animation pools (Decision 025,
B&W capped to a minority). Commercials stay off Home.

8.7 **A downloaded film plays as a plain local file** (Decision 099).
`OfflineLibrary.videoURL(for:)` is checked FIRST in `makeUIViewController`
and in `makeLocalItem()`; when it answers, the item is
`AVPlayerItem(url: fileURL)` with no resilient loader, no HLS wrapper and no
node resolution — that machinery exists to survive a connection, and a
`file://` URL has none to lose. This is the ONE carve-out from §11.5, which
governs REMOTE video. `directVideoURL` still holds the remote URL so AirPlay
keeps a receiver-fetchable target (Decision 051). Subtitles for a downloaded
film are the downloaded WebVTT rendered into the caption overlay
(`OfflineSubtitles`), selected by the existing caption-type control, never a
second overlay drawn on top of the first.

---

## §9 — State, persistence & sync (binding)

9.1 **`AppStore` (iOS) is the only catalog read path.** Views call
`store.*` pass-throughs; nothing touches `CatalogDB`, SQLite, or URLSession
directly. Load order is fixed: bundled `seed.sqlite` for instant first paint →
cached full DB → freshly downloaded DB (Decision 017), each swap bumping
`dbVersion`. Any view that caches query results re-queries via
`.task(id: store.dbVersion)` (and `.id(store.dbVersion)` where the whole body
must rebuild).

9.2 **Filters are baked into the DB layer once.** Adult (Decision 012,
default-deny) and hidden categories set `db.hideAdult` / `db.hiddenTypes` at
swap/change time so every query is filtered at the source — never re-filter
per-view.

9.3 **SwiftData models are shared with tvOS verbatim** (`WatchProgress`,
`Favorite`, `Playlist`, `UserChannel`, `Tombstone`), in the App Group
container, `cloudKitDatabase: .none` with manual `CloudKitSyncService` sync —
the same CloudKit container as the Apple TV, so an iPhone syncs WITH the TV
(Decision 022). Sign-in is optional and gates ONLY sync; never call CloudKit
on a signed-out install (the launch gate).

9.4 **Every synced mutation goes through `SyncNudge`.** Insert/update →
`ctx.save()` + `SyncNudge.nudge(ctx)` (debounced push/pull). Delete →
`SyncNudge.recordDeletion(key, in: ctx)` (tombstone, #11b) INSTEAD of a bare
`ctx.delete` — a bare delete resurrects on the next pull. Tombstone key
prefixes in use: `fav:`, `pl:`, `ch:`.

9.5 **UserDefaults keys are shared with tvOS by name** (`hideAdultContent`,
`hiddenCategories`, `autoplayMode`, `hideWatchedOnHome`) so a preference means
the same thing on both platforms even though the value is per-device. New
preferences reuse the tvOS key, or define one key for both — never an
`ios`-suffixed twin.

9.7 **A model that names a FILE on this device is device-local and never
synced** (Decision 099). `DownloadedFilm` is registered in the container but
excluded from `CloudKitSyncService` and from §9.4's tombstone discipline: a
bare `ctx.delete` (via `DownloadManager.remove`) is CORRECT here and nowhere
else. Favorites and progress record an intention, which is true on every
device; a download records bytes on one. Syncing it would put a title in the
iPhone's Downloads that exists only on the Mac. Any future model of this kind
(a cached render, an exported file) follows the same rule and says so here.
Whether a film is present is asked of the FILE SYSTEM, never of the row —
a row can outlive its file.

9.6 **No new state without a home** (tvOS-DESIGN §1.7). Persisted user state
maps to the §9.3 models (+ sync per §9.4) or a §9.5 default — nothing ad-hoc.

---

## §10 — Out of scope on iPhone/iPad (intentional)

Per PARITY §5, lean-back/10-foot idioms do not port to the phone:
- **Party Play** (muted ambient wall) — 🔮 iPad-leaning at most; not iPhone.
- **Cover-art screensaver with idle auto-trigger** — idle takeover is a
  10-foot idiom; at most a future explicit ambient mode on iPad.
- **Top Shelf** — n/a (WidgetKit is the iOS analog, §5.8).
- **VHS effect overlay** — future polish, reuse the Metal shader if ever.
- **A second sync island** — Apple devices sync via CloudKit only; Google
  Drive App Data is the Android/Web island (Decision 028). No cross-ecosystem
  sync.
- **Custom transport chrome** — §8.1/§8.5; we don't rebuild the scrubber.

---

## §11 — Anti-patterns (never)

11.1 A fifth content tab, or Settings as a tab (§2.1). 11.2 A per-view
`navigationDestination` for a shared route (§2.3). 11.3 `NavigationLink` to a
catalog screen instead of `router.push` (§2.4). 11.4 `fullScreenCover` for
anything but playback, or `fullScreenCover(isPresented:)` around
data-dependent content (§4.4). 11.5 `AVPlayerItem(url:)` for remote video, or
playback without the audio-session activation (§8.1–8.2). 11.6 A second
autoplay/queue engine (§8.3). 11.7 Persisting WatchProgress from channel
lineups (§8.4). 11.8 Resolving a featured shelf by contentType (§5.2). 11.9 A
shelf under 6 items (§5.4). 11.10 A bare `ctx.delete` on a synced model
(§9.4). 11.11 Direct `CatalogDB`/URLSession access from a view (§9.1). 11.12
A brand color for content meaning or a semantic accent for chrome (§7.1).
11.13 Custom font sizes outside navigation tiles (§6.1). 11.14 Porting a tvOS
focus rule into iOS files or this doc's inversions back into tvOS (§4.1).
11.15 A grid/list/sheet without all four states (§4.2). 11.16 A tombstone or
`SyncNudge` call on a device-local model (§9.7). 11.17 Answering "is this
downloaded?" from a database row rather than the file system (§9.7). 11.18
Wrapping a downloaded file in a resilient loader or an HLS master (§8.7).
11.19 Auto-downloading anything the viewer did not ask for by name — no
predictive pre-caching, no "for your trip" suggestions (the learning-
orientation gate: the viewer chooses what they carry).

---

## §12 — The tests (run before any surface ships)

12.1 **Competent-designer test** — could a peer rebuild this screen from a
one-paragraph description? If no, you added decoration; strip.
12.2 **Verb test** — what verb does this own? Colliding with one of the four
tabs' verbs (browse-curated / browse-all / find / saved)? Structural bug;
resolve first.
12.3 **Depth test** — count pushes from the tab root. >2 → scope/sheet/tab,
not another push (§1.5).
12.4 **Parity discipline** — `PARITY.md` is updated in the SAME change set as
any user-facing feature, and the proposal/commit quotes this doc's rule
numbers (e.g. "per iOS-DESIGN §5.3"). A feature that exists on tvOS but lands
differently here must be the *native idiom* of the same verb — name the tvOS
rule it mirrors or deliberately inverts.
