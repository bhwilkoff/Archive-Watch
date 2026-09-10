# How this project is engineered

Not a style guide. Every rule below is here because breaking it cost this
project something specific, and each one names the incident, so a reader can
judge the rule by its evidence rather than take it on trust.

The through-line: **a system that cannot tell you it is broken is worse than one
that is obviously broken.** Most of the expensive faults here were green.

---

## 1. Absence is not evidence

A reader that could not read must say so. It must never render as a zero, a
blank, or a silent omission.

This is the rule the Pulse dashboard is built on (`docs/PULSE.md`), and it was
learned four separate ways in one week:

| What happened | What it looked like |
|---|---|
| `apple_reviews` failed in CI on a Python 3.11 syntax error | "0 reviews" beside four healthy readers |
| A `--only` run overwrote the file it did not collect | Every mention CI had gathered, gone |
| A full run dropped the section of a failed reader | Four reviews became a hole |
| A fuzzy search did not repeat | A real third-party mention evaporated |

Each is the same lie told a different way. The fixes are in the collector:
sources are isolated and record their own failure, partial runs merge, a failed
reader keeps its last value marked stale, and mentions accumulate.

**Apply it**: when a function can return nothing, ask whether "nothing" and
"could not tell" are distinguishable to the caller. If they are not, that is the
bug, before any behaviour is written.

## 2. A green run is not a working run

Every serious pipeline failure in this project's history was green.

- `publish-db` ran for two days with **no `GH_TOKEN`**, skipped its SQLite build
  and every check, and reported success. The app's catalog went stale.
- The health auditor could not see it, because that workflow was on a
  `NOT_PRODUCERS` list that meant "skip entirely".
- `verify_external_match` called `adopt(it, {})`, and every branch of `adopt` is
  `if rec.get(...)` — so an EMPTY record cleared **nothing** while 266 items
  were marked cleared.
- `--clobber` deletes before uploading; a 422 on a 1.17 GB member took both
  assets with it, and a `|| echo "first run"` swallowed the evidence.
  **702,148 word timings destroyed by a green run.**

**Apply it**: a step's exit code says whether the code ran, not whether the work
happened. Assert the *yield* — rows written, files present, counts that grew.
`tools/sqlite_publish_guard.py` and `tools/audit_workflow_health.py` exist for
exactly this.

## 3. A test is not a test until you have seen it fail

Every check in this repo is written, then deliberately broken, then confirmed to
fail. The failure count is recorded in the commit message.

This is not ceremony. `frame_is_home_screen()` returned False for **every frame
since it was ported**, so a tvOS guard never ran once — the port added a
defensive branch the original does not have, and a bare `except` hid it. A test
that has never failed is a test that might be asserting nothing.

Recent examples, with their controls:

```
test_pulse_collect      55 cases  — 7 fail with relevant() stubbed to True
test_pulse_charts       31 cases  — 1-2 fail per broken encoding
test_sw_bypass           9 cases  — 2 fail with the /pulse bypass removed
UniqueByTest              5 cases  — 3 fail with uniqueBy stubbed to `this`
CatalogCorruptionTest     6 cases  — 4 fail matching the bare word "corrupt"
```

## 4. Verify on the glass, in the environment that ships

Compiling is not running. Running on a simulator is not running on the device.
Running the debug build is not running what users get.

- Play **rejected** a release because R8 stripped a Room constructor reached
  through Glance. Debug never minifies, so every debug install looked perfect.
  `tools/submit-play.sh` now refuses to upload if the RELEASE artifact crashes
  on a real device.
- A `| tail` on an `xcodebuild` once hid a `BUILD FAILED` and nearly had a fix
  reported as verified. Always grep for the verdict.
- The Pulse page looked stale while the deployed JSON was current: the viewer's
  **service worker** was serving `/pulse` from cache, because it is registered
  at root scope and catches everything not explicitly excluded.

**Apply it**: state plainly what was verified and where. "Compile-verified, not
run" is a complete and honest sentence. Claiming more is the only unacceptable
option.

## 5. Measure before theorising, and record what you ruled out

The Android cold start went 32s → 6.3s only after **five plausible theories were
measured and reverted** — serialization, network, image contention, per-row
compression (which *grew* the download to 57.9 MB), and a core artifact without
`item_json`.

Writing down what was ruled out is as valuable as the fix: it stops the next
session re-walking it. `tools/submit-amazon.py` carries its own disproven
hypothesis in its docstring for this reason.

**But a negative finding needs an expiry, and never a prohibition.** That same
file concluded "the API Access page does not exist in this console" and closed
with **"Do NOT re-walk the console nav."** The page did exist, one menu over.
Amazon's Reporting and Submission APIs were then unreachable for five weeks over
a two-click mapping, and the note written to save time is what stopped anyone
looking. Record what you ruled out *and how you ruled it out*, so the next reader
can judge whether the evidence still holds — an absence you searched for once is
much weaker evidence than a measurement, and consoles change.

**Apply it**: when a fix lands, the commit says what else was tried and why it
was wrong.

## 6. A number needs a comparison; a chart needs a reason

From `docs/PULSE.md` §How it LOOKS, which is binding:

- Show every figure against a scale, its siblings, its own past, or a whole.
- Encode in Cleveland & McGill's order: position, then length, then area, then
  colour. So no pie, no donut, no bubble.
- Colour means **state**, never quantity (Decision 013's split).
- No gauges — a bullet graph carries measure, scale, bands and target in 22px.
- Zero is **drawn**; absence is **written**.

## 7. Popularity is not editorial judgement

The social programme published *The Birth of a Nation* as "Free to watch —
#SilentFilm #Drama". Every signal the selector rewards pointed at it: 26,892
votes, professional artwork, a silent film — and TMDb's own descriptor tags for
it include "inspirational" and "feel-good", while the item's own search text
says "ku klux klan" and "racism".

Nothing in the system was making an editorial decision, so ranking made it.

`ops/social-do-not-promote.json` gates **broadcast only, never the app**.
Holding a work and recommending it are different acts: the archive's value is
that it keeps difficult material, and a daily post with two hashtags has no room
for the context some films require.

**Apply it**: any automated surface that RECOMMENDS needs a place for a human
judgement that ranking cannot express.

## 8. The owner's machine is not a build server

A release build is R8 plus a full Kotlin compile. On 2026-09-09 the owner asked
why the machine had slowed to a crawl. Two causes:

1. Two `social_card.py` processes at **98% CPU each since 6 September** — three
   and a half days, two cores pinned — stuck in a text-wrapping loop on code
   from *before* that loop was fixed. **A fix does nothing for a process already
   spinning.** The loop now carries a hard iteration bound as well as a correct
   exit condition.
2. Gradle's own daemon was capped at 4 GB, but the **Kotlin compile daemon is a
   separate JVM** whose heap was unbounded, and `parallel=true` had no worker
   cap.

The durable answer is not a smaller heap. `.github/workflows/play-release.yml`
builds and publishes in CI, `tools/submit-play.sh` dispatches it by default, and
`tools/ffmpeg_limits.py` gives ffmpeg half the cores at `nice 10` locally and
the whole runner in CI.

A third, smaller instance turned up later: three `python -m http.server`
preview servers, two of them older than two days. Nobody noticed, because a
process that is merely IDLE is invisible until something else needs the
machine — and the harness that replaced the need for them
(`tools/test_pulse_render.mjs`, which runs the real page JS in a DOM shim)
had already made them unnecessary.

**Apply it**: anything that can saturate the machine gets a bound and a CI path.
A tool that is correct but can hang is not finished. Prefer a harness to a
server — a test that needs no process left running cannot leave one. And run
`tools/dev_cleanup.sh` before walking away.

## 9. A red X means THIS run could not do its job

Decision 107, learned by being corrected twice.

An auditor never fails over somebody else's health — findings go to a report or
an issue, never an exit code. A partial success is a warning. A run destroyed in
the concurrency queue was never a failure. A workflow that declares
`cancel-in-progress` is asking to be superseded, and calling that KILLED is the
auditor alerting on a design decision.

An alert channel that cries wolf is one the owner mutes, and then a real break
goes unread.

## 10. Search the decision log for the MECHANISM, not the symptom

Most of one evening went into rebuilding a loopback media server, HLS-through-a-
resource-loader, and the `-12881` limit — all three already written down in this
repo. The log had been searched for the symptom and never for the thing about to
be built.

`DECISIONS.md` holds a complete index for this reason (Decision 092).

---

## The shape of a change here

1. **Read** the binding doc for the surface (`docs/*-DESIGN.md`, `docs/PULSE.md`,
   `docs/tvos-playbook.md`) and quote the rule the change implements.
2. **Measure** before theorising. Write down what you ruled out.
3. **Write the test, then break it** and record the failure count.
4. **Verify in the shipping environment**, and say exactly what you verified.
5. **Bump** `AppVersion.xcconfig` — the one version number (Decision 101).
6. **Commit** quoting the owner's words where they prompted it, naming what was
   tried and rejected.
7. **Log a decision** if the next developer would get it wrong without knowing.

## Where the disciplines live

| Concern | File |
|---|---|
| Product health, every channel | `docs/PULSE.md`, `tools/pulse_collect.py` |
| Fleet health, alerting rules | `tools/audit_workflow_health.py`, Decisions 090/093/107 |
| Workflow shape gates | `tools/check_workflow_gates.py` |
| Shared-index safety | `tools/sqlite_publish_guard.py`, Decision 089 |
| Real-device testing | `docs/DEVICE-TESTING.md` |
| Store submission | `docs/APPLE-SUBMISSION-CLI.md`, `.github/workflows/play-release.yml` |
| What must never be promoted | `ops/social-do-not-promote.json` |
| Machine resource policy | `tools/ffmpeg_limits.py`, `android/gradle.properties` |
