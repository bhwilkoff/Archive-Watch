#!/usr/bin/env python3
"""
play_promote.py — move a build that already exists on Play to another track.

The point is that NO BUILD HAPPENS. `play-release.yml` publishes to the internal
track, a person installs it from Play on a real device and uses it, and then the
SAME artifact is promoted. Rebuilding to promote would defeat the whole guard:
the thing that reached users would not be the thing that was tested.

    python3 tools/play_promote.py --version-code 57 --to production
    python3 tools/play_promote.py --version-code 57 --to production --rollout 0.2
"""
from __future__ import annotations

import argparse
import os
import sys

PACKAGE = "com.archivewatch.app"


def service():
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/archivewatch-play.json"))
    if not os.path.exists(key):
        sys.exit(f"no Play service-account key at {key}")
    creds = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return build("androidpublisher", "v3", credentials=creds, cache_discovery=False)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--version-code", required=True)
    ap.add_argument("--to", default="production")
    ap.add_argument("--rollout", type=float, default=None,
                    help="staged fraction 0<f<1; omit for a full release")
    ap.add_argument("--notes", default=None)
    a = ap.parse_args()

    svc = service()
    vc = str(int(a.version_code))

    edit = svc.edits().insert(packageName=PACKAGE, body={}).execute()
    eid = edit["id"]
    try:
        # The build must ALREADY be on a track. Promoting a versionCode Play has
        # never seen fails deep inside the commit with an unhelpful message, so
        # check here where the error can name the actual problem.
        tracks = svc.edits().tracks().list(packageName=PACKAGE, editId=eid).execute()
        found = None
        for t in tracks.get("tracks", []):
            for rel in t.get("releases", []):
                if vc in [str(c) for c in (rel.get("versionCodes") or [])]:
                    found = (t["track"], rel)
        if not found:
            have = {t["track"]: [c for r in t.get("releases", [])
                                 for c in (r.get("versionCodes") or [])]
                    for t in tracks.get("tracks", [])}
            sys.exit(f"versionCode {vc} is not on any track. Present: {have}")
        from_track, rel = found
        if from_track == a.to:
            print(f"versionCode {vc} is already on '{a.to}' — nothing to do")
            return 0

        release = {"versionCodes": [vc],
                   "status": "inProgress" if a.rollout else "completed"}
        if a.rollout:
            release["userFraction"] = a.rollout
        # Carry the notes forward rather than dropping them: the release the
        # testers approved said something, and users should see the same words.
        notes = rel.get("releaseNotes")
        if a.notes:
            release["releaseNotes"] = [{"language": "en-US", "text": a.notes}]
        elif notes:
            release["releaseNotes"] = notes
        if rel.get("name"):
            release["name"] = rel["name"]

        svc.edits().tracks().update(packageName=PACKAGE, editId=eid, track=a.to,
                                    body={"track": a.to, "releases": [release]}).execute()
        svc.edits().commit(packageName=PACKAGE, editId=eid).execute()
        eid = None
        print(f"promoted versionCode {vc}: {from_track} -> {a.to}"
              + (f" at {a.rollout:.0%}" if a.rollout else " (full)"))
    finally:
        if eid:
            try:
                svc.edits().delete(packageName=PACKAGE, editId=eid).execute()
            except Exception:                        # noqa: BLE001
                pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
