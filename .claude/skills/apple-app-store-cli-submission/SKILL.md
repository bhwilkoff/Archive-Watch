---
name: apple-app-store-cli-submission
description: Build + upload Archive Watch's macOS/iOS/tvOS App Store builds from the command line (no Xcode GUI) — the manual-REST-signing pathway, the ITMS-90111 Xcode-floor trap, the PyJWT venv, per-platform SDK downloads, the tuple-sort type-check gotcha, and screenshots. Invoke before archiving, signing, submitting, or resubmitting any Apple build, or when App Review rejects a build for SDK/Xcode/signing reasons.
---

# Apple App Store submission (CLI) — Archive Watch

Runbook: `docs/mac-app-store-submission.md`. Live state + cert ids:
`mac_app_store_build_pathway` memory. All three Apple apps share ONE App Store
Connect record (bundle id `app.archivewatch.tvos`, Decision 042). Android is a
separate path (`tools/submit-play.sh`, Play Developer API).

## The one command

```
DEVELOPER_DIR=<released-Xcode>/Contents/Developer tools/submit-appstore.sh <mac|ios|tvos|all>
```
It archives → resolves embedded bundle ids → ensures certs → creates an App Store
profile per bundle id → writes a manual ExportOptions → exports + uploads via the
ASC API key. Re-running is safe. Then the OWNER selects the build in ASC and hits
Submit for Review (the script only uploads).

## Load-bearing rules (each cost real time to learn)

1. **Manual signing is REQUIRED — cloud/automatic signing FAILS for this team key**
   ("Cloud signing permission error" / "No profiles for app.archivewatch.tvos"),
   even though the key CAN create certs/profiles via REST. The script signs
   manually: `asc_certs.py` (Apple Distribution + Mac Installer certs) +
   `asc_profiles.py` (a profile per bundle id). Don't "simplify" it to automatic.

2. **ITMS-90111 = Apple raised the Xcode/SDK FLOOR (recurring).** A build made with
   an Xcode older than Apple's current floor is REJECTED *after upload*. Diagnose:
   `WebFetch https://developer.apple.com/news/releases` for the latest **released or
   RC** Xcode, compare to `xcodebuild -version`. A build number ending in a lowercase
   letter (e.g. `27A5194q`) is a **beta — App Review rejects betas**; use the latest
   GA/RC. Fix = owner installs it (`xcodes install <ver>`, Apple ID + 2FA, not
   headless-automatable), then rebuild **all three** Apple platforms at a fresh,
   monotonic build number. This WILL recur every few weeks; Xcode Cloud avoids it.

3. **PyJWT dependency self-heals.** `asc_certs.py`/`asc_profiles.py` sign the ASC JWT
   with `import jwt` (PyJWT) + cryptography. Homebrew python3 is PEP-668 and lacks
   them; the script now auto-provisions `tools/.asc-venv` and runs the cert tools
   from it. If you bypass the script, put a jwt-capable python on PATH first.

4. **Per-platform device SDKs + Metal are separate Xcode component downloads.** A
   fresh Xcode needs `-downloadComponent MetalToolchain` (~700 MB; the app has a
   `.metal` shader — the script auto-installs it) and may need
   `xcodebuild -downloadPlatform iOS`/`tvOS` if the "Any iOS/tvOS Device"
   destination shows "not installed". (Xcode `.xip` GA installs usually bundle them.)

5. **Released Xcode only — never beta for review.** The code carries
   `#if compiler(>=6.4)` guards so macOS/iOS/tvOS-27 symbols compile on BOTH the
   GA toolchain (uses the `#else` 26 API) and the beta. Any NEW 27-only symbol must
   be `#if compiler(>=6.4)`-guarded, NOT just `#available` (a runtime check still
   needs the symbol in the BUILD SDK → fails to COMPILE on GA). Audit:
   `grep -rn 'available((macOS|iOS|tvOS) 27'`.

6. **tvOS tuple-sort type-check timeout.** `.sorted { (a,b,c) > (a,b,c) }` tuple
   comparisons "unable to type-check in reasonable time" on the GA toolchain (build
   fine on beta's newer Swift). Compare field-by-field. tvOS-only files surface this
   (iOS/macOS don't compile them). Fix wherever a new type-check timeout appears.

## Credentials & secrets (configured)

- ASC API key (TEAM key): ID `G5549XF8RV`, issuer `69a6de74-3929-47e3-e053-5b8c7c11a4d1`,
  `.p8` at `~/.appstoreconnect/private_keys/` (OUTSIDE the repo). IDs in gitignored
  `tools/asc-credentials.env` (sourced by the script). Individual keys 401.
- Existing cert ids: Apple Distribution `7VDL7K5H79`, 3rd Party Mac Installer
  `T445JWG853` (reused find-first; created+imported only if absent).
- Bundle ids embedded: iOS = main + `.widgets`; tvOS = main + `.topshelf`; macOS =
  main only. `.ipa` exports take no installer cert; the macOS `.pkg` does.
- **Bump BOTH `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in AppVersion.xcconfig
  every build** — App Review burns a build number even on rejection; the next must be
  ahead. Build numbers can differ per platform but we keep them aligned.

## Disk (the box runs ~97% full)

A fresh Xcode needs ~25-30 GB. Free it: delete the obsolete Xcode app, clear
`~/Library/Developer/Xcode/DerivedData/*`, `build/*.xcarchive build/*-export`
between platforms. Don't delete an Xcode app without owner OK (hard to reverse).

## Screenshots

macOS: 16:10, EXACTLY 1280×800 / 1440×900 / 2560×1600 / **2880×1800**. Drive the
app via `AW_START_TAB` / `AW_START_ITEM` / `AW_CS_TEST` launch hooks; capture by
REGION from the AX window bounds (SwiftUI exposes no AXWindowNumber) then PIL-frame
to exact size — `tools/mac-shotset.sh <app>` runs the whole set. Needs Screen
Recording permission. Any build may produce screenshots (not the submitted binary).
```
DEVELOPER_DIR=<released-Xcode>/Contents/Developer \
  tools/mac-shotset.sh "<DerivedData>/Release/Archive Watch.app"
```
