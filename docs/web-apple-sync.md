# Sign in with Apple on the web — one owner step remains

The owner asked (2026-09-03): *"I would love to be able to login with my apple
login on the web app and have content sync across to that platform."*

`js/cloudkitsync.js` does it. It signs the viewer in with Apple through
**Apple's own CloudKit JS** and reads and writes the **same records the
tvOS / iOS / macOS apps already sync through** — container
`iCloud.app.archivewatch.tvos`, record type `AWSync`, the five fixed-ID blobs
of Decision 022 (`tombstones`, `favorites`, `playlists`, `progress`,
`channels`). There is no server of ours in the path and no Apple secret in the
page: Apple's script owns the Apple ID sheet and 2FA, and hands the page an
authenticated client for the user's own private database.

Merge rules are Decision 078's, reused verbatim from `js/drivesync.js`
(`AWDriveSync.merge`), so a browser signed into both clouds is the one place
the Apple and Google islands meet — favorites, playlists, channels and watch
history converge, and deletions carry tombstones both ways.

## The owner step: a CloudKit JS API token

The code is dormant until `window.AW_CLOUDKIT_API_TOKEN` in `index.html` holds
a token. Like the Google client ID, that token is public by design — it names
the container and permits web sign-in; it grants nothing on its own.

1. Go to **https://icloud.developer.apple.com/dashboard/** and sign in with the
   Apple Developer account (team **L2G756LY8N**).
2. Pick the container **`iCloud.app.archivewatch.tvos`**.
3. **Settings → Tokens → API Tokens → Create API Token** (some versions of the
   dashboard put this under the container's "API Access").
   - Name it `Archive Watch Web`.
   - **Sign in with Apple: allow.** This is the setting that matters; without
     it the button appears and sign-in fails.
   - Set the token's allowed origins / redirect URLs to `https://archivewatch.org`
     (add `http://localhost:8080` too if you want local testing to work).
4. Copy the token and paste it into `index.html` where
   `window.AW_CLOUDKIT_API_TOKEN = ''`, then push.

The environment is **production** — that is deliberate, and matches the
schema the shipped apps use. The CloudKit schema was deployed to Production
long ago (the 2026-06-11 sync fix); this adds no record types and no indexes,
so nothing needs deploying for the web to join.

## Once the token is in

A "Sign in with Apple to sync with your Apple TV, iPhone and Mac" control
appears on the Library page, beside the Google one. Verify by favoriting a
film on the Apple TV or iPhone and reloading the Library page in a browser
signed into the same Apple ID — the same check that proved the Google island
(a favorite set on the Pixel 8a reached the browser through Drive, and
un-favoriting it removed it rather than resurrecting it).

## Why two buttons and not one

Decision 028's sync-islands rule: Apple state lives in the user's iCloud,
Google state in the user's Drive, and there is no neutral backend to run. The
web is the only client that can reach both, so it offers both and merges
whatever it can see. A viewer who uses only one ecosystem sees one button do
everything they need.
