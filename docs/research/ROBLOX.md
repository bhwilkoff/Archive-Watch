# Roblox as an Archive Watch platform — research (2026-10-15)

Owner, 2026-10-15: *"I'd like to start doing research on another major platform
that we could start publishing to and developing for: Roblox. ... a robust
'Watch Together' experience that could connect up with other users across the
other platforms AND also present an infinite number of virtual theaters that
could allow you to watch the Public Domain videos from our database for an
individual watching experience as well."*

This file is the synthesis. The evidence, with every primary-source URL and
every claim that could not be confirmed marked UNVERIFIED, is in six detail
files under `docs/research/roblox/`:

| File | Covers |
|---|---|
| `01-video.md` | Video playback objects, video asset uploads, external streaming, precedents, cost model |
| `02-toolchain-testing.md` | Rojo/Luau toolchain, Studio MCP, Jest + Open Cloud Luau Execution, multi-client tests, CI, observability |
| `03-publishing-policy.md` | Publishing, maturity labels, age checks, Community Standards vs. our catalog, money, discovery |
| `04-integration.md` | HttpService, Open Cloud push into Roblox, deep links, cross-platform rooms, posters |
| `05-theaters-3d.md` | Reserved-server instancing, theater building, lighting/audio, budgets, AI-only asset pipeline, precedents |
| `06-ui-aesthetic.md` | React Luau, UI Styling tokens, fonts, console focus, 3D UI, captions, safe areas |

Nothing has been built, uploaded or bought. Researched against Roblox's docs as
they read on 2026-10-15; Roblox changes these limits often (video length went
30 s -> 60 s -> 5 min in 2023-2025), so re-read `01-video.md`'s sources before
acting on a number.

---

## 1. The verdict in one paragraph

Everything the owner described is buildable on Roblox **except the thing at its
center: playing our films.** Roblox plays only video it hosts. There is no URL
playback, no web view and no sanctioned streaming route. Each video asset is at
most **5 minutes**, costs **2,000 Robux** (about $20-25, not refunded on a
moderation rejection), needs a 13+ ID-verified uploader, and one account may
upload **20 a day**. A 90-minute feature is 18 uploads, about **36,000 Robux
(~$400)**; the whole catalog would be ~$7M and ~49 years of one account's
quota. So Roblox can carry a **curated program** of public-domain films, not the
catalog. The theaters, the rooms that connect to our other platforms, the
interface in our design system, and an agent-driven build and test workflow
are all well supported.

## 2. What fits and what does not

| Owner goal | Fit | Why |
|---|---|---|
| Infinite virtual theaters, private or shared | **Strong** | One universe: a public Lobby place and a Theater place reached only through reserved servers. `TeleportAsync` with `ShouldReserveServer` opens a new screening; the access code rejoins it. No documented fee or cap. A private screening is just a reserved server holding one player. (05 §1) |
| Watching our public-domain films | **Weak** | Only uploaded 5-minute assets play; a feature is a chain of 18 segments using the two playback slots a client has (play one, preload the next). Gaplessness at the seams is unmeasured. (01 §5) |
| The full catalog | **Not feasible** | ~720M Robux, ~49 account-years of quota. Frame-pushing into an EditableImage avoids the fees but gives hobby-grade picture, needs the audio uploaded anyway, and bypasses moderation with unknown enforcement risk. (01 §3, §5) |
| Watch Together with the other platforms | **Good, one way** | Our Worker can push room changes into live Roblox servers through Open Cloud MessagingService (1 KiB, ~1-2 s). Roblox players follow a room as guests, seeking when drift exceeds ~1 s. Our apps can open Roblox with a room code in launch data (200 bytes). Roblox may NOT show a URL or point players off Roblox, so a code cannot be advertised from inside. The film must exist as Roblox segments, which ties a cross-platform room to the curated program. (04 §3-§5) |
| Our aesthetic | **Good** | The engine's UI Styling system (released 2026-01-20) has CSS-like rules and `$Token` design tokens; one token file can generate both our web CSS and a Roblox StyleSheet. React Luau is official and maintained. Custom fonts cannot be uploaded: Builder Sans (three weights) and Merriweather are the nearest built-ins; the wordmark is an image. (06 §1-§2) |
| Our development process (agent-driven, tested, CI) | **Good** | Studio ships an MCP server with Claude Code as a quick-connect client (run Luau, start playtests, read the console, capture the screen, drive a player). Rojo keeps the repo the source of truth; Jest runs in CI through the Open Cloud Luau Execution API; Studio can script a test with up to 8 clients. Real phones, consoles and VR cannot be automated. (02) |
| Publishing | **Free, with gates** | No store review; every asset is moderated. 16+ release needs only an age-checked account. Reaching under-16s needs ID verification, 2FA, a refundable 1,000 Robux fee (or Premium), a mild-or-lower label and 250 engaged plays in 60 days. (03 §1) |

## 3. Constraints that change OUR rules, not just our code

1. **Roblox's Community Standards are stricter than our catalog.** Real-world
   depictions of death, extremist iconography, mockery of protected groups —
   with no historical or educational exception. Nazi propaganda (Decision 149
   keeps it findable), racist cartoons and newsreels of the war dead must be
   **excluded** from anything on Roblox, not merely kept off recommendations.
   (03 §2)
2. **No links out.** "You may not link to, share, or display URLs of any
   external websites or services", and "any other efforts to direct users off of
   Roblox" are prohibited. Roblox cannot say "also on archivewatch.org". Social
   Links on the listing page are the only outward door, and a website does not
   appear to be an allowed type (UNVERIFIED). (03 §2, 04 §4)
3. **Chat is age-banded.** Since 2026-01, players chat only with their own and
   adjacent age bands, and unchecked players have no chat at all. A room must
   work without chat: reactions, quick phrases, votes. (03 §6)
4. **Ratings follow the films.** Realistic violence is Moderate (9+); heavy
   blood, alcohol or strong language is Restricted (18+). Whether on-screen
   drinking in 1930s-40s films counts is UNVERIFIED and decides how much of a
   program reaches teenagers. (03 §1)
5. **Store art may not show the films.** Thumbnails and trailers forbid
   "real-life footage ... outside the game" and spoken audio; trailers are
   captured inside the theater with silent or instrumental films. (03 §5)
6. **Money we would receive by default.** Creator Rewards (since 2025-07-24) pays
   automatically when a game is one of a spender's first few of the day. The
   docs do not say it can be declined. That incentive cuts against "Why we
   build" and is the owner's call. (03 §4)
7. **Accounts.** Nothing here needs "Sign in with Roblox"; rooms work on codes.
   Keep Decision 009 (no accounts) and send our Worker no Roblox user ids.
   (04 §8, 03 §2)

## 4. The architecture this research points to

```
Lobby place (public)
  marquee + poster shelves (SurfaceGui, one per shelf)  -> pick a film or a room code
  TeleportAsync(ShouldReserveServer)                     -> Theater place
Theater place (reserved servers only; "Secure within universe only")
  room themed by the film's era/category from catalog data (picture palace,
    nickelodeon, newsreel theater, drive-in): a data record over shared Packages
  VideoFrame chain: segment n playing, n+1 preloaded; server owns the schedule,
    clients seek (TimePosition is not replicated) until VideoPlayer ships (mid 2027)
  subtitles drawn by us from our SRT files, timed to playback
  screen light: a SurfaceLight tweened from a per-second color track our pipeline
    computes with ffmpeg (scripts cannot read video pixels)
Cross-platform room
  host on Apple/Android/web -> Worker -> Open Cloud publishMessage -> live servers
  slow 15-30 s poll as fallback; our apps open Roblox with launchData=<room code>
Pipeline (new, in tools/)
  curated list -> ffmpeg 5-min segments + loudness -> Open Cloud Assets upload
  (2,000 Robux each, quota 20/day) -> poll moderation -> segment map published
  posters: Open Cloud image uploads, <=512 px, moderated
```

Repo shape: `roblox/` with a fully managed Rojo project, Rokit-pinned tools,
StyLua + selene + `luau-lsp analyze`, Lune for pure-logic tests, Jest through
Luau Execution against a separate test universe, publish from CI with an API
key. The interface comes from one token JSON shared with the web (06 §7).

## 5. Measurements to take before committing (each is cheap)

Ordered by how much they could change the decision:

1. **Moderation on public-domain film.** Upload 2-3 segments of a film in the
   guaranteed rights tier (~6,000 Robux): accepted, rejected, or flagged by the
   copyright detector? Does an appeal with our rights evidence work? (01 Q1)
2. **Seams and drift.** Chain 3 segments on a phone and a console: is there a gap
   at the cut, and how far do two clients drift over 15 minutes? (01 Q3, 04 §5)
3. **Picture quality.** Is playback still capped at 720p, and at what frame rate
   on mobile? (01 Q2)
4. **Our Worker from a published place.** Does HttpService reach
   `*.workers.dev`, and does `launchData` survive the deep link on iOS, Android
   and desktop? (04 §7)
5. **Reserved-server spin-up time and rate limit** (undocumented). (05 §1)
6. **Agent harness.** Does Studio's command-line RunScript run unattended on this
   Mac, and does MCP `screen_capture` return bytes CI can compare? (02 §6)

Items 4-6 cost nothing. Items 1-3 need Robux and an ID-verified account.

## 6. Decisions reserved for the owner

1. **Is a curated program worth it?** A pilot of 10-20 features is roughly
   $4-9k in upload fees; 100 features ~$36-45k. Shorts, cartoons and silents
   under 5 minutes cost one upload each (~$20-25), which makes a shorts-first
   program far cheaper.
2. **Who uploads.** Uploads need a 13+ ID-verified Roblox account (a Group can
   own the experience); that identity is the owner's.
3. **Audience.** 16+ only (simplest), or the under-16 track with its fee, 2FA
   and engagement threshold.
4. **Creator Rewards** if it can be declined, and what to do if it cannot.
5. **Poster art.** Putting TMDb artwork on Roblox is a licensing question;
   frame-extracted covers (Decision 023) are ours.
6. **Wait for mid 2027?** The VideoPlayer API, which replicates play and pause
   from the server, moved to mid 2027 on Roblox's 2026-09-18 roadmap. Staff have
   called length, fee and concurrency "on the table" with nothing committed.
   Building theaters, rooms and interface now and adding films as limits move is
   a reasonable middle course.

## 7. Recommendation

Do the free measurements (§5, 4-6) now; they need only a Roblox account and
Studio on this Mac. Then, if the owner wants to proceed, spend the minimum on
measurements 1-3 before any build, because moderation of public-domain film is
the single unknown that could end the project. Build toward a **curated
cinematheque**: real films in rooms of their era, shared or private, joinable
from our other apps by code. Do not promise the catalog on Roblox until Roblox
lifts the length, fee or URL restrictions.
