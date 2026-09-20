# Running a Watch Together Studio test on the Apple TV

Everything here was learned by getting it wrong on 2026-09-19, when a
Continuity-camera session cost about an hour because each of these facts
lived somewhere else — `tools/atv_scenario.py`, a memory entry, and
`docs/WATCH-TOGETHER.md` §9 — and none of them together.

Read this before touching the television. The binding rules for the
feature itself are `docs/WATCH-TOGETHER.md`; this is only how to RUN one.

---

## 1. The device

| | |
|---|---|
| Name | **Ben Bedroom** |
| `devicectl` id | `C3FBA9DE-4A60-555B-A65F-80D6809A275B` |
| pyatv | `--address 10.0.0.223 --id 7A:3F:0C:4E:20:1E --protocol companion` |
| Model | Apple TV 4K (3rd gen), tvOS 27.0 |

**A scan shows two things called "Ben Bedroom" and they are not the same
box.** `Ben Bedroom (2)` at `10.0.0.223` is the Apple TV; `Ben Bedroom` at
`10.0.0.203` is the Samsung panel (`QCQS90D`, AirPlay only, no Companion).
The pyatv `--id` is the anchor — addresses are DHCP and drift.

**Fireplace TV is off limits** (owner, 2026-09-17). It is also the only
2nd-gen box, i.e. the Studio's hardware floor, so the floor cannot be
measured without asking first. Movie Room is not in the tvOS provisioning
profile and fails to install.

## 2. Wake it first — `devicectl` has no wake verb

An asleep Apple TV accepts an INSTALL and refuses a LAUNCH:

    ERROR ... Transaction failed. (System is asleep - foreground app launch forbidden)

Do not ask the owner to press a button; it is automated:

```python
import sys; sys.path.insert(0, 'tools')
import atv_scenario as s
s.wake_tv()          # Companion turn_on, POLLED until PowerState.On
```

Waking a television in someone's house is still an intrusion — at an hour
when the house may be asleep, ask before doing it.

## 3. Choose a film that PASSES THE RIGHTS GATE

**Do not pick on `rightsStatus`.** That field is `public_domain` for 39,164
items; the Studio gates on the AUDIT's bucket, which is narrower by an order
of magnitude. `StudioRights.refusal()` requires:

- `rightsBucket == "safe_pd_age"` (tier `guaranteed`), **and**
- `year <= 1929` — the bucket is an age claim, so the year must agree, **and**
- `contentType` not in `tv-series / tv-episode / tv-special / commercial`.

`rightsBucket` is computed at DB-build time and is **not** in `catalog.json`
(which carries only HIDE buckets). Query the DB the device actually reads:

The release asset is **raw deflate, not zlib** — `zlib.decompress` on it
answers `Error -3 ... incorrect header check`, which reads like a corrupt
download and is not one. (This runbook said `zlib.decompress` until
2026-09-20, so the documented command has never worked.)

```bash
curl -sL https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite.zz \
  -o /tmp/catalog.sqlite.zz
python3 -c "import zlib;open('/tmp/catalog.sqlite','wb').write(zlib.decompressobj(-15).decompress(open('/tmp/catalog.sqlite.zz','rb').read()))"
sqlite3 /tmp/catalog.sqlite "
  SELECT archiveID, year, title FROM items
  WHERE rightsBucket='safe_pd_age' AND year<=1929
    AND contentType NOT IN ('tv-series','tv-episode','tv-special','commercial')
    AND playable=1
  ORDER BY popularityScore DESC LIMIT 20;"
```

That returns **4,210** films, matching the documented tier size — if your
query returns a very different number, it is the wrong predicate.

Two traps inside the result: `isSilentFilm` is unreliable (several 1928
entries flagged `0` are silent), and an id that plays fine may have **no row
at all** in the DB, which is its own refusal ("no rights verdict ... on this
device"). Vary the film between runs — never re-test the same one.

## 4. The doors

| Variable | Effect |
|---|---|
| `AW_START_ITEM` + `AW_AUTOPLAY=1` | open and play that film |
| `AW_STUDIO_TV=1` | wait for `.playing`, check rights, then present the go-live sheet **and stop there** |
| `AW_STUDIO_TV_GOLIVE=1` | from inside the sheet, fire the real commit chain (needs `AW_STUDIO_DEST`) |
| `AW_STUDIO_DEST` | bench RTMP URL; **without it the `=1` door silently returns** |
| `AW_STUDIO_TV_SECONDS` | how long the door holds (default 180) |
| `AW_STUDIO_TV_SOUND=1` | do NOT mute the television speakers |
| `AW_STUDIO_TV_FORCE=1` | **with `AW_STUDIO_TV=1`** — skip the configuration gate + sheet, encode with no destination |
| `AW_STUDIO_TV_MIXER=1` | **with the two above** — open Rule 8.8c's live mixer straight away |
| `AW_DIAG_FILE=1` | write diagnostics to `Library/Caches/awdiag.log` |

**`AW_STUDIO_TV_FORCE` and `AW_STUDIO_TV_MIXER` are MODIFIERS of
`AW_STUDIO_TV=1`, not doors of their own.** The whole block sits behind
`guard environment["AW_STUDIO_TV"] == "1"`, so `FORCE` on its own launches the
film and nothing else — which looks exactly like the door firing and failing.

`AW_STUDIO_TV=1` alone deliberately **ends at the sheet** — it will not press
Go live, because a door that pressed it would broadcast from a television
nobody is standing in front of. Use that form when a human needs to pair a
camera or press something.

**Mute the room by default, and turn it back on when the owner is present.**
The `=1` door mutes the TV speakers (`AWMUTE`) and the wire is unaffected.

## 5. Console OR screenshots — never both

Two `devicectl` sessions kill the stream (measured). So:

- **With `--console`**: you get NSLog, including ObjC exception text and the
  crash tail. No screenshots.
- **Without `--console`**: you can capture the screen, and diagnostics come
  from the file.

```bash
# screenshot — the verb is `capture screenshot`, NOT `screenshot`
xcrun devicectl device capture screenshot --device "$DEV" --destination shot.png
# a frame under ~300 kB is the doze signature; re-wake and retry

# diagnostics off the device
xcrun devicectl device copy from --device "$DEV" \
  --domain-type appDataContainer --domain-identifier app.archivewatch.tvos \
  --source Library/Caches/awdiag.log --destination awdiag.log
```

**A pyatv press blocks screenshots for about a minute.** Measured 2026-09-20:
after one `atv_scenario.press()`, `devicectl device capture screenshot` failed
five times running and succeeded at +45 s. The failure prints an
`XPCConnectionDescription` blob and NO error line, so a grepped capture reads
as silence and leaves a STALE file in place — assert on `Screenshot saved`,
never on the exit code. Driving a multi-press navigation this way costs about
a minute a press, which is why a surface needing several presses to reach gets
a door instead (`AW_STUDIO_TV_MIXER`).

**CHOOSE A FILM WITH AUDIO, and MEASURE that rather than trusting a field.**
Owner, 2026-09-20: *"you are choosing the wizard of oz, a silent film, to test
streaming and without audio, it is very difficult to decide whether it is
working or not."* The Studio's rights tier is `safe_pd_age` — published before
1930 — so nearly everything it can broadcast is silent cinema, and
`isSilentFilm` does NOT answer the question: it is 0 for Steamboat Bill Jr and
The Wind, both silent. What decides it is whether the DERIVATIVE carries a
recorded score. Measure it:

```
ffmpeg -v error -ss 180 -t 15 -i "<smallest mp4>" -vn -ac 1 -ar 16000 seg.wav -y
ffmpeg -i seg.wav -af volumedetect -f null -   # NO -v error on this one
```

**`-v error` on the second command hides the answer** — `volumedetect` prints
at info level, so suppressing it reports a blank for every film and reads as
"no audio". Measured 2026-09-20: prinzen-achmed -23.8 dB mean, steamboat_bill
-22.5, TheGeneral720p1926 -27.5, the-wind_1928 -29.4, our-gang -31.4. All have
real scores.

`DiagFile` **truncates on every launch**, so pull the log before relaunching
or the evidence is gone. An ObjC exception never reaches that file — it goes
to NSLog — so a crash hunt needs `--console`.

Everything needs `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`.

## 6. What the log lines mean

| Line | Says |
|---|---|
| `AWCONT connected= camera= micPort=` | what Continuity found before anything is built |
| `AWCONT camera formats=… active=…` | what the phone actually offers |
| `AWCONT preset=` | which session preset was used |
| `AWCONT step=makeSession → sessionMade → cameraTapAttached → cameraEngineAttached → startRunning` | one line per call, so a crash names the call after the last line printed |
| `AWCAM frames=N (+n/s)` | camera frames REACHING the tap — separates "no frames" from "frames not drawn" |
| `AWSYNC` | film-audio position vs playhead |
| `AWMUTE` | the television speakers were muted by a door |

**A rights refusal currently prints NOTHING.** It sets the on-screen sentence
and returns, so from the console a refused run and a door that never fired
are identical. If `AW_STUDIO_TV=1` produced no `AWCONT` at all, suspect the
gate first and check the film against §3.

## 7. Judge it from the server, not the app

The app saying `attached camera=Continuity Camera` is not evidence a tile is
on the wire — on 2026-09-19 that line was true and the program had no tile in
it. Record the bench and look:

```bash
mediamtx mtx.yml       # record: yes, recordFormat: fmp4
ffprobe -v error -show_entries stream=codec_name,width,height -of csv=p=0 rec.mp4
ffmpeg -y -ss 20 -i rec.mp4 -frames:v 1 frame.png     # then LOOK at it
ffmpeg -v info -i rec.mp4 -af volumedetect -f null -  # -v error HIDES this output
```

## 8. Stop when you stop testing, and VERIFY

`terminate` needs `--pid` and prints USAGE if misused — which looks like
success. Ask the device what is running instead of trusting it:

```bash
PID=$(xcrun devicectl device info processes --device "$DEV" \
      | grep 'ArchiveWatch.app/ArchiveWatch' | awk '{print $1}' | head -1)
xcrun devicectl device process terminate --device "$DEV" --pid "$PID"
xcrun devicectl device info processes --device "$DEV" \
  | grep -c 'ArchiveWatch.app/ArchiveWatch'      # expect 0
```

Stop the bench server too, and leave no recordings in the owner's home
directory.

## 9. Continuity camera: what is known

- Pairing is done from the go-live sheet (`continuityDevicePicker`, tvOS 17+)
  or the system picker. The owner must approve camera + mic **on the phone**;
  there is no way to pre-grant.
- **The connection does not appear to survive across app launches.** It was
  `connected=true` at 08:06 and `connected=false` at 08:19 on the same day
  with the same phone in the house. SCRATCHPAD's "a paired phone is found
  automatically after" is not reliable; budget for re-pairing, and never
  report a `connected=false` run as a camera test — that is a skip, not a
  pass (Decision 130).
- `micPort=none` alongside a working camera is **normal**: the camera comes
  from discovery, the microphone only from the picker's `AVContinuityDevice`.
- **A session may not drive a Continuity device's format.** `sessionPreset`
  must be `.inputPriority`; anything else throws
  `-[AVCaptureDevice _setActiveFormat:…sessionPreset:] Unsupported format
  ((null))`, an ObjC exception that kills the app with signal 6. The device
  DOES publish 1280x720 — the format was never missing, and
  `canSetSessionPreset` returns true for it anyway, so that predicate is not
  a usable gate here.
- Every `addOutput` onto a Continuity session belongs inside
  `beginConfiguration()`/`commitConfiguration()`, or it commits on the spot
  and forces exactly that renegotiation mid-flight.
- **The phone's ORIENTATION cannot be learned from the television, and the
  feature is LANDSCAPE ONLY because of it.**
  `AVCaptureDevice.RotationCoordinator` is the API for it, and
  `AVCaptureDevice.h` says, twice: *"External cameras return 0 degrees of
  rotation even if they physically rotate when their position in physical
  space is unknown."* Measured with a phone connected at 31 fps:
  `AWCAM rotation 0 applied`. A host-stated Landscape/Portrait choice was
  built, flown for 134 s and withdrawn by the owner the same day (Rule 8.8d) —
  90 degrees was the wrong direction with nothing to pick the right one with,
  and `StudioLayout.corner` sizes its tile from ONE axis, so a portrait buffer
  produced a tile 82% of the program's height. **Prop the phone on its side.**
  Judge a rotation by `AWCAM frame shape WxH`, never by the attach's own
  line — the attach logs `rotation N applied` whether or not the buffers ever
  change shape.
