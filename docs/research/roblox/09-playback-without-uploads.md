# Playing our films on Roblox without paid uploads (2026-10-15)

Owner, 2026-10-15: *"I have seen multiple instances of people streaming
'youtube videos' into Roblox, so I wonder if there is something to that.
Obviously, if we have to pay to upload public domain films, it won't work for
our context. Can you look at how others have streamed youtube into Roblox and
see if we can solve for it in a novel way without uploads/charges?"*

Evidence: `07-youtube-streaming-precedents.md` (what others built, with URLs)
and `08-frame-streaming-limits.md` (the platform's numbers). This file is the
conclusion, plus one experiment run here.

## 1. How "YouTube in Roblox" works

Every project uses the same pipeline (07 §1). An off-platform server runs
yt-dlp and ffmpeg, then serves raw pixels over HTTP. The Roblox game server
fetches them with HttpService and relays them to each player over
RemoteEvents. Each player's device paints them into an EditableImage, a
picture a script can draw on.

The best documented results:

- 213x120 at 10 fps (2022).
- About 24 fps claimed by arithmetic, not measured (2025).
- **None with sound.** Roblox cannot play or generate audio at runtime, so
  projects either stayed silent or played an uploaded Roblox sound as the clock
  (08 §5).

The "Netflix in Roblox" clips are a cheat-executor script. They play only on the
cheater's own machine (07 §5).

## 2. Why we should not copy it

- **Roblox told creators not to.** The staff post that opened EditableImage
  (2024-11-20) says: *"Do not load asset-like content from off-platform sites
  or unmoderated sources"*. The same post ties EditableImage to a 13+,
  ID-verified owner who opts in, "to increase creator accountability" (07 §7).
- **The owner carries the risk.** The account at risk is the ID-verified owner's,
  and the Community Standards forbid "attempting to circumvent our safety
  systems".
- **Projects went private or were banned.** Authors kept their code private
  because it "bypasses Roblox image moderation", and community replies say such
  projects "ended up all getting banned". No official ban was found (07 §9).
- **The ceiling is low anyway:**
  - The game server relays every frame to every viewer separately.
  - At the commonly cited ~50 KB/s per player (a community figure, not
    Roblox's), the stream fits about 160x90 grayscale.
  - Live streaming connections (WebSocket, SSE) are blocked outside Studio
    (08 §2, §12).

## 3. A novel route that stays inside the rules: the moderated flipbook

Roblox charges for **video** uploads. Its asset limits table lists **no fee and
no upload cap for images** (create.roblox.com/docs/cloud/guides/usage-assets,
read 2026-10-15). Images display at up to 1024x1024. So a film can be cut, in
our pipeline, into **frame sheets**:

- 20 frames at 256x192 tile one 1024x960 sheet.
- Each sheet goes through Roblox's normal image moderation.
- The theater plays the film by stepping an ImageLabel's `ImageRectOffset`
  across the sheet, the standard sprite-sheet technique. It preloads the next
  sheets with `ContentProvider:PreloadAsync`.

What this route gives us:

- **Rules:** every pixel the player sees has passed moderation, and nothing is
  fetched from off-platform at runtime.
- **Bandwidth:** frames come from Roblox's own image CDN, not through our game
  server, so the per-player relay limit does not apply.
- **No EditableImage:** so no ID-verified opt-in is needed for playback.
- **Better Watch Together:** every client computes the frame from the server's
  clock, so playback is deterministic. Sync is exact, which uploaded video
  cannot promise (its TimePosition is per client and does not replicate,
  01 §1).

**Measured here** on *A Trip to the Moon* (1902, `ATripToTheMoon20Fps`, 678 s,
320x240 source):

- `ffmpeg -vf "fps=12,scale=256:192:flags=lanczos,tile=4x5" -q:v 3` gives
  **407 sheets**, 92 MB as JPEG, or about 1.1 Mbps from the CDN.
- One frame enlarged to 1024x768 looks like a good VHS copy: faces and set
  detail are readable.

What it costs is **volume, not money**:

- At 12 fps a film needs **0.6 images a second**.
- An 11-minute short is about 400 images and a 70-minute feature about 2,500.
- The 8,089 visible silent films (4,326 hours) would be **~9.3 million images**.
  Even the 4,114 silent films of 15 minutes or less would be about 1 million.
- A curated program is the realistic scale: 100 shorts of about 10 minutes is
  about 36,000 images.

Lowering the bar (160x120, 8 fps, 48 frames a sheet) cuts a 70-minute feature
to about 700 images.

**Unknowns that decide it.** Each can be settled with a free account:

1. The real image quota. The docs list none, while a third-party blog reports
   throttling around 200-300 a month (noping.com). Read the actual number from
   `GET /cloud/v2/users/{id}/asset-quotas`.
2. Whether thousands of near-identical frame sheets trip moderation or spam
   detection, and how long moderation takes per sheet.
3. Whether Roblox recompresses or downscales sheets in a way that blurs 256x192
   tiles.
4. Whether stepping `ImageRectOffset` at 12 fps holds on a mid-range phone, and
   how much memory preloading takes.

## 4. Sound

- **Silent films need no upload at all.** They can be scored from the Creator
  Store's free licensed music, which has more than 100,000 tracks. Whether its
  license fits continuous accompaniment is for the owner and Roblox to settle
  (08 §5).
- **Sound films need their soundtrack uploaded as audio.** Audio is free, up to
  7 minutes a file, so a 90-minute film is 13 uploads.
  - The documented cap is **100 a month** on an ID-verified account
    (usage-assets table, 2026-10-15); one secondary source says 2,000 a month.
  - At 100 a month, that is about 7 sound features a month.

So the free route favors exactly what the catalog is richest in: silent film.

## 5. Rejected: hiding a codec inside images

Uploading images that are not pictures but compressed video bitstreams, read
back with `EditableImage:ReadPixelsBuffer` and decoded in Luau, would pack far
more film per image. It is rejected on principle: the moderator would approve
noise while players saw a film, which is circumventing the safety system the
flipbook route respects.

## 6. Recommendation

1. Do not stream from off-platform, whatever the precedents do.
2. If Roblox goes ahead, the free route is a **curated silent-film program as
   moderated flipbooks**, scored from Roblox's licensed library: Méliès, early
   Chaplin and Keaton shorts, silent cartoons. It plays at 256x192 and 12 fps,
   in exact sync for Watch Together.
3. Before any building, take the four measurements in §3. The first needs only
   a Roblox account and one API call.
4. Feature-length and sound films stay out of reach without paid video uploads,
   unless Roblox changes its video terms. Its roadmap puts the next video API in
   mid 2027.
