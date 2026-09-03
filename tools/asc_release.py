#!/usr/bin/env python3
"""Ship Archive Watch to the App Store end to end — no App Store Connect UI.

    python3 tools/asc_release.py status
    python3 tools/asc_release.py ship --notes "What's new…" --submit
    python3 tools/asc_release.py ship --platform ios --dry-run

Ported from the Tidbits Trivia pathway (docs/APPLE-SUBMISSION-CLI.md there),
which learned every trap below the expensive way. Read them before changing
anything here: each one built and archived GREEN and failed only at submit.

WHAT THE UPLOAD DOES NOT DO
  `appstore-build.yml` uploads a binary. A TestFlight build is NOT an App Store
  version — they are separate records, and the absence of the second is why
  submitting "the uploaded build" does nothing. `ship` opens the version.

THE OBVIOUS SUBMIT ENDPOINT IS A TRAP
  POST /v1/appStoreVersionSubmissions answers
      403 The resource 'appStoreVersionSubmissions' does not allow 'CREATE'.
          Allowed operation is: DELETE
  Deprecated, not broken, and the message never says so. Submitting is three
  calls: create a `reviewSubmissions`, add the version as a
  `reviewSubmissionItems`, then PATCH `submitted: true`. Apple's model is a
  submission CARRYING items, which is why a version cannot be sent alone.

THREE PLATFORMS MEANS THREE SUBMISSIONS
  tvOS, iOS and macOS ship from one universal target with ONE build number, but
  Connect keeps a separate appStoreVersion AND a separate reviewSubmission per
  platform. Hardcoding one platform silently ships one app — which is exactly
  what happened in the Tidbits repo. Default here is all three.

BUILDS MUST BE FILTERED BY PLATFORM
  `platform=all` produces three builds sharing one number. Without
  filter[preReleaseVersion.platform] the first match wins at random and Connect
  rejects it with "The specified build has a different platform than the
  version" — which reads like a build problem rather than a query problem. This
  is also the blind spot in `asc_build_exists.py`, which filters by number only.

A WRONG VERSION STRING CANNOT BE DELETED — ONLY RENAMED
  Measured 2026-09-03: Connect ACCEPTED a versionString LOWER than the live one
  (created 1.3.494 while 1.41 was READY_FOR_SALE), so creation does NOT enforce
  ordering — the rejection comes later, at review. And DELETE answers
      409 STATE_ERROR  Only the first version of any platform can be deleted.
  So a mistyped version is permanent as a record. It IS renameable while in
  PREPARE_FOR_SUBMISSION, which is the recovery: PATCH versionString rather
  than trying to remove it. That is also why `ship` RECONCILES an existing
  editable version's string to the target instead of leaving it alone.

THE VERSION STRING COMES FROM AppVersion.xcconfig
  So the App Store version always equals the binary's own
  CFBundleShortVersionString and the two numbering schemes cannot drift apart
  again (they had: App Store 1.41 against a repo reading 1.3.491).
"""
import argparse
import json
import os
import pathlib
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from asc_certs import token           # noqa: E402  (JWT/ES256 lives there already)

BASE = "https://api.appstoreconnect.apple.com"
BUNDLE = "app.archivewatch.tvos"      # one record serves all three platforms (D042)
REPO = pathlib.Path(__file__).resolve().parent.parent

PLATFORMS = {"tvos": "TV_OS", "ios": "IOS", "mac": "MAC_OS"}

# States in which Connect will let us edit a version's content.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}
# States where the version is already on its way — editable only for release
# logistics (releaseType), never for reviewable content.
IN_FLIGHT = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"}


class ASCError(RuntimeError):
    def __init__(self, status, body):
        super().__init__(f"{status}: {body[:400]}")
        self.status, self.body = status, body


def call(path, method="GET", body=None):
    req = urllib.request.Request(
        f"{BASE}/{path.lstrip('/')}", method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        raise ASCError(e.code, e.read().decode()) from None


def repo_version():
    """(marketingVersion, buildNumber) from the ONE file that owns them."""
    text = (REPO / "AppVersion.xcconfig").read_text()
    mv = re.search(r"^MARKETING_VERSION\s*=\s*(\S+)", text, re.M).group(1)
    bn = re.search(r"^CURRENT_PROJECT_VERSION\s*=\s*(\S+)", text, re.M).group(1)
    return mv, bn


def app_id():
    d = call(f"v1/apps?filter[bundleId]={BUNDLE}")["data"]
    if not d:
        sys.exit(f"no app for bundle id {BUNDLE}")
    return d[0]["id"]


def versions(aid, platform):
    return call(f"v1/apps/{aid}/appStoreVersions?limit=50"
                f"&filter[platform]={platform}"
                "&fields[appStoreVersions]=versionString,appStoreState,releaseType")["data"]


def find_build(aid, number, platform):
    """The build with this number ON THIS PLATFORM, or None."""
    d = call(f"v1/builds?filter[app]={aid}&limit=50"
             f"&filter[version]={number}"
             f"&filter[preReleaseVersion.platform]={platform}"
             "&fields[builds]=version,processingState,expired")["data"]
    return next((b for b in d if not b["attributes"].get("expired")), None)


def attached_build(version_id):
    try:
        d = call(f"v1/appStoreVersions/{version_id}/build"
                 "?fields[builds]=version").get("data")
        return (d or {}).get("attributes", {}).get("version")
    except ASCError:
        return None


# ----------------------------------------------------------------- status

def status(aid):
    mv, bn = repo_version()
    print(f"repo: {mv} ({bn})\n")
    worst = 0
    for name, platform in PLATFORMS.items():
        vs = versions(aid, platform)
        live = next((v for v in vs if v["attributes"]["appStoreState"] == "READY_FOR_SALE"), None)
        edit = next((v for v in vs if v["attributes"]["appStoreState"] in EDITABLE | IN_FLIGHT), None)
        b = find_build(aid, bn, platform)
        bstate = b["attributes"]["processingState"] if b else "NOT UPLOADED"
        print(f"  {name:5} live={live['attributes']['versionString'] if live else '-':8}"
              f" in-progress={(edit['attributes']['versionString'] + ' ' +
                               edit['attributes']['appStoreState']) if edit else '-'}")
        print(f"        build {bn}: {bstate}"
              + (f"   attached to {attached_build(edit['id'])}" if edit else ""))
        if bstate != "VALID":
            worst = 1
    return worst


# ----------------------------------------------------------------- ship

def editable_version(aid, platform, create, dry):
    """The version being PREPARED — never the one already live."""
    vs = versions(aid, platform)
    for v in vs:
        if v["attributes"]["appStoreState"] in EDITABLE:
            have = v["attributes"]["versionString"]
            print(f"    using existing {have} ({v['attributes']['appStoreState']})")
            # RECONCILE the string. An editable version left at an older number
            # would be shipped carrying a binary whose CFBundleShortVersionString
            # says something else — the exact drift that put App Store 1.41
            # against a repo reading 1.3.491. Renaming is also the only way to
            # correct a mistyped version, since it cannot be deleted.
            if have != create and not dry:
                call(f"v1/appStoreVersions/{v['id']}", method="PATCH", body={"data": {
                    "type": "appStoreVersions", "id": v["id"],
                    "attributes": {"versionString": create}}})
                print(f"    renamed {have} -> {create}")
                v["attributes"]["versionString"] = create
            elif have != create:
                print(f"    would rename {have} -> {create}")
            return v
    inflight = next((v for v in vs if v["attributes"]["appStoreState"] in IN_FLIGHT), None)
    if inflight:
        print(f"    already {inflight['attributes']['appStoreState']} at "
              f"{inflight['attributes']['versionString']} — nothing to do")
        return None
    live = [v["attributes"]["versionString"] for v in vs
            if v["attributes"]["appStoreState"] == "READY_FOR_SALE"]
    if dry:
        print(f"    would CREATE version {create} (live: {live[:3]})")
        return None
    # AFTER_APPROVAL by default: an approved-but-unreleased version is a silent
    # stall, and this project has lost days to exactly that shape elsewhere.
    made = call("v1/appStoreVersions", method="POST", body={"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": platform, "versionString": create,
                       "releaseType": "AFTER_APPROVAL"},
        "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})
    print(f"    created {create} (AFTER_APPROVAL)")
    return made["data"]


def set_notes(version_id, notes, locale, dry):
    locs = call(f"v1/appStoreVersions/{version_id}/appStoreVersionLocalizations?limit=50")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == locale), None)
    if loc is None:
        print(f"    !! locale {locale} absent; have "
              f"{[l['attributes']['locale'] for l in locs]}")
        return False
    if dry:
        print(f"    would set What's New ({len(notes)} chars)")
        return True
    call(f"v1/appStoreVersionLocalizations/{loc['id']}", method="PATCH", body={"data": {
        "type": "appStoreVersionLocalizations", "id": loc["id"],
        "attributes": {"whatsNew": notes}}})
    print("    set What's New")
    return True


def attach(aid, version_id, number, platform, dry):
    b = find_build(aid, number, platform)
    if b is None:
        print(f"    !! build {number} not uploaded for {platform}")
        return False
    state = b["attributes"]["processingState"]
    if state != "VALID":
        # Attaching a build Apple has not finished processing fails with a
        # confusing relationship error rather than "still processing".
        print(f"    !! build {number} is {state}, not VALID — wait and re-run")
        return False
    if dry:
        print(f"    would attach build {number}")
        return True
    call(f"v1/appStoreVersions/{version_id}/relationships/build", method="PATCH",
         body={"data": {"type": "builds", "id": b["id"]}})
    print(f"    attached build {number}")
    return True


def submit(aid, version_id, platform, dry):
    """The three-call flow. See the module docstring for why not the obvious one."""
    open_states = {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "UNRESOLVED_ISSUES"}
    existing = call(f"v1/reviewSubmissions?filter[app]={aid}"
                    f"&filter[platform]={platform}&limit=50")["data"]
    sub = next((r for r in existing if r["attributes"].get("state") in open_states), None)
    if sub and sub["attributes"]["state"] != "READY_FOR_REVIEW":
        print(f"    already {sub['attributes']['state']} — nothing to submit")
        return True
    if dry:
        print("    would submit for review (create submission, add item, PATCH submitted)")
        return True
    if sub is None:
        sub = call("v1/reviewSubmissions", method="POST", body={"data": {
            "type": "reviewSubmissions",
            "attributes": {"platform": platform},
            "relationships": {"app": {"data": {"type": "apps", "id": aid}}}}})["data"]
        print(f"    opened review submission {sub['id']}")
    items = call(f"v1/reviewSubmissions/{sub['id']}/items?limit=50")["data"]
    already = any((i.get("relationships", {}).get("appStoreVersion", {}).get("data") or {})
                  .get("id") == version_id for i in items)
    if not already:
        call("v1/reviewSubmissionItems", method="POST", body={"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sub["id"]}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        print("    added the version as a submission item")
    call(f"v1/reviewSubmissions/{sub['id']}", method="PATCH", body={"data": {
        "type": "reviewSubmissions", "id": sub["id"],
        "attributes": {"submitted": True}}})
    print("    SUBMITTED FOR REVIEW")
    return True


def ship(aid, args):
    mv, bn = repo_version()
    version = args.version or mv
    number = args.build or bn
    notes = args.notes
    if args.notes_file:
        notes = pathlib.Path(args.notes_file).read_text().strip()
    targets = list(PLATFORMS) if args.platform == "all" else [args.platform]
    print(f"shipping {version} (build {number}) to: {', '.join(targets)}"
          + ("   [DRY RUN]" if args.dry_run else "") + "\n")

    failed = []
    for name in targets:
        platform = PLATFORMS[name]
        print(f"  {name}")
        try:
            ver = editable_version(aid, platform, version, args.dry_run)
            if ver is None:
                continue
            ok = attach(aid, ver["id"], number, platform, args.dry_run)
            if notes:
                ok = set_notes(ver["id"], notes, args.locale, args.dry_run) and ok
            if args.release_type and not args.dry_run:
                call(f"v1/appStoreVersions/{ver['id']}", method="PATCH", body={"data": {
                    "type": "appStoreVersions", "id": ver["id"],
                    "attributes": {"releaseType": args.release_type}}})
                print(f"    release type -> {args.release_type}")
            if not ok:
                failed.append(name)
                print("    stopping here for this platform — not submitting an "
                      "incomplete version")
                continue
            if args.submit:
                submit(aid, ver["id"], platform, args.dry_run)
            else:
                print("    prepared; pass --submit to send it for review")
        except ASCError as e:
            failed.append(name)
            print(f"    !! {e}")
    if failed:
        print(f"\nFAILED: {', '.join(failed)}")
        return 1
    print("\nall requested platforms done")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["status", "ship"])
    ap.add_argument("--platform", default="all", choices=["all", *PLATFORMS])
    ap.add_argument("--version", help="App Store version string (default: MARKETING_VERSION)")
    ap.add_argument("--build", help="build number to attach (default: CURRENT_PROJECT_VERSION)")
    ap.add_argument("--notes", help="What's New text")
    ap.add_argument("--notes-file", help="read What's New from a file")
    ap.add_argument("--locale", default="en-US")
    ap.add_argument("--release-type", choices=["AFTER_APPROVAL", "MANUAL", "SCHEDULED"])
    ap.add_argument("--submit", action="store_true",
                    help="actually send for review (without it the version is only prepared)")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    for var in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
        if not os.environ.get(var):
            sys.exit(f"set {var} (see tools/asc-credentials.env)")

    aid = app_id()
    return status(aid) if a.mode == "status" else ship(aid, a)


if __name__ == "__main__":
    sys.exit(main())
