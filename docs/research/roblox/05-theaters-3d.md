# 05 — Virtual theaters on Roblox: instancing, building, budgets, generation, precedents, AI-made assets

Research date: 2026-10-15. Primary sources are Roblox Creator Hub docs (create.roblox.com), DevForum
staff announcements, and the asset sites' own license pages. Anything not confirmed from a primary
source is marked **UNVERIFIED**. Video upload/playback mechanics are covered in depth in `01-video.md`;
they are summarized here only where they constrain the theater design.

---

## 0. The short answer

"An infinite number of theaters" is the natural shape of Roblox: one **Universe** (experience) with a
**Lobby place** (the start place, public matchmaking) and a **Theater place** that is only ever entered
through **reserved servers**. Each screening — private or shared — is `TeleportAsync` with
`TeleportOptions.ShouldReserveServer = true` (new screening) or `ReservedServerAccessCode = code`
(join an existing one). Reserved servers are free, documented with no cap on how many you create, and
their access codes never expire. Themes (picture palace, drive-in, newsreel theater) are data: one
Theater place that builds its room from a theme record passed in teleport data, or one place per theme.

The hard constraints are not instancing — they are **video** (5-minute uploads, 2 simultaneous videos,
each video fully downloaded to the device before playing, per-upload ID verification + daily quota) and
**mobile memory**.

---

## 1. Instancing

### 1.1 Reserved servers (the core mechanism)
- Modern API: `TeleportService:TeleportAsync(placeId, players, teleportOptions)`; the old
  `ReserveServer`, `TeleportToPrivateServer`, `TeleportPartyAsync`, `TeleportToPlaceInstance` are
  **deprecated**. https://create.roblox.com/docs/reference/engine/classes/TeleportService
- `ReserveServerAsync(placeId)` (server-only, yields) "returns an access code that can be used to teleport
  players to a reserved server". "Access codes remain valid indefinitely, meaning reserved servers can
  still be joined if no game server is running." "A server is started when the access code is first
  used." https://create.roblox.com/docs/reference/engine/classes/TeleportService.md
- `game.PrivateServerId` is "constant across all server instances associated with the server access
  code" (JobId differs per instance) — so it is the stable "theater id". Console players with cross-play
  off are split into a separate server with the same PrivateServerId; tell them apart with
  `DataModel.MatchmakingType`. (same page)
- TeleportOptions: `ShouldReserveServer = true` creates a new reserved server;
  `ReservedServerAccessCode` joins one; `ServerInstanceId` targets a public server; these are mutually
  exclusive. "No more than 50 players can be teleported with a single" call. On failure,
  `TeleportInitFailed` hands back the TeleportOptions including the generated access code so the retry
  goes to the same theater. https://create.roblox.com/docs/projects/teleport
- Reserved servers are "detached from automatic matchmaking and can only be accessed through a
  server-sided method with an access code"; player cap comes from the **target place's** max players;
  no built-in cap on how many you can create (DevForum, community, older).
  https://devforum.roblox.com/t/reserved-server-limitations/1468107
- **Cost**: no fee is documented anywhere for reserved servers; they are standard game servers.
  Community confirms they are the free workaround now that free private servers were restricted (below).
  Free — high confidence, but Roblox publishes no explicit "free" sentence: **UNVERIFIED in so many words**.
- **Concurrency cap**: no documented per-universe cap on reserved servers or game servers. **UNVERIFIED**
  (absence of evidence). Rate limit on `ReserveServerAsync`: undocumented; Open Cloud docs note
  "additional, undocumented limits may apply". https://create.roblox.com/docs/cloud/reference/rate-limits
- **Spin-up time**: not documented. Community experience is several seconds to ~15 s including the
  teleport loading screen. **UNVERIFIED** — measure it.
- Teleports cannot be tested in Studio ("You must publish the game and test in the Roblox client").
  https://create.roblox.com/docs/projects/teleport
- Access Control: set the Theater place to **"Secure within universe only"** so it can only be reached by
  server-initiated teleports (no direct joins). (same page)

### 1.2 Private servers (VIP servers) — not the right tool
- Player-purchased/owned subscription servers, can be free or paid; require the game to be public;
  changing the price cancels subscriptions; incompatible with paid access.
  https://create.roblox.com/docs/production/monetization/private-servers
- **2026 change**: from **2026-09-24**, Roblox Plus includes "one free private server per game instead of
  unlimited servers"; free private servers in games that offer them free are unaffected.
  https://devforum.roblox.com/t/changes-to-roblox-plus-private-server-limits/4739922
- Developers no longer get unlimited free private servers on their own games; the community answer is
  "use Reserved Servers ... basically private servers but you have to create them using a script"
  (2026-07-16). https://devforum.roblox.com/t/let-developers-create-private-servers-for-free-for-their-own-games/4739962
- Conclusion: theater instances should be **reserved servers owned by our code**, not private servers.

### 1.3 Server size, single-player servers, matchmaking
- `Players.MaxPlayers` "can only be set through a specific place's settings on the Creator Dashboard";
  `PreferredPlayers` is what "Roblox's matchmaker will fill servers" to.
  https://create.roblox.com/docs/reference/engine/classes/Players.md
- Max players is **per place**, so a Theater place can be sized independently of the Lobby
  (https://devforum.roblox.com/t/howserver-size/2669652). Exact allowed range (commonly cited 1–100,
  higher by exception, 700 anecdotal) — **UNVERIFIED**. Voice chat docs cap voice experiences at 50
  (community report) — **UNVERIFIED**.
- A max-player change does not apply to already running servers (community).
- **Private single-viewer screening**: reserve a server and teleport one player. The server holds only
  that player, so it is effectively a single-player instance even though the place max is, say, 50.
  No special "single-player server" mode is needed.
- **Shared screening**: the host reserves; the access code is stored (MemoryStore / DataStore) under a
  short human room code; friends' lobby servers look it up and `TeleportAsync` them in with the code.
  Matchmaking is bypassed entirely. Party size per teleport call ≤ 50.
- Known matchmaking bug (2025-10-06): Roblox sometimes created a new server for every joining player in
  public matchmaking; staff "assigned it for investigation".
  https://devforum.roblox.com/t/roblox-is-creating-1-player-servers-over-filling-existing-ones-harming-interaction/3981365
  — irrelevant to reserved servers but matters for the public Lobby.
- **Server compute**: default per-server CPU/memory limits "were recently raised and scale with each
  player" (2026); **Extended Services for Compute** (announced 2026-06-02) is opt-in, first 100K playtime
  hours/month free, then $0.001 per playtime hour, with a mandatory budget. A theater server does almost
  no simulation, so it is **not needed**.
  https://devforum.roblox.com/t/scale-your-game-performance-with-extended-services-for-compute/4665165

### 1.4 Places within a Universe
- "Games on Roblox are made up of individual places, comparable to scenes in Unity or maps in Unreal."
  https://create.roblox.com/docs/en-us/studio/experience-settings
- Recommended layout: **Lobby** (start place: catalog browsing, "now showing" marquee, social,
  public servers) → **Theater** place(s) (reserved only). Teleport data (`TeleportOptions:SetTeleportData`,
  read via `Player:GetJoinData()`) carries non-secret screening info (film id, theme id, start
  timestamp); it is client-visible and unencrypted, so authority (host, schedule) lives in
  MemoryStore/DataStore. https://create.roblox.com/docs/projects/teleport
- Max places per universe: not documented in the pages read — **UNVERIFIED** (not a practical limit
  for a handful of theme places).

### 1.5 Instance streaming
- `Workspace.StreamingEnabled` is on by default for new places; `StreamingMinRadius` default 64,
  `StreamingTargetRadius` default 1024; `StreamOutBehavior = Opportunistic` recommended to cut
  out-of-memory crashes; `ModelStreamingBehavior = Improved` recommended; Atomic / Persistent /
  PersistentPerPlayer model modes. "Games can be played on devices with less memory since content is
  dynamically streamed in and out." https://create.roblox.com/docs/workspace/streaming
- For a single enclosed auditorium (~100–200 studs across) streaming buys little beyond join speed;
  keep it on (also required for SLIM, below), make the screen/seat rig **Atomic** or
  **PersistentPerPlayer** so client scripts never find half a theater.
- **SLIM** level of detail: set `Model.LevelOfDetail = SLIM` on static geometry (requires a saved place,
  StreamingEnabled and Team Create; cloud-transcoded); `Workspace.EnableSLIMAvatars` renders distant
  avatars as lightweight stand-ins — useful in a full shared theater on phones.
  https://create.roblox.com/docs/workspace/streaming/slim

### 1.6 Can each player get their own theater on demand? — Yes
Reserve → teleport is a few lines of server code and is the documented pattern. Practical concerns:
retry with backoff (docs' sample: 5 attempts, 1 s delay, 15 s after a flood result), store the access
code before teleporting, and handle `TeleportInitFailed`. Video, not servers, is the scaling cost.

---

## 2. Building a theater

### 2.1 Modeling approach
- **Imported meshes from Blender** for anything shaped (proscenium, seat rows, balcony fronts, plaster
  ornament, drive-in screen frame, cars); **Studio Parts** for blockout, collision, and invisible floors.
- Limits: "Individual meshes can not exceed 20,000 triangles"; geometry must be watertight, no
  zero-thickness, quads preferred, no N-gons. https://create.roblox.com/docs/art/modeling/specifications
  (A 2026 request to raise the 20k limit exists; no change announced.
  https://devforum.roblox.com/t/increase-the-max-triangle-limit/4650221)
- 3D Importer: .fbx, .obj, .gltf; .fbx/.gltf carry "basic and PBR textures"; Scale Unit setting;
  "Import Only As Model"; "Merge Meshes"; a batch import queue.
  https://create.roblox.com/docs/art/modeling/3d-importer
- Blender export: .fbx, Path Mode = Copy + Embed Textures, apply scalings to FBX unit scale, no leaf
  bones. https://create.roblox.com/docs/art/modeling/export-requirements
- **Instancing / draw calls**: meshes sharing the same MeshContent and matching SurfaceAppearance render
  in one draw call — "only upload each mesh in a map once" and duplicate it in Studio. This is exactly
  what a theater needs: **one seat mesh, 300 copies**.
  https://create.roblox.com/docs/performance-optimization/improve

### 2.2 PBR materials — SurfaceAppearance
- Color, normal (OpenGL tangent space only), roughness, metalness, emissive maps; AlphaMode
  Opaque/Overlay/Transparency/TintMask. Properties cannot be scripted at runtime **except**
  `SurfaceAppearance.Color`, a tint multiplier — "Tinting does not affect performance", so one velvet
  seat material can be red in the palace and green in the newsreel theater.
  https://create.roblox.com/docs/art/modeling/surface-appearance
- **Emissive maps** (`EmissiveMaskContent`, `EmissiveStrength`, `EmissiveTint`) are in the API reference;
  the DevForum beta announcement carries a note that the update was "temporarily reverted ... to
  investigate an issue". Current shipping status: **UNVERIFIED**.
  https://devforum.roblox.com/t/on-hold-emissives/4034414 — Fallback for marquee bulbs, exit signs and
  aisle lights: `Neon` material parts.
- Textures: albedo/normal RGB 24-bit, roughness/metalness/emissive 8-bit grayscale; docs state both
  "up to 4096×4096" and "up to 1024×1024 pixel spaces for texture maps" (inconsistent); the engine
  streams lower mips first. https://create.roblox.com/docs/art/modeling/texture-specifications
  Performance guidance: "Images usually need at most 512x512"; a 1024² costs 4× a 512²; use trim
  sheets. https://create.roblox.com/docs/performance-optimization/improve

### 2.3 Lighting (2025–2026 state)
- `Lighting.Technology` (Voxel / ShadowMap / Future) has been superseded by **`LightingStyle`**
  (`Realistic` | `Soft`) and **`PrioritizeLightingQuality`** (prefer near shadow/shader quality vs. view
  distance). "Realistic provides the most advanced and realistic lighting and shadows Roblox can
  deliver"; new games start on Soft; "Soft with that property enabled uses shadow maps rather than voxel
  lighting". https://create.roblox.com/docs/environment/lighting ,
  https://create.roblox.com/docs/reference/engine/classes/Lighting.md
  (The exact date of the switch and whether `Technology` is formally deprecated: **UNVERIFIED**; the
  reference page I read still describes Technology without a deprecation note.)
- Indoors: Realistic is required for local lights to cast precise shadows and specular highlights;
  enclose rooms with ≥1-stud-thick parts so outdoor light doesn't leak; "Point lights can be more
  performance intensive on low-end devices"; use ExposureCompensation and ColorCorrection rather than
  raising Brightness. https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-indoor-environments
- Shadows degrade automatically with graphics quality; **disabled entirely below quality level 4**.
  Disable `Shadows` on lights that don't need them, `CastShadow=false` on small parts.
  https://create.roblox.com/docs/performance-optimization/improve
- Per-pixel lighting falls back to ShadowMap or Voxel on devices that can't do it (2020 "Future is
  Bright" announcements; current device coverage **UNVERIFIED**).
  https://devforum.roblox.com/t/future-is-bright-phase-3-released/878634
- A dark theater is the friendliest possible lighting case: ambient near black, a handful of
  non-shadowing aisle/sconce lights, one shadowing SpotLight at most (the projector beam).

### 2.4 The screen
- Playback: `VideoFrame` inside a `SurfaceGui` on a Part (docs' sample builds a 16×9×1 part), or the
  newer wired **`VideoPlayer` → `Wire` → `VideoDisplay`** (in a SurfaceGui) plus a second Wire to an
  **`AudioEmitter`**: "Create and connect wires so that the video visually renders and emits audio."
  Client-side playback is preferred; server playback "does not guarantee it is loaded or synced".
  https://create.roblox.com/docs/en-us/reference/engine/classes/VideoPlayer ,
  https://create.roblox.com/docs/en-us/reference/engine/classes/VideoDisplay
- Constraints (see 01-video.md for detail): uploads ≤ 5 minutes, ≤ 4096×2160, < 3.75 GB, .mp4/.mov,
  13+ ID-verified uploader, **20 uploads/day**, "maximum of two videos can play simultaneously", and the
  video-frames doc still says "Each video upload costs 2,000 Robux" (the July 2025 announcement promised
  "adjustments to the video upload fee" — current fee **UNVERIFIED**).
  https://create.roblox.com/docs/ui/video-frames ,
  https://devforum.roblox.com/t/longer-video-uploads-more-video-uploads/3532432 ,
  https://create.roblox.com/docs/cloud/guides/usage-assets
  A 90-minute feature = ~18 segments chained with `DidEnd` and a preloaded second player (the 2-video
  limit is exactly enough for A/B double-buffering). "Every video asset must be downloaded to each
  player's device before it can play" — preload the next segment only, unload the last.
  https://create.roblox.com/docs/cloud-services/video-service
- **Glow**: SurfaceGui `LightInfluence = 0` makes it ignore scene lighting; `Brightness` "determines
  the factor by which the SurfaceGui container's light is scaled when LightInfluence is 0" — so a value
  >1 makes the screen self-lit in a dark room. Whether it then feeds `BloomEffect` for a halo:
  **UNVERIFIED** (test). `AlwaysOnTop` must stay false (it disables Brightness and draws through
  geometry). `PixelsPerStud` / `SizingMode` control the canvas resolution.
  https://create.roblox.com/docs/reference/engine/classes/SurfaceGui.md
- **Light spill — can a screen cast colored light?** A `SurfaceLight` on the screen part's front face
  casts light "from the whole surface" (Angle 0–180, Range, Color, Brightness, optional Shadows), and its
  output scales with the parent's surface size. https://create.roblox.com/docs/effects/light-sources
  Roblox gives scripts **no way to read video pixels** (no documented API), so the light cannot follow
  the picture automatically — **UNVERIFIED as a negative**. The workable design: the data pipeline
  pre-computes a per-second average color/luminance track for each film (ffmpeg; Archive Watch already
  samples frames for `colorMode`, Decision 025) and ships it as a compact table; the client tweens
  `SurfaceLight.Color/Brightness` along it in sync with `TimePosition`. Black-and-white films get a
  silver-blue flicker for free.
- Avoid stacked transparencies around the screen (curtains with Transparency, glass) — they re-render
  overlapping pixels. https://create.roblox.com/docs/performance-optimization/improve

### 2.5 Seating and the viewing camera
- `Seat`: touching an enabled seat welds the character (SeatWeld) about 2 studs above it; `Occupant`;
  `Seat:Sit(humanoid)` forces a sit; `Humanoid.SeatPart`; jumping exits; 3 s per-seat cooldown.
  https://create.roblox.com/docs/reference/engine/classes/Seat.md
- Camera: `CameraType = Scriptable` gives full control; `CameraMode = LockFirstPerson` hides the body;
  `CameraMinZoomDistance = CameraMaxZoomDistance` locks zoom; `FieldOfView` 1–120 (default 70).
  https://create.roblox.com/docs/workspace/camera
- Pattern: on `Seat.Occupant` change, the client switches to a "screening" camera — first-person head
  position, look clamped to a cone around the screen center (not fully Scriptable: let the player look
  around a little, it reduces claustrophobia), and a one-key "seat view / free view" toggle. Assign
  seats server-side with `Seat:Sit()` so a friend group sits together.

### 2.6 Spatial audio from the screen (new audio API)
- AudioPlayer / AudioEmitter ("virtual speaker") / AudioListener ("virtual microphone") /
  AudioDeviceOutput / Wire; effects AudioEqualizer/AudioCompressor/AudioReverb; old `Sound`/`SoundGroup`
  are "now discouraged". https://create.roblox.com/docs/audio/objects
- `AudioEmitter`: plays from its parent's position (Attachment/PVInstance); `SetDistanceAttenuation()`
  curve; `SetAngleAttenuation()` for directional projection along LookVector;
  `AcousticSimulationEnabled` (occlusion, diffraction, reverb; listener must also enable it);
  `AudioInteractionGroup` (listener hears emitter only in the same group — handy to keep the lobby
  from hearing a screening). https://create.roblox.com/docs/reference/engine/classes/AudioEmitter.md
- Design: VideoPlayer's audio wired to 2–3 emitters on Attachments behind the screen (left/center/right
  "speakers"), gentle distance curve so every seat hears the film at near-equal level (a cinema is not
  a point source), reverb sized per theme (palace = long, drive-in = dry, outdoors). A "private
  screening" can wire the film straight to AudioDeviceOutput (2D) instead.

### 2.7 Motion sickness and VR
- Roblox VR runs on Quest and PC VR via OpenXR; comfort presets (Comfort/Default/Expert) with vignette,
  stepped rotation, fixed third-person camera; Quest Auto Quality "aims to maintain a minimum of 72 frames
  per second"; "Mobile VR is sensitive to a high number of draw calls"; "Keep SurfaceGuis to a minimum";
  reduce semi-transparent objects. https://create.roblox.com/docs/production/publishing/vr-guidelines
- A seated theater is close to ideal VR content: no locomotion while seated, the user's head drives the
  camera (never script the camera in VR), a big stable screen, and a dark surround. Do not lock
  first-person look in VR; do not animate the camera to the seat (teleport with a fade).
- Flat-screen comfort: avoid camera-shake effects, keep FOV at default when seated, fade (not swoop)
  between lobby and seat.

---

## 3. Performance budgets (mobile-first)

- Audience: Q2 2026 ~123M DAU, 29B hours/quarter (SEC 8-K).
  https://www.sec.gov/Archives/edgar/data/0001315098/000162828026051059/ex991-robloxq22026earnin.htm
  Mobile share of activity ~72% per a secondary source — **UNVERIFIED** (Roblox's filings read here
  did not give a device split).
- Memory: Roblox publishes **no per-device client memory budget**; "For mobile devices, client memory
  usage is particularly important"; Studio over-reports memory, test on real devices.
  https://create.roblox.com/docs/projects/performance-optimization/memory
- Rendering guidance (https://create.roblox.com/docs/performance-optimization/improve):
  draw calls carry "significant overhead"; instance-share meshes; textures ≤512² normally, ≤256² for
  minor ones; RenderFidelity Automatic/Performance; few shadowing lights; avoid layered transparency;
  streaming is "the highest impact mechanism" for client memory; SLIM for static models.
- Working budget for one auditorium (author's targets, not Roblox numbers — **UNVERIFIED as official**):
  ≤ 300 draw calls on the seated view; ≤ 150k visible triangles total; ≤ 30 unique meshes; ≤ 12
  unique texture sets at 512² (one 1024² hero trim sheet for the proscenium); ≤ 4 shadow-casting lights
  (ideally 1); one VideoDisplay at 720p-class source; video segments sized so one preloaded segment plus
  the playing one stay well under ~300 MB on device. Measure with ShiftF2 render stats and the
  MicroProfiler scopes listed in the docs, and on the cheapest Android phone available.
- Video dominates memory and data: the Creator Dashboard **Video Service** charts show "Preloaded, never
  played" and "Played, never viewed" — keep both near zero (clear `VideoContent` when the screen is not
  in use). https://create.roblox.com/docs/cloud-services/video-service

---

## 4. Procedural / data-driven worlds

- **One kit, many themes**: a theme record (JSON/ModuleScript) names: auditorium length/width/rake,
  seat count and spacing, screen aspect (1.33 for silent/Academy, 1.37, 1.85, 2.39), proscenium kit
  piece, wall/ceiling trim sheet + `SurfaceAppearance.Color` tints, carpet, sconce style, light colors,
  reverb preset, ambient sound, marquee text style. A server script assembles the room from
  **Packages** at reserved-server start.
- Theme examples: **silent-era picture palace** (organ pit, gilt proscenium, 1.33 screen, warm
  tungsten); **1950s newsreel theater** (small, Art Moderne, continuous-show clock); **drive-in**
  (outdoor, night sky, cars as seats, `Soft` lighting, screen on a frame tower, car-radio 2D audio);
  **Art Deco movie palace**; **nickelodeon storefront** (1905–15, piano, 1.33); **film society
  screening room**. Theme choice can follow the film's year/category from the catalog, which keeps
  "no AI copy" intact: the room is rules over metadata.
- **Packages**: "group instances into reusable units ... shared across a team or multiple projects";
  PackageLink with AutoUpdate ("when a place is opened in Studio"); nested packages; Update All across
  places; group ownership chosen at creation (cannot be transferred).
  https://create.roblox.com/docs/projects/assets/packages
  Use packages for the kit pieces and the screen/audio rig, so a fix lands in every theme place.
- **Roblox generative tools (2025–2026)**:
  - **Cube 3D**: text-to-shape model, open weights v0.1 (Mar 2025) and v0.5 (Jul 2025), plus
    **CubePart** (May 2026, part-controllable). Output is untextured .obj; texture generation is listed
    as "upcoming". The repo's LICENSE is the **"CUBE3D Research-Only RAIL-MS License"** — "for academic
    or research purposes only"; "providing a hosted service incorporating the Artifact" counts as
    distribution. **Not usable for running the model ourselves in production.**
    https://github.com/Roblox/cube , https://raw.githubusercontent.com/Roblox/cube/main/LICENSE
    (Hugging Face card says "openrail" — conflicts with the repo file; the repo file is the stronger
    source.) https://huggingface.co/Roblox/cube3d-v0.5
  - **In-Studio / in-experience generation** (Roblox-hosted, not the open weights):
    `GenerationService` (GenerateModelAsync; GenerateMeshAsync listed as deprecated on some pages),
    5 generations/min per experience, server-only, prompt moderation.
    https://create.roblox.com/docs/reference/engine/classes/GenerationService
    Usage rights for these outputs follow the Roblox Terms of Use, not the RAIL license — the exact
    clause was not read: **UNVERIFIED**.
  - **Studio MCP server** (official): tools include `generate_mesh` ("textured 3D mesh from a text
    prompt"), `generate_material`, `generate_procedural_model` (builds from primitive parts),
    `insert_asset`, `search_asset`, `upload_image`, `execute_luau`, `start_stop_play`,
    `screen_capture`, `get_console_output`; **Claude Code is on the Quick-connect list**; macOS binary
    `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.
    https://create.roblox.com/docs/studio/mcp
    This is the most useful 2026 tool for an agent: it can build, playtest and screenshot a place.
  - **Production verdict**: generated meshes are fine for props seen from a seat (popcorn machine,
    ashtrays, lamp shades) after review; architecture (the room itself) should be procedural/kit-built
    for consistency, instancing and triangle control. Quality of generated meshes vs. hand-built:
    **UNVERIFIED** — evaluate on 10 prompts before committing.

---

## 5. Precedents and player expectations

- **CineBlox** — "Roblox's largest movie destination"; watch with friends, order snacks, be staff;
  group page claims 34M+ visits (self-reported). https://www.roblox.com/games/5797596824/CineBlox ,
  https://www.rolimons.com/group/5101119
- **The Cinema Movie Experience** — watch films together, serve popcorn, earn Robux tips from other
  players. https://www.roblox.com/games/70796533480456/The-Cinema-Movie-Experience
- **ROBLOX CINEMA**, **The movie theater roleplay**, **Videos Movies** — smaller community cinemas.
  https://www.roblox.com/games/394107886/ROBLOX-CINEMA ,
  https://www.roblox.com/games/9364082713/The-movie-theater-roleplay ,
  https://www.roblox.com/games/139502387707079/Videos-Movies
- **Regal × Super League** virtual theatre (2026-01-16 → 02-02): endless runner, popcorn avatar items,
  real free-popcorn codes; no in-world film. https://ir.superleague.com/news-events/press-releases/detail/285/super-league-and-regal-launch-roblox-theatre-experience-for
- Studio marketing: *Beetlejuice Beetlejuice* trailer in a lobby with a Fandango box office; *Godzilla x
  Kong* "first immersive movie trailer". https://www.mediapost.com/publications/article/398359 ,
  https://www.marketingdive.com/news/godzilla-x-kong-roblox-first-immersive-movie-trailer-metaverse/710122/
- Licensing context: Roblox License Manager (July 2025) with Lionsgate, Netflix, Sega, Kodansha.
  https://about.roblox.com/newsroom/2025/07/roblox-launches-new-licensing-platform-for-experiences
- What these tell us (player-count and review quality of each **UNVERIFIED**; the listing pages showed
  no live servers when read): Roblox cinemas are **roleplay + social** first — staff jobs, snacks,
  tipping, seating with friends — and the "film" is often short or user-made. Players expect: seats
  that work, friends sitting together, snacks/avatar items, emotes, chat, something to do before the
  show. Hangout leaders (Brookhaven, MeepCity) are free-roam social spaces (secondary sources).
  An archive cinematheque differentiates by **real films, real rooms of their era, and quiet** —
  pre-show is the lobby's job (posters from the catalog, the program notes from archive.org metadata).
- Copyright risk for uploads: a "Copyright Video Autostrike" thread exists (2026-01-09, content not
  read) — public-domain films can still trip automated matching. **UNVERIFIED** details.
  https://devforum.roblox.com/tag/video

---

## 6. Professional-quality 3D by an AI agent, no human artist

### 6.1 Pipeline
1. **Blender, headless, scripted with `bpy`** (`blender -b -P build.py -- theme.json`): generate the
   room procedurally from the theme record — arrays/instances for seats, curves + screw/solidify for
   moldings, boolean-free modeling (booleans make bad topology), bevel modifiers for highlight edges,
   UVs via Smart UV / cube projection onto **trim sheets**. Blender Python API:
   https://docs.blender.org/api/current/
2. **Materials from CC0 PBR libraries**, baked down to Roblox's 4 maps (color, normal-OpenGL,
   roughness, metalness) at 512²/1024²; a single trim sheet per theme carries molding, panel and gilt
   strips so the whole proscenium is one texture set.
3. **Triangle discipline per mesh** (< 20k, aim < 5k for repeated pieces), seat as one mesh instanced,
   collision as simple invisible Parts (`CanCollide` off on decorative meshes, `CollisionFidelity` Box).
4. **Render verification before import**: Blender renders turntables/reference views to PNG which the
   agent inspects (the same sim-validate discipline used for RealityKit work here).
5. **Import**: 3D Importer (batch queue) in Studio, or **Open Cloud Assets API** — Model type accepts
   .fbx/.gltf/.glb/.rbxm and imports "a Model container of MeshParts, uploaded as packages"; one asset per
   call, ≤ 20 MB; only .fbx can be updated in place (new version); API key with asset read/write; images
   < 8000×8000. https://create.roblox.com/docs/cloud/guides/usage-assets
6. **Assemble and test in Studio through the official MCP server** (`execute_luau`, `start_stop_play`,
   `screen_capture`). Device truth still needs a real phone (project rule: real devices only).

### 6.2 CC0 sources and licenses (all verified on their own pages)
- **Poly Haven** (HDRIs, textures, models): "Our assets are all licensed as CC0, which is effectively
  Public Domain"; "You can use our assets for any purpose"; "You do not need to give credit"; site
  content like renders/logos is not CC0. https://polyhaven.com/license
- **ambientCG** (PBR materials): "All ambientCG assets are provided under the Creative Commons CC0 1.0
  Universal License"; commercial use allowed; attribution optional. https://docs.ambientcg.com/license/
- **Kenney** (low-poly kits): "all game assets on the asset pages are public domain licensed (CC0)";
  commercial use allowed; don't use the Kenney logo. https://kenney.nl/support
- Fit: ambientCG/Poly Haven for velvet, carpet, plaster, wood, brass, concrete (drive-in), night HDRIs as
  sky references; Kenney is stylized and only suits a deliberately low-poly look. Poly Haven models are
  often high-poly — decimate in Blender before import.
- Period reference (ornament, signage) can come from public-domain photographs of real theaters
  (e.g. Library of Congress HABS drawings) — **UNVERIFIED** as a specific source; check each item's
  rights statement.

### 6.3 Where an agent will fall short (honest risks)
- Art direction and "taste" across a whole room — mitigate with strict kits, real architectural
  reference, and owner review of rendered stills before import.
- Generated meshes (Cube 3D, `generate_mesh`) are untextured or low-detail and license-encumbered (open
  weights) — keep them to small props.
- Emissive maps' shipping status, SurfaceGui bloom behavior, reserved-server spin-up time and the
  current video fee are all open and must be measured.

---

## Open items to verify by measurement
1. Reserved-server spin-up + teleport time on a phone (target < 10 s).
2. Current video upload fee and whether ~18 five-minute segments per feature is affordable/allowed
   within 20 uploads/day.
3. Seamless A/B segment handoff with two VideoPlayers (no audible gap).
4. SurfaceGui Brightness > 1 with LightInfluence 0: does it bloom?
5. SurfaceLight color tween from a precomputed color track: cost on a low-end Android.
6. Emissive SurfaceAppearance status.
7. Server MaxPlayers allowed range for the Theater place.
