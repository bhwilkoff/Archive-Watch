# Creation Studio — Publishing / Upload (Feature 7)

> Research brief. The native macOS **Creation Studio** exports a finished video;
> Feature 7 lets the user **publish it to YouTube OR archive.org under their own
> account**, with **NO backend server** — all auth + upload happen client-side
> from the Mac app, secrets/tokens in the **macOS Keychain**. Apple frameworks
> only: `ASWebAuthenticationSession` (OAuth), `URLSession` (upload), `Security`
> (Keychain). We already ship `tools/upload_covers.py` proving the archive.org
> IAS3 S3 path works.

This complements **Decision 033** (Clip Studio is iOS-only today) and
**Decision 010** (free, non-commercial). Publishing is a *macOS* surface; the
ethics section below scopes it tightly to the user's own account + own creation.

---

## 0. The two paths at a glance

| | YouTube | archive.org |
|---|---|---|
| Auth model | OAuth 2.0 (Google), per-user consent | User's own IAS3 access/secret keys |
| Where the user gets credentials | Signs in via system browser (one time) | `archive.org/account/s3.php` (paste once) |
| Secret-storage | refresh token + (client id/secret) in Keychain | IAS3 access+secret in Keychain |
| Upload protocol | Resumable upload (init → chunked PUT → resume) | S3-like `PUT` to `s3.us.archive.org` |
| Resumable? | Yes (308 + `Range`) | Per-file PUT; large files use multipart |
| Hard caveat | **Unverified app → uploads forced PRIVATE** + 6-day verification/audit | Identifier must be globally unique; derivation queued |
| Quota / cost | `videos.insert` = **1600 units**; default 10,000/day ≈ **6 uploads/day** | No per-call unit quota; rate-limited by S3 |

The **YouTube unverified-app restriction** is the single most important finding
for product scoping — see §1.5.

---

## 1. YouTube — Data API v3 `videos.insert`

### 1.1 OAuth 2.0 for an installed / desktop app (no backend)

YouTube uploads require a signed-in Google user; we use the **OAuth 2.0
"Installed Apps" flow** with the **loopback IP redirect + PKCE**. The loopback
redirect is **still supported for Desktop-app OAuth client types** (it is
deprecated only for Android / iOS / Chrome client types — a macOS desktop app is
explicitly unaffected).
([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps),
[Loopback migration](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration))

**One-time developer setup (us, not the user):**
- In Google Cloud Console, enable the **YouTube Data API v3** and create an
  **OAuth client ID of type "Desktop app"**. This yields a `client_id` and a
  `client_secret`. For installed/desktop clients the secret is **not treated as
  confidential** — "it is assumed that these apps cannot keep secrets"; PKCE is
  what actually secures the exchange, so shipping the desktop client id/secret in
  the app is the intended model.
  ([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps))
- Configure the OAuth **consent screen** and register the sensitive scope
  `https://www.googleapis.com/auth/youtube.upload`.

**Runtime flow (per user, native, no server):**

1. **Spin up a loopback listener.** Open a local `NWListener`/HTTP server on
   `127.0.0.1` (and/or `[::1]`) on a **random free port**; the registered
   redirect for a Desktop client is `http://127.0.0.1:PORT`. The app picks the
   port at runtime and listens for the redirect.
   ([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps))
2. **PKCE.** Generate a `code_verifier` (43–128 unreserved chars) and
   `code_challenge = BASE64URL(SHA256(verifier))`, `code_challenge_method=S256`.
3. **Authorize via the system browser.** Build the URL and present it through
   **`ASWebAuthenticationSession`** (system browser; on macOS it routes to the
   default browser / Safari). Endpoint:
   `https://accounts.google.com/o/oauth2/v2/auth` with:
   `client_id`, `redirect_uri=http://127.0.0.1:PORT`, `response_type=code`,
   `scope=https://www.googleapis.com/auth/youtube.upload`,
   `code_challenge`, `code_challenge_method=S256`, `state` (CSRF), and
   `access_type=offline` + `prompt=consent` to guarantee a refresh token.
   ([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps))

   > Note on the callback: `ASWebAuthenticationSession`'s `callbackURLScheme` is
   > built for a **custom scheme**, not an `http://127.0.0.1` loopback. Two
   > viable patterns on macOS: **(a)** register a **custom URI scheme**
   > (`com.googleusercontent.apps.<id>:/oauth2redirect`) as the redirect and pass
   > that scheme to `ASWebAuthenticationSession` (cleanest with the session API),
   > or **(b)** use the **loopback HTTP listener** and open the auth URL in the
   > browser, reading the code off the local server (no `callbackURLScheme`).
   > Prefer (a) for the native session round-trip; (b) is the RFC 8252 desktop
   > canonical and avoids any scheme registration. Either is server-free.
   > ([ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession),
   > [RFC 8252](https://datatracker.ietf.org/doc/html/rfc8252))
4. **Exchange the code for tokens.** `POST https://oauth2.googleapis.com/token`
   (form-encoded) with `client_id`, `client_secret`, `code`, `code_verifier`,
   `grant_type=authorization_code`, `redirect_uri`. Response JSON:
   `access_token`, `refresh_token`, `expires_in`, `scope` (verify the granted
   scope includes `youtube.upload`).
   ([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps))
5. **Refresh.** When `access_token` nears expiry,
   `POST https://oauth2.googleapis.com/token` with `grant_type=refresh_token`,
   `refresh_token`, `client_id`, `client_secret`. "Refresh tokens are always
   returned for installed applications," enabling silent re-auth.
   ([Installed Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps))

### 1.2 Resumable upload protocol

`videos.insert` uses Google's **resumable upload** (init session → chunked PUT →
resume on failure).
([Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol))

1. **Initiate the session.**
   `POST https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status`
   Headers: `Authorization: Bearer <access_token>`,
   `Content-Type: application/json; charset=UTF-8`,
   `X-Upload-Content-Length: <file bytes>`, `X-Upload-Content-Type: video/*`.
   Body: the video resource JSON (snippet + status, §1.3).
   Response `200 OK` with a `Location:` header = the **upload session URI** (save
   it). ([Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol))
2. **Upload the bytes (single shot or chunked).** `PUT` to the session URI with
   `Content-Length` + `Content-Type: video/*`. For chunked uploads add
   `Content-Range: bytes START-END/TOTAL`. **Each chunk except the last must be a
   multiple of 256 KB (262,144 bytes).** A single PUT of the whole file is also
   allowed and is simpler when the network is stable.
   ([Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol))
3. **Handle responses.**
   - `308 Resume Incomplete` → an intermediate chunk succeeded; read the `Range:
     bytes=0-N` header and resume the next PUT at byte `N+1`.
   - To **query status** after an interruption: empty `PUT` with
     `Content-Range: bytes */TOTAL` and `Content-Length: 0`; the `Range` header
     tells you how many bytes the server already has.
   - `201 Created` → done; body is the new video resource (id, etc.).
   - `500/502/503/504` → transient; resume with exponential backoff.
   - `404 Not Found` → session expired; restart from step 1.
   - Other `4xx`/`5xx` → permanent; start a new session.
   ([Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol))

This maps cleanly onto `URLSession` (a background `URLSession` for the PUT lets
the upload survive app backgrounding; track byte offset in the model for resume).

### 1.3 Setting title / description / tags / privacy / category

Request body parts are `snippet` and `status`
([videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert)):

```json
{
  "snippet": {
    "title": "My Edit — from a public-domain film",
    "description": "Created with Archive Watch. Source: https://archive.org/details/<id>",
    "tags": ["public domain", "archive.org", "fan edit"],
    "categoryId": "1"
  },
  "status": {
    "privacyStatus": "private",
    "selfDeclaredMadeForKids": false
  }
}
```

- `snippet.title`, `snippet.description`, `snippet.tags[]` — user-editable in the
  publish sheet.
- **`snippet.categoryId` is REQUIRED** (numeric; e.g. "1" = Film & Animation).
  Fetch the valid list per region via `videoCategories.list` (cheap) or ship a
  small static map.
- `status.privacyStatus` ∈ `private` | `public` | `unlisted`.
- `status.selfDeclaredMadeForKids` (COPPA) — surface a toggle; default false.
- `status.publishAt` (RFC 3339) schedules a public release (requires
  `privacyStatus: private`).
  ([videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert))

### 1.4 Quota cost of an upload

`videos.insert` costs **1600 units**. The default project allocation is **10,000
units/day** → roughly **6 uploads/day across ALL users of our client id
combined** (quota is per Google Cloud project, not per user).
([Quota Calculator](https://developers.google.com/youtube/v3/determine_quota_cost),
[Quota & Compliance Audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits))

A higher quota requires submitting the **YouTube API Services Audit and Quota
Extension Form**.
([Quota & Compliance Audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits))

### 1.5 ⚠️ The unverified-app caveat (product-shaping)

> **"All videos uploaded via the `videos.insert` endpoint from unverified API
> projects created after 28 July 2020 will be restricted to private viewing
> mode."**
> ([videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert))

Until the app passes Google's **OAuth verification + YouTube API compliance
audit**, every upload from our client id is **forced PRIVATE regardless of the
`privacyStatus` we request** — the user must then flip it to public/unlisted in
YouTube Studio. Also relevant:

- **Sensitive scope + unverified app:** the consent screen shows an
  "unverified app" warning, and (separate from the upload restriction) Google
  caps unverified sensitive-scope apps to **100 test users** added in the consent
  config until the app is verified.
  ([Quota & Compliance Audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits))

**Implication for Feature 7:** until we complete verification + the audit, either
(a) default the YouTube publish to **Unlisted/Private** and tell the user they'll
finish publishing in YouTube Studio, or (b) treat YouTube as a "private upload to
your channel" feature and lead with **archive.org** (no such restriction) as the
fully-public path. Document this in the publish sheet copy so it's never a
surprise.

### 1.6 Token storage + refresh (Keychain)

- Store `refresh_token` (+ the granted scope, the Google account email for
  display, and `client_secret` if not bundled) in the **Keychain** as a generic
  password item, service e.g. `org.archivewatch.youtube`, account = the Google
  account id. Use `kSecAttrAccessibleAfterFirstUnlock` (or
  `…ThisDeviceOnly` to keep it off iCloud Keychain). Do **not** persist the
  short-lived `access_token` (re-mint from the refresh token on demand).
- "Sign out" = delete the Keychain item (and optionally call Google's token
  revocation endpoint `https://oauth2.googleapis.com/revoke`).

---

## 2. archive.org — IAS3 S3-like upload to the user's OWN item

This is the **same protocol as `tools/upload_covers.py`**, scaled to a video file
and signed with the **user's own keys** instead of our CI keys.

### 2.1 Authentication — the user's own IAS3 keys

The user generates their own keys at **`https://archive.org/account/s3.php`**
("Your S3-like API keys") and pastes the **access key + secret key** into the
publish sheet **once**; we store them in the **Keychain**. Every request carries:

```
Authorization: LOW <access_key>:<secret_key>
```

HTTPS is required for this header form.
([IAS3](https://archive.org/developers/ias3.html))

> Contrast with `upload_covers.py`: that tool reads `IAS3_ACCESS_KEY` /
> `IAS3_SECRET_KEY` from the **environment** (CI secrets) and uploads to OUR
> `archivewatch-covers` item. Feature 7 reads the **user's** keys from the
> **Keychain** and uploads to the **user's own** new item — so the upload is
> attributed to *their* account, never ours.

### 2.2 Create the item + upload the file (one PUT)

Endpoint host: **`s3.us.archive.org`**. An item is an S3 "bucket"; files are
"keys". Create the item and upload in a single PUT by including
`x-amz-auto-make-bucket:1`:
([IAS3](https://archive.org/developers/ias3.html),
[Metadata schema](https://archive.org/developers/metadata-schema/))

```
PUT https://s3.us.archive.org/<identifier>/<filename.mp4>
Authorization: LOW <access>:<secret>
x-amz-auto-make-bucket: 1
x-archive-meta-mediatype: movies
x-archive-meta01-collection: opensource_movies
x-archive-meta-title: uri(<URL-encoded title>)
x-archive-meta-description: uri(<URL-encoded description, incl. source link>)
x-archive-meta-licenseurl: https://creativecommons.org/publicdomain/zero/1.0/
x-archive-meta-creator: <user-chosen creator>
Content-Type: video/mp4
Content-Length: <bytes>
<binary body>
```

- **Identifier**: must be **globally unique** across all of archive.org,
  5–80 chars (max 100), alphanumeric/underscore/dash/period. Generate a
  slug from the title + a short random suffix; on `409`/conflict, re-roll.
  ([Metadata schema](https://archive.org/developers/metadata-schema/))
- **`mediatype: movies`** — all video (features/shorts/etc.) uses `movies`; the
  item then renders with the online video player.
  ([Metadata schema](https://archive.org/developers/metadata-schema/))
- **Collection**: a new user's uploads normally land in the generic
  community/open collections (e.g. `opensource_movies`); you cannot self-assign
  into a curated collection. Let the platform default unless the user has rights.
- **Metadata headers**: `x-archive-meta-<name>:<value>`; multiple values of one
  field are numbered (`meta01`, `meta02`, …); `--` in a name becomes `_`; UTF-8
  values should be wrapped as `uri(<percent-encoded>)`.
  ([IAS3](https://archive.org/developers/ias3.html))
- **`licenseurl`**: set the Creative Commons / public-domain URL the user picks
  (e.g. CC0 `…/publicdomain/zero/1.0/`, CC-BY `…/licenses/by/4.0/`).
  ([IAS3](https://archive.org/developers/ias3.html))

### 2.3 Derivation, large files, and progress

- **Derivation**: by default the Archive **queues derivatives** (web-friendly
  formats, thumbnails) after upload — this is what makes the item playable. For a
  finished video we WANT derivation, so do **not** send `x-archive-queue-derive:0`
  (which `upload_covers.py` sends precisely because cover JPEGs need no derive).
  Track progress at `archive.org/history/<identifier>`.
  ([IAS3](https://archive.org/developers/ias3.html))
- **Large files**: a video can be hundreds of MB+. IAS3 supports **S3 multipart
  upload** for large files (split into parts, PUT each, then complete). Note the
  Archive-specific rule: `x-archive-keep-old-version` must be set **at the time
  the multipart upload is completed**, not per part. For Creation Studio's typical
  short clips a single PUT is fine; wire multipart only if files routinely exceed
  the single-request comfort zone.
  ([IAS3](https://archive.org/developers/ias3.html))
- **`x-archive-size-hint:<bytes>`** lets the Archive pre-allocate for big items.
  ([IAS3](https://archive.org/developers/ias3.html))
- **Rate limits**: query `?check_limit=1&accesskey=<key>&bucket=<id>`; on `503`
  back off (exactly the retry pattern already in `upload_covers.py`).
  ([IAS3](https://archive.org/developers/ias3.html))
- **Resumability**: a plain PUT is not resumable; on failure either retry the
  whole file (small clips) or use multipart (re-PUT only the failed part).
  `URLSession` background uploads survive app suspension.

### 2.4 Public URL

After derivation the file is at
`https://archive.org/download/<identifier>/<filename>` and the item page at
`https://archive.org/details/<identifier>` — show both in the success state.
([IAS3](https://archive.org/developers/ias3.html))

---

## 3. UX + safety

### 3.1 Publish sheet (native SwiftUI)

A single `.sheet` launched from a "Publish" action on the export-complete screen:

1. **Destination** — segmented control: `YouTube` | `archive.org`.
2. **Account / credentials**
   - YouTube: a "Connect YouTube" row → `ASWebAuthenticationSession`. Once
     connected, show the account email + a "Sign out" affordance. (Reuse the
     `per-ecosystem-sync-islands` Sign-in-with-Google plumbing if it already
     exists — the youtube.upload scope is additive.)
   - archive.org: two `SecureField`s for access/secret keys with a "Get your keys"
     link to `archive.org/account/s3.php`; store on first use, then show
     "Connected as <screenname>" (fetched from the metadata API).
3. **Metadata** — `title`, `description` (pre-filled with the baked-in source
   attribution, see §3.3), `tags`/keywords. archive.org adds a **license picker**
   (CC0 / CC-BY / Public Domain); YouTube adds a **privacy picker** (Private /
   Unlisted / Public) and a "Made for Kids" toggle, plus a **category** picker.
4. **Caveat banner (YouTube only)** — surface §1.5: "Until Archive Watch is
   verified by Google, uploads arrive **Private**; finish publishing in YouTube
   Studio." Use a `universal-feature-states` hint banner.
5. **Publish button** → progress.

### 3.2 Progress, resumability, errors

- A determinate `ProgressView` driven by `URLSession` upload progress
  (`urlSession(_:task:didSendBodyData:…)`).
- YouTube: persist the **session URI + byte offset** so a dropped connection
  resumes (308/`Range`); a background `URLSession` keeps it alive across app
  suspension.
- Cover the four states (`universal-feature-states`): **uploading** (progress),
  **success** (links to the live item/video), **error** (actionable — auth
  expired → re-connect; 503 → "retrying"; identifier conflict → auto re-slug;
  quota exceeded → explain the daily cap from §1.4), **offline** (queue/disable).

### 3.3 Ethics — the load-bearing constraints

This feature must pass the `learning-orientation-design` test the same way
Clip Studio did (Decision 033): it **invites participation** (the user shares
their own editorial work) and **supports agency** — but only under hard guardrails:

- **Only the user's own account.** YouTube via the user's own OAuth consent;
  archive.org via the user's own IAS3 keys. We never hold a shared "Archive
  Watch" publishing account, and nothing uploads to *our* org account.
- **Only the user's own creation.** Publishing is offered only for a file the
  user actually produced in Creation Studio (an exported clip), and only when the
  source is clippable per **Decision 033 / 027** (PD / CC). No re-uploading raw
  catalog films.
- **Attribution is baked in, not optional.** Every publish pre-fills the
  description with the source credit (`Source: archive.org/details/<id>` +
  `Created with Archive Watch · archivewatch.org`), mirroring the always-on
  provenance credit burned into the export (Decision 033). The user can add to
  it but the source link is the default. This turns the Internet Archive's
  attribution norm into the feature's spine.
- **No auto-publish.** Same rule as "no one-tap auto fan-edit" — the user reviews
  destination, metadata, license/privacy, and presses Publish. Nothing is posted
  silently.
- **Secrets never leave the device unencrypted.** OAuth refresh tokens and IAS3
  keys live only in the **Keychain** (`…AfterFirstUnlockThisDeviceOnly`), never in
  `UserDefaults`, a file, or git. Sign-out deletes them (and revokes the Google
  token).
- **Honest licensing.** The license picker defaults to the source's own status
  (PD/CC0); we never let the user claim a more restrictive license on
  public-domain-derived work than is truthful.

---

## 4. Native-first / framework mapping

| Concern | Framework / API |
|---|---|
| Google OAuth (browser round-trip) | `ASWebAuthenticationSession` (AuthenticationServices) |
| PKCE (SHA256, base64url) | `CryptoKit` (`SHA256`), `Data.base64EncodedString` + url-safe transform |
| Loopback listener (if using RFC 8252 desktop path) | `Network` (`NWListener` on `127.0.0.1`) |
| Token exchange / refresh, IAS3 PUT, resumable PUT | `URLSession` (background config for large uploads) |
| Secret storage | `Security` (Keychain: `SecItemAdd`/`SecItemCopyMatching`, `kSecClassGenericPassword`) |
| Publish UI, progress, states | SwiftUI `.sheet`, `ProgressView`, `SecureField`, `Picker` |

No third-party SDK is needed (consistent with the no-third-party-packages rule);
the Google API client library is optional — the raw OAuth + resumable HTTP is
small and avoids a dependency.

---

## 5. Open questions / follow-ups

- **YouTube verification**: decide whether to pursue Google OAuth verification +
  the YouTube compliance audit (removes the forced-private restriction and the
  100-test-user cap), or ship YouTube as an explicitly "uploads as Private/
  Unlisted" feature and lead with archive.org for public sharing. (§1.5)
- **archive.org collection**: confirm which default collection a fresh user upload
  lands in and whether to expose any collection choice at all.
- **Multipart threshold**: pick a file-size cutoff above which we switch the
  archive.org path from single-PUT to S3 multipart.
- **Reuse**: if Sign-in-with-Google already exists for Drive App Data sync
  (`per-ecosystem-sync-islands`), reuse that OAuth client and just add the
  `youtube.upload` scope incrementally.

---

## Sources

- [YouTube Data API — Resumable Uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol)
- [YouTube Data API — videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert)
- [YouTube Data API — OAuth 2.0 for Mobile & Desktop (Installed) Apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps)
- [Google Identity — Loopback IP Address flow Migration Guide](https://developers.google.com/identity/protocols/oauth2/resources/loopback-migration)
- [YouTube Data API — Quota Calculator](https://developers.google.com/youtube/v3/determine_quota_cost)
- [YouTube Data API — Quota and Compliance Audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits)
- [RFC 8252 — OAuth 2.0 for Native Apps](https://datatracker.ietf.org/doc/html/rfc8252)
- [Internet Archive — IAS3 S3-like API](https://archive.org/developers/ias3.html)
- [Internet Archive — Metadata schema](https://archive.org/developers/metadata-schema/)
- [Apple — ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Apple — Authenticating a User Through a Web Service](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service)
- Internal precedent: `tools/upload_covers.py` (IAS3 PUT with `LOW` auth, derive-skip, 503 backoff)
