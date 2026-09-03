# Submitting Archive Watch to the App Store from the CLI

**The whole ship is commands now — build, upload, version, notes, and the submit
itself. Nobody needs to open App Store Connect.**

New as of 2026-09-03, ported from the Tidbits Trivia pathway. Before it, the
build was automated but a human created the version in Connect, attached the
build and pressed Submit. The reason that stayed manual is worth stating: the
obvious API endpoint for submitting is **deprecated and answers 403**, which
reads as "you can't do this" rather than "use the other one".

---

## The three commands

```bash
# 1. Bump BOTH numbers. Every commit moves them (AppVersion.xcconfig says why).
vim AppVersion.xcconfig                 # e.g. 1.42.1 / 1013
git commit -am "1.42.1 (1013) — …" && git push

# 2. Build, sign, upload all three platforms. ~15 min.
gh workflow run appstore-build.yml -f platform=all

# 3. Open the version, attach the build, set the notes, submit — all three.
gh workflow run appstore-submit.yml \
  -f mode=ship -f platform=all \
  -f release_notes="What's new…" \
  -f submit=true
```

Locally the same thing, if credentials are on the machine:

```bash
set -a; . tools/asc-credentials.env; set +a
python3 tools/asc_release.py status
python3 tools/asc_release.py ship --notes "What's new…" --submit
```

Then confirm — the tool's own success message is not evidence:

```bash
python3 tools/asc_release.py status     # expect WAITING_FOR_REVIEW per platform
```

---

## Version numbers: ONE number, and it only goes up

`AppVersion.xcconfig` is the single source of truth. `asc_release.py` reads
`MARKETING_VERSION` and uses it as the **App Store version string**, and reads
`CURRENT_PROJECT_VERSION` as the **build to attach** — so the store version and
the binary's own `CFBundleShortVersionString` are always the same number.

They had drifted badly: the App Store showed **1.41** while the repo read
**1.3.491**, because the store version was typed by hand in Connect and the repo
number was only ever a build tag. Compared component-wise `1.3.491` is
**LOWER** than `1.41` (3 < 41), so the repo number could not have been used as
a store version at all. The scheme therefore moved to **1.42.0** on 2026-09-03
— greater than 1.41, and still three-part so the per-commit patch bump keeps
working (1.42.1, 1.42.2, …), each one greater than the last.

Android's `versionName` tracks the same number (its `versionCode` is separate
and Play-specific).

---

## The traps, each of which cost something

**1. A TestFlight upload does not create an App Store version.** Separate
records. An uploaded build sits there indefinitely; `ship` opens the version.

**2. `POST /v1/appStoreVersionSubmissions` is deprecated.**

```
403  The resource 'appStoreVersionSubmissions' does not allow 'CREATE'.
     Allowed operation is: DELETE
```

Submitting is three calls: create a `reviewSubmissions`, add the version as a
`reviewSubmissionItems`, then PATCH `submitted: true`.

**3. Three platforms is three submissions.** tvOS, iOS and macOS ship from one
universal target with one build number, but Connect keeps a separate
`appStoreVersion` AND a separate `reviewSubmission` per platform. Hardcoding one
platform silently ships one app — which is what happened in the Tidbits repo.

**4. Builds must be filtered by platform.** `platform=all` produces three builds
sharing one number. Without `filter[preReleaseVersion.platform]` the first match
wins at random and Connect rejects it with "The specified build has a different
platform than the version" — which reads like a build problem, not a query
problem. **`tools/asc_build_exists.py` still has this blind spot**: it filters by
number only, so its "already uploaded" can mean one platform of three.

**5. A wrong version string cannot be deleted — only renamed.** Measured
2026-09-03: Connect **accepted** a version string lower than the live one
(1.3.494 created while 1.41 was live), so creation does not enforce ordering;
the rejection comes later. And `DELETE` answers
`409 STATE_ERROR — Only the first version of any platform can be deleted.`
The recovery is `PATCH versionString` while the version is in
`PREPARE_FOR_SUBMISSION`, which is also why `ship` reconciles an existing
editable version's string to the target rather than leaving it alone.

**6. Attach only a `VALID` build.** A build Apple is still processing fails with
a confusing relationship error rather than "still processing". `status` prints
the processing state; platforms appear as Apple finishes them, not in upload
order (measured: macOS, then iOS, then tvOS ~7 minutes apart).

---

## Release type: it auto-releases

Versions are created **`AFTER_APPROVAL`** — approval puts it on the store with
nobody pressing anything. An approved build sitting unreleased is a silent
stall. To change it, `--release-type MANUAL`; release type is logistics rather
than reviewable content, so Apple lets it change even while the version waits
in review.

---

## Credentials

`ASC_KEY_ID`, `ASC_ISSUER_ID`, and `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`.
Locally they live in `tools/asc-credentials.env` (gitignored); in CI they are
the `ASC_KEY_P8` / `ASC_KEY_ID` / `ASC_ISSUER_ID` secrets that
`appstore-build.yml` already uses. `PyJWT` is required — system Python has none
and PEP 668 blocks `pip install --user`, so use a venv locally.
