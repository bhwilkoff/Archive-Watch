# Google OAuth for cross-device sync — DONE 2026-09-03

Decision 028 routes Android + web sync through the user's own Google Drive
(App Data folder) — no backend, the exact analog of CloudKit on the Apple
side. This page records what exists, where it lives, and what to do when
something about it changes. The one-time setup was performed 2026-09-03 in
the Google Cloud project **`archivewatch-play`** (owner account
benwilkoff@gmail.com — the same project that holds the Play publishing
service account).

## What exists

| Thing | Value / place |
|---|---|
| Google Auth Platform branding | App name "Archive Watch", support + contact benwilkoff@gmail.com, home https://archivewatch.org, privacy https://archivewatch.org/privacy.html, authorized domain `archivewatch.org` |
| Audience | **External, In production** (`drive.appdata` is a non-sensitive scope, so no verification and no 100-user cap) |
| Data Access | `https://www.googleapis.com/auth/drive.appdata` — the ONLY scope requested |
| Web client | "Archive Watch Web" — origins `https://archivewatch.org` and `http://localhost:8080`. Client ID `294492189901-jadidkmiv08nqndjt1uod34tliobi7l2.apps.googleusercontent.com` (public by nature; it is in `index.html` as `window.AW_GOOGLE_CLIENT_ID`). Its client secret is NOT used anywhere and was not recorded. |
| Android client (Play signing key) | package `com.archivewatch.app`, SHA-1 `CB:4B:ED:31:3B:06:79:44:03:4E:03:B0:88:BB:1B:40:22:C5:8E:97` — what production installs are signed with |
| Android client (upload key) | package `com.archivewatch.app`, SHA-1 `8B:3E:FF:3E:05:8B:60:54:84:19:E0:0F:F4:7A:85:42:83:54:63:AD` — local `assembleGoogleRelease` builds |
| Android client (debug) | package `com.archivewatch.app.debug`, SHA-1 `B2:0D:E1:7E:31:C1:6D:33:E0:30:8B:2F:9D:97:A8:C3:D2:C5:A7:43` — the dev Mac's `~/.android/debug.keystore` |
| Android activation | `awGoogleServerClientId=<web client id>` in `~/.gradle/gradle.properties` → `BuildConfig.AW_GOOGLE_SERVER_CLIENT_ID`. `tools/submit-play.sh` builds locally, so the Play release carries it. Empty = the Sync section is hidden. |

Package names matter: the OAuth Android client is keyed on the INSTALLED
package (`applicationId`, `com.archivewatch.app`), not the Kotlin namespace
`app.archivewatch.android`. The debug build has its own suffix and its own
client.

## How it works

- Android (google flavor only — Fire OS has no Play services, Decision 047):
  `sync/DriveSync.kt`. Google's `AuthorizationClient` hands back an access
  token silently once the account has consented, and a consent
  `PendingIntent` the first time; Settings launches it through an
  ActivityResult seam. Works on phones and on Google TV the same way.
- Web: `js/drivesync.js` (Google Identity Services token client).
- One file `awsync.json` in the appDataFolder, blob v2: favorites, playlists,
  channels, progress/history, tombstones. Both merges are field-for-field the
  same; deletions carry tombstones (90-day TTL).
- Sign-in is optional and gates ONLY sync. Status is visible in Settings
  (account, last sync, last error, Sync now).

## When something changes

- **A new signing certificate** (a new dev Mac, a Play key upgrade): add
  another Android client with the new SHA-1 under Google Auth Platform →
  Clients. Without it, sign-in on that build fails with `DEVELOPER_ERROR` /
  status 10 and the app shows "Google sign-in unavailable".
- **A new web origin**: add it to the web client's authorized JavaScript
  origins (propagation takes minutes to hours).
- **A new scope**: register it under Data Access first; a sensitive one
  would put the app back into verification.
