# Samsung Tizen — signing and side-loading

The `.wgt` is built and installed entirely from the CLI. The ONE step that
cannot be scripted is the Samsung account sign-in, and this file exists because
finding it cost an evening.

## The pipeline

```sh
export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/tizen-studio/tools:$PATH"
export TIZEN_PROFILE=archivewatchSamsung
sdb connect <TV-IP>                       # 26101 is the debug port
bash tv/build-tv-packages.sh tizen        # -> tv/dist/ArchiveWatch.wgt
tizen install -n ArchiveWatch.wgt -- "$PWD/tv/dist"
tizen run -p ArchvWatch.ArchiveWatch
```

Toolchain: `web-cli_Tizen_SDK_10.0_macos-64.bin` from
`download.tizen.org/sdk/Installer/tizen-sdk_10.0/`, plus the packages
`TV-SAMSUNG-Public-WebAppDevelopment`, `TV-SAMSUNG-Extension-Tools`,
`cert-add-on`, `Certificate-Manager`. **Not** the emulator — real devices only.

## Enabling Developer Mode on the TV

Smart Hub -> **Apps** in the top banner -> **Settings** (the gear, INSIDE Apps)
-> enter **12345**. Modern Samsung remotes have no number keys: press **123**
for an on-screen keypad. Toggle Developer mode ON, enter this Mac's IP, restart
the TV. "Develop Mode" then shows at the top of the Apps panel.

Verified 2026-09-09 on a QN65S90CDFXZA (2023 S90C, Tizen 9.0).

## The certificate — the part that cost the evening

A Samsung TV REJECTS the generic Tizen distributor certificate:

    install failed[118, -12], reason: Check certificate error :
    Invalid certificate chain with certificate in signature.

**RULED OUT, so nobody re-walks it:** the SDK's default profile ships
`tizen-distributor-signer`, which expired **2012** (its CA in 2022) and is a
"Tizen Test CA" cert. That looks like an excellent explanation. It is not —
rebuilding the profile with `tizen-distributor-signer-new` (valid to 2032)
produces the IDENTICAL error. Samsung genuinely requires its own certificates.

`tizen certificate` has **no** Samsung option; the CLI creates Tizen certs only.
The Samsung path is Certificate Manager, and it is easy to conclude it is not
there:

1. `open ~/tizen-studio/tools/certificate-manager/certificate-manager.app`
2. Click the small **`+`** icon beside **"Certificate Profile"** — NOT the big
   `+` in the Distributor Certificate box, which only imports an existing file.
   This is the step that is impossible to find; nothing labels it.
3. A Tizen | **SAMSUNG** chooser appears. Pick Samsung.
4. Device Type **TV** -> name the profile -> author certificate (a LOCAL
   password, min 8 with upper/lower/numeral) -> **Samsung account sign-in in
   your browser** -> distributor certificate.
5. The TV's **DUID is filled in automatically** from the live `sdb` connection.
   Privilege **Public** is correct for a normal app.

Certificates land in `~/SamsungCertificate/<profile>/`. **Keep them** — Samsung
requires every future update to be signed with the same certificate. The
distributor cert is tied to the DUIDs listed in it, so a new test TV means
re-issuing it with that TV added.

### Driving that GUI from a script

It is an x86 Eclipse under Rosetta and **ignores synthetic AX clicks**
(`System Events click at`). Real events work — `cliclick`, with a slow
press/release (`m: w:600 dd: w:250 du:`) — and where a click only focuses a
button, **Space** activates a focused one and **Return** fires the default one.

## Traps in the packaging itself

- **A space in the .wgt name makes the install fail SILENTLY.** `tizen package`
  names the file from config.xml `<name>` ("Archive Watch.wgt") and
  `tizen install` interpolates it into a remote shell command unquoted: the TV
  answers "Failed to install" with an EMPTY platform log. The build strips
  spaces. Never ship a .wgt whose name has one.
- **`-o` on `tizen package` resolves relative to the tizen BINARY**, not the
  cwd. Always pass an absolute path.
- **The version sed must be anchored.** An unanchored `version="[0-9]..."` also
  rewrites the XML declaration (must stay 1.0) and `required_version` (the
  minimum TIZEN PLATFORM, not the app version).

## There is no remote Web Inspector on a retail TV

Measured 2026-09-09 on a retail QN65S90CDFXZA:

| Route | Result |
|---|---|
| `sdb shell 0 debug <appid>` | hangs, then `closed` |
| `tizen run -p <id> --debug` | `--debug` is not a flag; prints usage |
| ports 7011 / 7012 / 9998, forwarded and direct | connection refused |

`sdb shell` is **closed entirely** on retail hardware — every command, not just
the debug ones:

    sdb shell "which screenshot"   ->  closed
    sdb shell 0 applist            ->  works (a whitelisted verb)

So `install`, `run` and `applist` are the whole vocabulary: no shell, no
screenshot, no dlog. Remote debugging needs a developer (UD) unit. On retail hardware the oracle for
a Tizen build is **screenshots from the owner plus the desktop browser in TV
mode** (`archivewatch.org/?tv=1`, which `tv.js` treats as a TV). Do not budget
time for a device console; there isn't one.

## 2026-10-03 — turning the set on, and an inspector on a RETAIL TV

**Turning it on.** Wake-on-LAN (wifi MAC B8:B4:09:E5:CF:64) does nothing from
standby on this set. What works: wake the **Apple TV on the same HDMI chain
("Ben Bedroom", 10.0.0.223)** and HDMI-CEC switches the Samsung on —

    ~/.pyatv-venv/bin/atvremote -s 10.0.0.223 -i 7A:3F:0C:4E:20:1E \
        --protocol companion turn_on

(`-s` scans that one host; `--address` alone answered "Found more than one
Apple TV"). `curl http://10.0.0.203:8001/api/v2/` then reports
`"PowerState":"on"` (empty while in standby). `tizen run` then puts our app in
front of the HDMI input.

**An inspector on the retail set — Chii.** Samsung's Web Inspector needs a
debug launch the retail firmware refuses; Chii does not. A debug package built
with `AW_TV_INSPECT=10.0.0.90:8080` loads Chii's `target.js` and appears in
`http://localhost:8080/targets`; `chii start -p 8080` serves it, the DevTools
page is `http://localhost:8080`, and `node tools/tv_inspect.mjs "<js>"`
evaluates JavaScript inside the app ON THE TV (Tizen 9.0, Chromium 120,
1920x1080, dpr 1, measured). **A widget with no CSP of its own runs only its
own scripts**: the first debug package never requested `target.js`; the
debug package now declares a `<tizen:content-security-policy>` naming the
inspector host. The store package declares none and carries no hook (the
build refuses one). The package is renamed `ArchiveWatch-debug.wgt`.

**The network remote (port 8001/8002, `tools/samsung_remote.mjs`) stays
SILENT on this set**: the socket opens and the TV never answers — with Access
Notification Off, an empty device list, and (the owner tried) IP Remote on;
`samsungtvws` times out identically. Not solved; key input goes through the
app's own handler via the inspector instead.
