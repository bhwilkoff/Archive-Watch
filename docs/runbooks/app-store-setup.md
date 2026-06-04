# App Store setup & submission runbook

Status: started 2026-06-04. The **code/capability side is done** (bundle IDs
renamed, entitlements wired, verified on-sim). The remaining steps are in
Apple's web portals + Xcode and must be done by the account owner.

## Canonical identifiers (already in the project)

| Thing | Identifier |
|---|---|
| App bundle ID | `app.archivewatch.tvos` |
| Top Shelf extension bundle ID | `app.archivewatch.tvos.topshelf` |
| App Group | `group.app.archivewatch.tvos` |
| iCloud / CloudKit container | `iCloud.app.archivewatch.tvos` |
| Team ID | `L2G756LY8N` |
| Version / build | `1.0` / `1` (from `AppVersion.xcconfig`) |
| Min OS | tvOS 26.0 |

Entitlements already in `ArchiveWatch.entitlements`: App Groups, Sign in with
Apple, iCloud (CloudKit). Top Shelf entitlements: App Groups only.

---

## Phase 1 — Developer portal: register identifiers + capabilities

Easiest path is to let **Xcode automatic signing** do it:

1. Open `ArchiveWatch/ArchiveWatch.xcodeproj` in Xcode.
2. Select the **ArchiveWatch** target → **Signing & Capabilities**.
   - "Automatically manage signing" ON, Team = your team (`L2G756LY8N`).
   - You should see capabilities already listed (from the entitlements file):
     **App Groups**, **Sign in with Apple**, **iCloud → CloudKit**.
   - For **App Groups**: confirm `group.app.archivewatch.tvos` is checked (the +
     creates it in the portal if missing).
   - For **iCloud**: confirm **CloudKit** is checked and the container
     `iCloud.app.archivewatch.tvos` exists (use the + to create it).
3. Repeat for the **ArchiveWatchTopShelf** target → only **App Groups**
   (`group.app.archivewatch.tvos`, the same group).
4. Build for "Any tvOS Device" once — Xcode registers both App IDs + the group +
   the container and provisions them. Resolve any signing prompts.

(Manual alternative: developer.apple.com → Certificates, Identifiers & Profiles →
register both App IDs with those capabilities, create the App Group + iCloud
Container identifiers, assign them. The Xcode path above does this for you.)

---

## Phase 2 — App Store Connect: create the app record

appstoreconnect.apple.com → **My Apps → + → New App**:

- Platform: **tvOS**
- Name: **Archive Watch** (must be globally unique on the App Store)
- Primary language, Bundle ID: **`app.archivewatch.tvos`** (only appears after
  Phase 1 registers it), SKU: e.g. `archivewatch-tvos`
- User access: Full

Then fill the listing (App Information / Pricing / Version):
- **Category**: Entertainment (primary)
- **Price**: Free (Decision 010)
- **Description, subtitle, keywords, promotional text**
- **Support URL** + **Privacy Policy URL** (required) — host on your GitHub Pages
  site (privacy is near-trivial: no data leaves device except API calls to public
  services; with sign-in, data lives in the user's own iCloud).
- **App Privacy** questionnaire: the app ships a `PrivacyInfo.xcprivacy` already.
  With Sign in with Apple + CloudKit you must disclose the identifier/user-content
  stored in the user's private iCloud DB.
- **Age rating** questionnaire.
- **Screenshots**: Apple TV 4K — 3840×2160 or 1920×1080 (capture from a real
  Apple TV or the simulator).
- **App icon**: the 1280×768 App Store icon ships in the asset catalog
  (`App Icon & Top Shelf Image.brandassets`).

---

## Phase 3 — Build, upload, submit

1. `AppVersion.xcconfig` controls version/build — bump there, never in Xcode's UI
   (Decision 003).
2. Xcode → **Product → Archive** (destination "Any tvOS Device").
3. Organizer → **Distribute App → App Store Connect → Upload**.
4. Wait for processing in ASC, then attach the build to the version and **Submit
   for Review**.

---

## ⚠️ Blockers / must-do before review passes

- **Account deletion (App Review Guideline 5.1.1(v))** — because we now offer
  **Sign in with Apple**, the app MUST provide an in-app way to **delete the
  account + its data**, not just sign out. Today Settings has Sign Out only. This
  has to ship before submitting with accounts enabled. (Ties into the accounts
  re-design — or disable Sign in with Apple for the very first submission.)
- **`CloudSync.entitlementConfigured` is still `false`.** Flip it to `true` only
  AFTER the iCloud container exists (Phase 1) and you've verified sync on a real
  Apple TV signed into iCloud (#84). It traps on the simulator. Note: SwiftData's
  automatic CloudKit mirror is intentionally OFF (`cloudKitDatabase: .none`) — we
  sync manually; do not re-enable auto-mirror (our models use unique constraints).
- **tvOS 26 SDK** — you can only submit built against a **released** SDK. Confirm
  the Xcode you archive with is a GA release supporting tvOS 26.
- **`.xcodeproj` location** — it lives at `ArchiveWatch/ArchiveWatch.xcodeproj`
  (two levels deep), not the repo root. Fine for manual Archive/Upload; revisit
  before wiring **Xcode Cloud** (Decision 002 wants it at root).
- **App Group on device** — enabling it (Phase 1) lights up the Top Shelf +
  cross-process SwiftData store on real hardware.
