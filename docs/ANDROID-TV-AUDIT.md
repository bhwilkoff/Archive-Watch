# Android TV / Google TV — Full Screen, Button & Interface-Element Audit — 2026-09

Owner directive: *"I don't believe we have done a full audit of every screen,
button, and interface element. Please write up a full audit for Android TV and
test each component to be sure that it works as intended."*

This is the audit's **living ledger**, patterned on `docs/TVOS-AUDIT.md` (the
44/44 on-device pass) and continuing `docs/ANDROID-TV-PARITY.md` (which
measured PARITY — this one measures every ELEMENT, one row per control).

## Method

Two real devices, no emulator (owner's standing rule):

| Device | Flavor | Package | adb |
|---|---|---|---|
| Google TV Streamer (SEI Dongle_R_4K, Android 14) | `google` | `com.archivewatch.app.debug` | `10.0.0.55:5555` |
| Fire TV Stick 4K (AFTKRT, Fire OS) | `amazon` (zero GMS) | same | `10.0.0.139:5555` |

    ./gradlew :app:assembleGoogleDebug      # or :app:assembleAmazonDebug
    adb -s 10.0.0.55:5555 install -r android/app/build/outputs/apk/google/debug/app-google-debug.apk
    python3 tools/gtv_scenario.py launch --es aw_start_tab browse
    python3 tools/gtv_scenario.py go "Play" ; python3 tools/gtv_scenario.py select "Play"
    AW_TV_HOST=10.0.0.139 python3 tools/gtv_scenario.py rail_walk    # Fire TV

Evidence channels, all EXTERNAL to the app:

- **focus tree** (`uiautomator dump`) + **AWFOCUS logcat trace**
  (`--ez aw_focus_log true`) — the only proof a control is REACHABLE. A
  screenshot proves rendering and nothing else.
- **screenshots + OCR** (`/tmp/awocr`) — the only channel for Compose
  overlays, which are ABSENT from the uiautomator tree.
- **logcat** (`AWTV`, `AWHOME`, decoder frames, `dumpsys audio`).

Tiers, as in TVOS-AUDIT: **T1 device** (observed on the glass) · **T2 code**
(wiring read end-to-end) · **T3 owner** (feel/visual). A row that could not be
exercised is **SKIP with the reason** — never PASS.

Instrument facts already paid for (do not re-derive):

- `input tap` is INERT on the TV profile; the D-pad is the only channel.
- Focus enters the rail at the VERTICALLY NEAREST row, so blind key counts
  mislabel screens. Navigate by the tree.
- BACK from a tab ROOT exits the app (§1.7) — only press it after a pushed route.
- This SoC never composites the video plane into `screencap`: a black player
  frame is NOT "no video". Use decoder frame progression, the transport clock,
  `dumpsys audio state:started`, and the `AWTV` dispose log.
- Media3's PlayerView controller NEVER shows on TV; no MediaSession is
  registered on TV, by design.

Build under test: **1.42.2 / versionCode 52**, HEAD `31d4b6fad`, installed to
both devices at the start of this audit.

