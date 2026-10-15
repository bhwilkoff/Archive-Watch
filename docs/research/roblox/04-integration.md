# Roblox ↔ Archive Watch backend integration (research, 2026-10-15)

Scope: how a Roblox experience could talk to the Watch Together room Worker
(`archivewatch-pulse.benwilkoff.workers.dev`, Cloudflare Worker + D1) and the
catalog (`archivewatch.org/catalog-index.json`), and the reverse direction.
Sources are Roblox's own Creator Hub docs (most read from the canonical
markdown in github.com/Roblox/creator-docs), DevForum staff posts and
Roblox's Community Standards. Anything not confirmed in a primary source is
marked **UNVERIFIED**.

---

## 0. Bottom line

- **The data plane joins easily.** A Roblox game server can poll our Worker
  over HTTPS (HttpService, server only, 500 external requests/min per server)
  at 1 s, and our Worker can PUSH into live Roblox servers through Open Cloud
  `publishMessage` (1 KiB, delivered in about 1–2 s on a best-effort basis).
  Room state (archiveID, copy, playing, position, timestamp) fits comfortably
  in 1 KiB.
- **The film does not join.** Roblox plays only **uploaded Roblox video
  assets**. Each one is limited to 5 minutes, costs 2,000 Robux, needs a 13+
  ID-verified uploader, is capped at 20 uploads a day, and only 2 videos can
  play at once. Nothing documented lets a VideoPlayer stream an archive.org
  URL. A 90-minute feature would be 18 segments, 36,000 Robux and a day of
  quota, and the segments would have to be cut from the exact copy the room
  names (Decision 143). That makes the catalog-scale "watch any film in Roblox"
  idea infeasible. The most it allows is a small hand-picked set of films.
- **Policy blocks the natural cross-platform UX.** Community Standards say
  "You may not link to, share, or display URLs of any external websites or
  services" and "Any other efforts to direct users off of Roblox ... are
  prohibited." So a Roblox experience **cannot show "archivewatch.org" or tell
  players to type a code into the Archive Watch app**. The other direction
  (our apps opening Roblox) is ours to do.
- **Posters**: there is no supported way to show an image fetched from an
  external URL. In theory you could fetch bytes, decode them in Luau and write
  them into an EditableImage. That pushes unmoderated imagery past Roblox
  moderation and is a policy risk (**UNVERIFIED** whether it is explicitly
  banned). The supported route is uploading each poster as an image asset
  through the Open Cloud Assets API, where it is moderated. Note that this
  re-publishes TMDb artwork on Roblox, which is a licensing question for the
  owner.

---

## 1. HttpService (Roblox → our Worker)

| Fact | Value | Source |
|---|---|---|
| Where it runs | "allows HTTP requests to be sent from **experience servers**". Client scripts cannot make requests. Secrets error on the client too | [HttpService API ref](https://create.roblox.com/docs/reference/engine/classes/HttpService) ([raw yaml](https://raw.githubusercontent.com/Roblox/creator-docs/main/content/en-us/reference/engine/classes/HttpService.yaml)); [Secrets](https://create.roblox.com/docs/cloud-services/secrets) |
| Enable | Off by default. Studio → File → Experience Settings → Security → *Allow HTTP Requests* | [In-experience HTTP requests](https://create.roblox.com/docs/cloud-services/http-service) |
| Rate limit | **500 external HTTP requests per minute per game server**. Open Cloud calls from HttpService have a separate budget of **2,500/min per server**. Going over can stall request methods for about 30 s | same page; HttpService ref ("500 requests per minute") |
| Protocol | **HTTPS only** | http-service page |
| Ports | 80 and 443 allowed. Port 1194 and everything below 1024 is blocked (403 / ERR_ACCESS_DENIED) | http-service page |
| Headers | RequestAsync: "`User-Agent` and `Roblox-Id` are locked by Roblox"; `Content-Length` is computed. The http-service page's *Limitations* section says "Only the x-api-key and content-type headers are allowed" and that x-api-key must be a Secret. Read in context, that applies to **Open Cloud** calls. Whether custom headers (e.g. our host key) are allowed toward third-party hosts is **UNVERIFIED**. A safe design puts the key in the URL or as a Secret in an allowed header | HttpService ref; http-service page |
| Body/response size | **No documented limit** (only JSONEncode's 50 MiB buffer is documented). Treat as **UNVERIFIED**; keep responses small | HttpService ref |
| Timeout | RequestAsync accepts a timeout "no greater than the default request timeout". The default value is not documented (**UNVERIFIED**) | HttpService ref |
| Domains | No allow-list for third-party domains is documented. `*.workers.dev` is not blocked by anything in the docs, and a DevForum resource uses a Cloudflare Worker as an HttpService relay ([thread](https://devforum.roblox.com/t/resource-rbxhttpservice-async-http-requests-with-built-in-batching-for-roblox/4708973)). Not tested by us (**UNVERIFIED** for our Worker specifically). Our Worker's own Cloudflare WAF/bot rules must not challenge Roblox datacenter IPs |  |
| Secrets Store | Per experience: **500 secrets, 1,024 chars each**. Each secret is **bound to a domain** (`*.example.com` wildcard allowed; `*` discouraged). Read with `HttpService:GetSecret(name)` **on the server**. The value is opaque (prints `Secret(name)`) and can only be composed with `AddPrefix`/`AddSuffix`. **Secrets can go in the URL or headers, never the body.** Not available in local playtest (use Local Secrets) | [Secrets stores](https://create.roblox.com/docs/cloud-services/secrets) |
| WebSockets / SSE | `HttpService:CreateWebStreamClient` (SSE, RawStream, WebSocket) is **Studio-only**: "Any CreateWebStreamClient() requests made in a live experience will be blocked." No timeline given (staff post, 2025-10-23) | [DevForum announcement](https://devforum.roblox.com/t/websockets-support-in-studio-is-now-available/4021932); [WebStreamClient](https://create.roblox.com/docs/reference/engine/classes/WebStreamClient) |
| Observability | Creator Dashboard shows HTTP request-count and response-time charts by method and status | http-service page |
| Latency | Not documented. Expect roughly one HTTPS round trip from a Roblox datacenter to the nearest Cloudflare PoP, likely tens of ms (**UNVERIFIED**) | |

**Implications for us**
- If our host key is ever stored in Roblox, it must be a domain-bound Secret
  placed in the URL or an allowed header. Our Worker currently expects the
  key in a request field (**check the Worker**). It would need an alternative
  carrier, such as `?k=` or a header, because a Secret cannot go into a body.
- A Roblox server **guest** needs no key at all (a guest GET never carries
  one, SCRATCHPAD item 15).

## 2. Cross-server state inside Roblox

### MessagingService (pub/sub between live servers, also reachable from Open Cloud)
Source: [MessagingService ref](https://create.roblox.com/docs/reference/engine/classes/MessagingService), [Cross-server messaging](https://create.roblox.com/docs/cloud-services/cross-server-messaging), [Open Cloud messaging guide](https://create.roblox.com/docs/cloud/guides/usage-messaging)

| Limit | Value |
|---|---|
| Message size | 1 KiB (1,024 chars) |
| Topic name | 80 chars |
| Sent per server | 600 + 240 × players / min |
| Received per topic | 40 + 80 × servers / min |
| Received per game | 400 + 200 × servers / min |
| Subscriptions per server | 20 + 8 × players |
| Subscribe requests | 240 / min / server |
| Delivery | **"best effort and not guaranteed"**, typically **1–2 s** |
| Shared with Open Cloud | Yes, the engine and the Open Cloud API share these limits |

### MemoryStoreService (fast, expiring, cross-server)
Source: [Memory stores](https://create.roblox.com/docs/cloud-services/memory-stores)
- Memory quota: 64 KB + 1.2 KB × users. Request units: 1,000 + 120 ×
  concurrent users per minute. Single-partition throttle starts around 30k
  RU/min. Hash map keys allow about 5k writes and 15k reads per minute.
- Item ≤ 32 KB; expiration ≤ 3,888,000 s (45 days); sorted map/queue ≤ 1M
  items / 100 MB.
- Open Cloud v2 has memory-store sorted-map and queue endpoints under
  `/cloud/v2/universes/{id}/memory-store/...`
  ([storage reference](https://create.roblox.com/docs/cloud/reference/features/storage)),
  so **our Worker could write room state directly into a MemoryStore** that
  every Roblox server reads.

### DataStoreService (durable)
Source: [Error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits)
- Per server: 60 + 40 × players reads and writes per minute. Experience-wide
  (shared with Open Cloud): read 300 + 40 × CCU, write 300 + 20 × CCU per
  minute. Per key: 25 MB/min read, 4 MB/min write. Value ≤ 4,194,304 chars.
  Storage: 500 MB + 1 MB per lifetime user.
- Too slow and too throttled for second-by-second playback state. Suitable
  for a cached copy of the catalog subset or for favorites.

### Can a Roblox server be a room participant polling at 1–2 s?
**Yes, within the documented limits.** Polling at 1 s uses 60 of 500
requests per minute per server. Roblox server timing is the usual Luau
`task.wait` loop. The server holds the room snapshot and replicates it to
its clients (attributes / RemoteEvent). Clients then set
`VideoPlayer.TimePosition` (see §5).

**Our cost to watch: Cloudflare Workers Free allows 100,000 requests a day**
(Cloudflare plan limits, not re-fetched here, **UNVERIFIED this session**).
One Roblox server polling every second is 86,400 requests/day, close to the
entire free quota. Ten concurrent servers would blow through it. Two ways to
stay inside the $0 constraint:
1. **Push instead of poll.** On every host write, the Worker calls Open Cloud
   `publishMessage` (one outbound call per state change, not per server per
   second). Roblox servers fall back to a slow poll every 15–30 s to recover
   from dropped messages, because delivery is best-effort.
2. Or the Worker writes the room into a MemoryStore sorted map via Open
   Cloud. Roblox servers then read it at 1 s against **Roblox's** quota
   instead of ours.

## 3. Open Cloud: from our Worker into Roblox

| API | What it gives us | Source |
|---|---|---|
| **Messaging** `POST https://apis.roblox.com/cloud/v2/universes/{universe}:publishMessage`, body `{"topic","message"}`, `x-api-key` (scope `universe-messaging-service:publish`) or OAuth Bearer. 200 with an empty body | **Yes: the Worker can push "room state changed" to every live server subscribed to the topic** (e.g. topic `room-ABCD`). "Currently, the API can only target live game servers." 1 KiB, best-effort, 1–2 s | [Messaging usage guide](https://create.roblox.com/docs/cloud/guides/usage-messaging) |
| **Memory stores v2** (sorted maps, queues, flush) | Worker-written room snapshot that servers read | [storage reference](https://create.roblox.com/docs/cloud/reference/features/storage) |
| **Data stores v2** | Durable writes (shares the experience-wide quota) | same |
| **Assets** `POST https://apis.roblox.com/assets/v1/assets` (+ `GET /assets/v1/operations/{id}` to poll moderation) | Bulk upload of posters (Decal/Image: png/jpeg/bmp/tga, < 8000×8000, cannot be updated) and videos. Each request is limited to 20 MB (video page says 3.75 GB; the docs don't reconcile the two). Moderation result is in `moderationResult.moderationState` | [Assets usage guide](https://create.roblox.com/docs/cloud/guides/usage-assets) |
| Asset quotas | `GET /cloud/v2/users/{user_id}/asset-quotas` (Beta) | [Assets reference](https://create.roblox.com/docs/cloud/reference/features/assets) |
| Universes/places | Publishing a place and restarting servers from external scripts is documented in general terms ([external tools](https://create.roblox.com/docs/projects/external-tools)). The exact "restart servers" endpoint was not found in the English reference (**UNVERIFIED**) | |
| Rate limits | Apply per API-key **owner** (user or group) or per OAuth token. Responses carry `x-ratelimit-limit/remaining/reset`. Handle 429. Per-endpoint numbers are on each endpoint's page | [Rate limits](https://create.roblox.com/docs/cloud/reference/rate-limits) |
| **Webhooks** | Only subscription, commerce, refund, Right-to-Erasure, experiment-harm and sample events. **No gameplay or server events**, so Roblox cannot webhook us when a player joins a theater; the game server must call our Worker itself. HMAC-SHA256 `roblox-signature` header | [Webhook notifications](https://create.roblox.com/docs/cloud/webhooks/webhook-notifications) |

**OAuth 2.0 ("Sign in with Roblox")**
- Authorization-code flow with PKCE (public clients send no secret). Endpoints
  are under `https://apis.roblox.com/oauth/v1/{authorize,token,userinfo,token/introspect,token/resources,token/revoke}`
  plus `.well-known/openid-configuration`.
  ([OAuth reference](https://create.roblox.com/docs/cloud/auth/oauth2-reference),
  [overview](https://create.roblox.com/docs/cloud/auth/oauth2-overview))
- Scopes in discovery: `openid, profile, email, verification, credentials,
  age, premium, roles`, plus resource scopes such as
  `universe-messaging-service:publish`. Some scopes are reserved for official
  Roblox apps.
- Tokens: auth code 1 min single-use; **access 15 min**; **refresh 90 days,
  single-use (rotating)**.
- Registration: the developer must be **ID verified**, and authorizing
  creators must be 13+. **Private mode is capped at 10 unique users** until
  review. Review needs a demo video of at most 1 minute starting signed-out,
  plus a written justification per scope. A public app cannot go back to
  private. Redirect URIs: HTTPS, localhost, or **custom schemes**
  (`my-app://...`), at most 10, each at most 256 chars.
  ([registration](https://create.roblox.com/docs/cloud/auth/oauth2-registration))
- The Messaging usage guide calls third-party OAuth app support **beta**.
- **We don't need OAuth for rooms.** One API key held as a Worker secret
  publishes to our own universe. OAuth would only matter if we wanted to show
  a Roblox identity in our apps. That is an account-like feature and runs
  against Decision 009 ("no accounts").

## 4. Deep links into Roblox, and the reverse

- **Deep links (deprecated).** Web: `https://www.roblox.com/games/start?placeId=<id>&launchData=<string>`.
  App: `roblox://placeId=<id>&launchData=<string>`. "The decoded launch data
  can't exceed 200 bytes." It is read on the server via
  `Player:GetJoinData().LaunchData`, and is visible to and editable by the
  user, so it must never carry the host key. The page states "This process is
  deprecated" and points to Share links.
  ([Deep links](https://create.roblox.com/docs/production/promotion/deeplinks))
  Whether the deprecated URL still delivers `LaunchData` on every platform in
  Oct 2026 is **UNVERIFIED**. DevForum reports cases where the app opens but
  does not join, and blank join data via Safari
  ([beta thread](https://devforum.roblox.com/t/developer-deeplinking-beta/1904069)).
- **Share links (current).** Created in Creator Dashboard → Creations →
  Share Links, with optional custom LaunchData per link and no limit on the
  number of links. They are **made by hand in the dashboard, one per
  campaign**, and no documented API creates them per room (**UNVERIFIED**
  that none exists). That rules them out for per-room codes, which are
  dynamic.
  ([Share links](https://create.roblox.com/docs/production/promotion/share-links))
- **So a phone app could open Roblox into a theater with the room code** as
  `launchData={"room":"ABCD"}` (≈20 bytes) via the deprecated URL. The
  Roblox server reads it, then subscribes and polls that room. Fallback: the
  player types the room code on a keypad inside the experience. That is
  allowed because the code is entered *into* Roblox.
- **Reverse direction (Roblox → our apps) is blocked by policy.**
  [Community Standards](https://about.roblox.com/community-standards),
  *Directing Users Off-Platform*: "You may not link to, share, or display URLs
  of any external websites or services" outside the Social Links feature
  (which requires age check and 16+), and "Any other efforts to direct users
  off of Roblox to an external website or service are prohibited." Showing a
  room code captioned "enter this in Archive Watch" is an effort to direct
  users off Roblox. Treat it as **not allowed** (not tested with Roblox
  moderation). `PolicyService.AllowedExternalLinkReferences` is now a legacy
  field that always returns an empty array
  ([PolicyService](https://create.roblox.com/docs/reference/engine/classes/PolicyService)).
  The experience's own Social Links (Discord, YouTube, etc. on the game page)
  are the only sanctioned outbound route.

## 5. Cross-platform rooms: a concrete architecture

```
Archive Watch host (Mac)  --host key-->  Worker + D1  (room ABCD)
                                            |  on every host write:
                                            |  POST apis.roblox.com/cloud/v2/universes/U:publishMessage
                                            |       {topic:"room", message:"{ABCD,archiveID,copy,playing,pos,ts}"}
                                            v
Roblox game servers (theater place) -- SubscribeAsync("room") --> filter by code
   |  fallback: HttpService GET /room/ABCD every 15-30 s (guest, no key)
   |  replicate snapshot -> clients (attributes)
   v
Roblox clients: VideoPlayer (Roblox asset for that archiveID+copy, segment k)
                TimePosition = pos + (now - ts) - segmentStart(k)
```

- **Roblox players joining a room made elsewhere**: works as guests, by
  keypad code or launchData. Every room write stays with the host, so Roblox
  needs no key.
- **Others joining a room "hosted" in Roblox**: possible only if a Roblox
  server holds a host key (as a domain-bound Secret) and writes to the Worker.
  Roblox players cannot be told where to go to join (policy, §4), so the
  only real use is a Roblox host whose guests are also in Roblox. That would
  not need our Worker at all.
- **Sync tolerance.** `VideoPlayer.TimePosition` is a writable double (seconds)
  that "can be changed ... before and during playback". `Play()`/`Pause()`
  replicate server→client and `IsPlaying` replicates. The docs give no seek
  accuracy and no sync guidance
  ([VideoPlayer](https://create.roblox.com/docs/reference/engine/classes/VideoPlayer)).
  Each video asset must be downloaded to each device before it plays
  ([VideoService](https://create.roblox.com/docs/cloud-services/video-service)).
  Error budget, estimated rather than measured (**UNVERIFIED**): push delivery
  takes 1–2 s, which the timestamp corrects for. Our wall-clock offset vs.
  Roblox server time plus server→client replication adds about 0.1–0.3 s,
  and seek granularity to a keyframe is also uncertain. A realistic target
  is the same as our other guests: correct by seeking when drift exceeds
  about 1 s. Frame accuracy is not a realistic target. `PlaybackSpeed` (0–1
  documented range) changes pitch, so rate nudging isn't available. Seek
  only.
- **The film-asset gap** ([Video frames](https://create.roblox.com/docs/ui/video-frames),
  [Assets usage](https://create.roblox.com/docs/cloud/guides/usage-assets)):
  uploads need a 13+ ID-verified account. Each video is **at most 5 minutes**,
  .mp4/.mov, ≤ 4096×2160, < 3.75 GB, **2,000 Robux per upload**, **20 uploads
  a day**. **At most 2 videos play simultaneously.** The uploader must hold
  the rights and moderation applies. (Older docs and the 2024 beta said
  30 s and 3 per 30 days, so the limits have loosened. The current English
  page is the one quoted.) A 90-minute film is 18 assets and 36,000 Robux.
  Segment boundaries need a hand-off between two VideoPlayers, which the
  two-video cap just allows (**UNVERIFIED** that the cut is gapless). Each
  asset set is tied to ONE archive.org copy, so a room's `copy` field must
  map to a Roblox asset table and rooms on other copies cannot be joined
  from Roblox. Captions, versions and the catalog's breadth are all lost.
  An honest product would be a small set of short films (cartoons, newsreels,
  shorts under 5–10 minutes). It cannot be the 26k catalog.
- `PolicyService.IsEndlessContentAutoplayAllowed` exists. A theater that
  auto-advances films should check it per player (**UNVERIFIED** whether a
  queued film counts as "endless content").

## 6. Posters and images

- `AssetService:CreateEditableImageAsync(content)` loads only assets that are
  "associated with and/or owned by a creator of the experience" (or created
  in-experience). It does not take an external URL
  ([AssetService](https://create.roblox.com/docs/reference/engine/classes/AssetService)).
- `AssetService:CreateEditableImage({Size})` + `EditableImage:WritePixelsBuffer`
  (RGBA, 4 bytes/pixel, max 1024×1024) can draw any pixels. **In theory** the
  server fetches a JPEG over HttpService, decodes it in Luau (community
  decoders exist, unreviewed), and replicates the pixels. EditableImage must
  be enabled per experience (*Enable Mesh / Image APIs*, after reviewing the
  Terms). Client memory budgets are "strict"
  ([EditableImage](https://create.roblox.com/docs/reference/engine/classes/EditableImage)).
  **Policy**: this displays imagery that never passed Roblox moderation. No
  primary source found that explicitly forbids it (**UNVERIFIED**). A DevForum
  reply says Roblox restricts free-form content via EditableImage
  ([thread](https://devforum.roblox.com/t/do-editableimages-work-for-every-country/4736748)).
  Treat it as a moderation-bypass risk to the owner's account.
- **Supported route**: upload each poster as an Image/Decal through Open
  Cloud Assets (`POST /assets/v1/assets`), poll the operation for
  `moderationState`, and store `archiveID → rbxassetid` in a DataStore or
  bundled ModuleScript. Image uploads have no Robux cost on the docs page
  (**UNVERIFIED** that they are free; the Robux cost is documented for video
  and audio limits only). Daily image quotas are not stated; query
  `asset-quotas` (**UNVERIFIED** numbers). Posters cannot be updated, only
  replaced. 26k uploads plus moderation is a large job, and should be limited
  to the titles the theater actually offers.
- Rights: catalog posters are TMDb/Wikimedia artwork. Re-publishing them as
  Roblox assets under our account is redistribution. That is a licensing
  question (TMDb terms, Decision 007/010) for the owner, not a technical one.

## 7. Open questions worth a measurement before any build
1. Does our Worker answer HttpService from a live Roblox server (WAF/bot
   rules on Roblox IPs)? One request from a published test place.
2. Does `roblox.com/games/start?...&launchData=` still deliver LaunchData
   on iOS, Android and desktop in Oct 2026?
3. VideoPlayer seek accuracy and segment hand-off gap, measured on a real
   device (project rule: real devices only).
4. Ask Roblox, or read the full Terms of Use (updated 2026-04-30 per a
   tracker, not verified), on EditableImage with external pixels and on
   displaying a code meant for another app.
