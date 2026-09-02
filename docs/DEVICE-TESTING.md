# Testing on real devices

How this project verifies work on the owner's actual hardware, and the rules
that came from getting it wrong. Companion to `docs/IPHONE-12-AUDIT.md`,
`docs/IPAD-DESIGN.md` and `docs/TVOS-AUDIT.md`.

**The standing directive: the owner is never the tester.** A change ships when
a harness observed it on the glass — not when it compiled, and not when the app
reported its own success.

---

## 1. The fleet

| Lease name | Device | UDID prefix | Notes |
|---|---|---|---|
| `atv` | Ben Bedroom — Apple TV 4K (3rd gen) | `C3FBA9DE` | Paired. The owner *watches* on a second, unpaired unit (Fireplace) — settings differ per device |
| `ipad` | iPad Pro 12.9 (5th gen) | `AC5377E9` | Signed in as benwilkoff@gmail.com |
| `iphone` | iPhone 12 | `B4E756E2` | Signed in as arlowilkoff@icloud.com — a **different Apple ID**, which is what makes it a real SharePlay peer |
| — | iPhone 15 Pro | `988DE0A7` | Paired, available |

Two Apple IDs across the fleet is a feature, not an accident: SharePlay,
CloudKit sync and Sign in with Apple all behave differently between "two
devices, one account" and "two accounts".

## 2. Device leases — sharing hardware with another session

Several Claude Code sessions run against this Mac at once (Archive Watch and
Tidbits Trivia). They contend for the same physical devices, and the failure
mode is silent: a second session installs over your build, or launches an app
while you are mid-screenshot, and you diagnose a bug that does not exist.

`tools/devlease.py` is a cooperative lease protocol, adopted verbatim from the
Tidbits Trivia session so both sides speak it identically:

```python
import devlease
with devlease.lease("atv", task="what you are doing", ttl=1500, wait=900):
    ...   # the device is yours for the whole block
```

State lives in `~/.device-lease/<device>.json`, is pid-scoped, and expires.
**Never steal a lease.** If it is held, wait or work on something else.

### The lease lesson, learned the hard way

Hold the lease for **the whole run, in a single process** — install, launch,
screenshot, assert. Taking a lease per invocation leaves gaps between calls,
and the other session grabbed the Apple TV in exactly one of those gaps.

## 3. devicectl recipes

Requires `DEVELOPER_DIR` exported into the subprocess — it is not inherited
from a plain `os.environ` copy if the parent shell never set it.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer

xcrun devicectl list devices
xcrun devicectl device install app --device <UDID> /path/ArchiveWatch.app
xcrun devicectl device info apps --device <UDID>          # VERIFY the version
xcrun devicectl device process launch --device <UDID> --terminate-existing <bundle>
xcrun devicectl device process launch --device <UDID> --console <bundle>   # readable log
xcrun devicectl device capture screenshot --device <UDID> out.png          # 3840x2160 on ATV
xcrun devicectl device openURL --device <UDID> --url 'archivewatch://item/x'
```

Gotchas, each of which cost a debugging cycle:

- **Environment variables are JSON**, not `-e KEY=VALUE`. The flag form fails
  with `NSCocoaErrorDomain 3840`.
- **The iOS bundle id is `app.archivewatch.tvos`** on every Apple platform —
  they share one App Store record (Decision 042). Guessing `.ios` yields a
  silent "app not found" that looks like a failed install.
- **Installs work while the Apple TV sleeps; launches do not** ("System is
  asleep"), and there is no wake verb. `atv_scenario.wake_tv()` handles it.
- **There is no touch injection.** Interaction is deep links, launch
  environment hooks (`AW_START_TAB`, `AW_START_ITEM`), and on-device audit
  modes (`AW_UI_AUDIT=1`) — not synthesized taps.

## 4. Verify the artifact, never the build

**`| tail` on an `xcodebuild` invocation once hid a `BUILD FAILED`** and nearly
had a fix reported as verified. Two rules:

```bash
xcodebuild ... 2>&1 | grep -E "^e: |error: |BUILD SUCCEEDED|BUILD FAILED"
```

and, after installing, read the version back off the device with
`devicectl device info apps` rather than inferring it from a successful build.
A stale build on one device is invisible and explains symptoms it did not
cause: the Apple TV sat three builds behind the iPad through an entire
SharePlay debugging session.

## 5. Judge pixels with OCR, not by eye

Two black screenshots were once read as "playback is broken". OCR showed the
film's opening credits — it was a dark scene. Screenshots are evidence only
once something has *read* them.

This cuts both ways for focus-driven UI: focus is invisible to a screenshot,
which has misled in both directions (a rendered-but-unreachable EPG; a
"broken" Surprise that worked). Assert where a navigation **lands**, not that a
screen drew.

## 6. Schemes

The macOS app is a **separate scheme**. `-scheme ArchiveWatch` with
`-destination generic/platform=macOS` fails with "Unable to find a destination
matching the provided destination specifier", which reads like a toolchain
problem and is not.

```bash
xcodebuild -scheme "ArchiveWatch"       -destination 'generic/platform=tvOS'
xcodebuild -scheme "ArchiveWatch"       -destination 'generic/platform=iOS'
xcodebuild -scheme "Archive Watch Mac"  -destination 'generic/platform=macOS'
```

## 7. What cannot be automated here

- **Passcodes and passwords.** Entering credentials into any field is out of
  scope for the agent, including when the owner supplies them. Device unlock,
  Apple ID sign-in and portal passwords are owner steps. A locked device
  INSTALLS fine and refuses to launch (`FBSOpenApplicationErrorDomain error 7`,
  "Locked"), which arrives as an empty console plus an empty screenshot — i.e.
  as several unrelated failures and two VACUOUS passes. `download_audit.py`
  probes for it and names the condition once. `devicectl device simulate
  biometrics` is not supported on this iPad; opening the Device Hub screen
  viewer (`open "devices://device/open?id=<UDID>"`) DOES wake it to the
  passcode prompt, which is as far as automation goes.
- **FaceTime call placement between two Apple IDs.** The app's own sharing
  controller can start the call; verifying the *system's* call UI cannot be
  driven from here.
- **Store submission review outcomes.** The build uploads; a human submits.

## 8. Harnesses in the repo

| Harness | What it proves |
|---|---|
| `tools/ios_scenario.py` | iPhone/iPad flows, deep-link driven |
| `tools/atv_scenario.py` | Apple TV wake, launch, screenshot, OCR |
| `tools/devlease.py` | Cooperative device sharing between sessions |
| `FunctionalAudit.swift` (`AW_UI_AUDIT=1`) | 44 on-device tvOS assertions |
| `tools/test_catalog_audit.swift` | The same checks against the live published DB, from the Mac |
| `tools/test_home_screen_probe.py` | The backgrounded-launch guard — written to FAIL against the old code first |
| `tools/verify_tv_focus.sh`, `tv_browser_tests.js` | Focus reachability on TV surfaces |
| `tools/download_audit.py` + `DownloadAudit.swift` (`AW_DOWNLOAD_AUDIT`) | Offline downloads end to end: a real archive.org transfer, the file on disk, AVFoundation decoding it, removal — and the offline surfaces by OCR |

## 9. Severing the network without severing yourself

To prove something works offline, deny the network to the APP'S PROCESS:

```bash
sandbox-exec -p '(version 1)(allow default)(deny network*)' "$APP/Contents/MacOS/$BIN"
```

**Never `networksetup -setairportpower en0 off`.** This Mac's default route IS
en0, so switching Wi-Fi off cuts the agent session driving the test, and there
is nothing left to switch it back on with. The sandbox profile is also the
better experiment: the machine stays connected, so a pass cannot be explained
by the network having been down for unrelated reasons.

Two things to know. `sandbox-exec` collides with the **App Sandbox
entitlement**, so run an ad-hoc re-signed copy (`codesign --force --deep --sign
-`) with that entitlement stripped — note this moves the container, so prepare
and assert in the SAME configuration. And always carry a **negative control**:
the audit fetches archive.org and requires it to FAIL, because "it played" is
otherwise equally consistent with the severing not having happened.

A physical iPhone/iPad cannot be put into airplane mode from here at all. There
the offline proof is structural — assert that the URL handed to AVFoundation is
`file://`, which cannot reach the network — plus `AW_FORCE_OFFLINE=1` to render
the offline UI for a screenshot. That hook fakes the STATE, never the response
to it.

A regression test is only known to work once it has been checked to **fail**
against the code that had the bug.
