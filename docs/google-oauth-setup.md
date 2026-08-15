# Google OAuth client setup — the ONE owner step for cross-ecosystem sync

Decision 028 routes Android + web sync through the user's own Google Drive
(App Data folder) — no backend, the exact analog of CloudKit on the Apple
side. Everything is built and waiting (web: `js/drivesync.js`, activation
constant in `index.html`); it needs OAuth client IDs that only the project
owner can create. ~15 minutes, free, no billing account needed.

## 1. Create the project + consent screen (once)

1. https://console.cloud.google.com → New Project → name `Archive Watch`.
2. APIs & Services → **Library** → search "Google Drive API" → Enable.
3. APIs & Services → **OAuth consent screen**:
   - User type: **External** → Create.
   - App name `Archive Watch`, support email = your email.
   - Scopes: Add → filter `drive.appdata` → check
     `https://www.googleapis.com/auth/drive.appdata` → Update.
   - Test users: add your own Google account (while the app is in Testing,
     only listed users can sign in — fine for now; Publish later for
     everyone, `drive.appdata` is a non-sensitive scope with no review).

## 2. Web client ID (activates the PWA at archivewatch.org)

1. APIs & Services → **Credentials** → Create Credentials → OAuth client ID.
2. Application type: **Web application**, name `Archive Watch Web`.
3. Authorized JavaScript origins:
   - `https://archivewatch.org`
   - `http://localhost:8080` (local dev)
4. Create → copy the client ID (`…apps.googleusercontent.com`).
5. Paste it into `index.html` where `window.AW_GOOGLE_CLIENT_ID = ''` and
   push. A "Sign in with Google to sync across devices" button then
   appears at the top of the Library page.

## 3. Android client ID (activates the Android app)

OAuth for Android validates by package + signing certificate — no secret.

1. Credentials → Create Credentials → OAuth client ID → **Android**.
2. Package name: `app.archivewatch.android`.
3. SHA-1: one client per certificate, so create THREE Android clients:
   - the upload key: `keytool -list -v -keystore
     ~/keystores/archivewatch-upload.jks -alias upload | grep SHA1`
   - the debug key: `keytool -list -v -keystore ~/.android/debug.keystore
     -alias androiddebugkey -storepass android | grep SHA1`
   - the **Play App Signing** key: Play Console → your app → Setup →
     App signing → App signing key certificate → SHA-1. (This is the one
     production installs use — without it, sync fails only in production,
     the classic trap.)
4. Android sign-in also needs a client to EXCHANGE for tokens: reuse the
   Web client ID from step 2 as the `serverClientId` — tell Claude both
   IDs and the Android wiring lands in the google flavor (Fire stays
   GMS-free per Decision 047).

## 4. Hand back to Claude

Reply with: the Web client ID (+ confirmation it's pasted in index.html,
or just paste the ID and Claude will wire it). Android IDs need no code —
only the Web/serverClientId does. Claude then finishes the Android
Sign-In + Drive plumbing and verifies a browser and a phone converge on
one watch record.
