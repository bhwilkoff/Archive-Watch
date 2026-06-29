#!/usr/bin/env python3
"""Upload a signed Android App Bundle to Google Play and create a release on a track, via the Google
Play Developer API v3 — no Android Studio, no manual upload (the Play analog of the App Store
tools/asc_*.py scripts). Uses the "edits" transaction: insert an edit, upload the .aab, point a track
at the new versionCode with release notes, then commit.

Usage:  play-publish.py <app-release.aab> [--track production|internal|alpha|beta]
                        [--notes "release notes"] [--rollout 0.1] [--draft]
Env:    PLAY_SERVICE_ACCOUNT_JSON  path to the service-account JSON key
                                   (default ~/.config/play/archivewatch-play.json)
        PLAY_PACKAGE               package name (default com.archivewatch.app)

The service account must be granted release permissions for the app in Play Console
(Users and permissions). The JSON key belongs in NO git repo — keep it under ~/.config/play.
Requires: google-api-python-client, google-auth (tools/submit-play.sh installs them into a venv).
"""
import sys, os, argparse

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("aab")
    ap.add_argument("--track", default="production")
    ap.add_argument("--notes", default=None, help="release notes (en-US); or @path to read a file")
    ap.add_argument("--rollout", type=float, default=None, help="staged rollout fraction 0<f<1 (else full)")
    ap.add_argument("--draft", action="store_true", help="create the release as a draft (not live)")
    args = ap.parse_args()

    pkg = os.environ.get("PLAY_PACKAGE", "com.archivewatch.app")
    key = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON",
                         os.path.expanduser("~/.config/play/archivewatch-play.json"))
    if not os.path.isfile(args.aab):
        raise SystemExit(f"AAB not found: {args.aab}")
    if not os.path.isfile(key):
        raise SystemExit(f"Service-account JSON not found: {key}\n"
                         f"Set PLAY_SERVICE_ACCOUNT_JSON or place it at ~/.config/play/archivewatch-play.json")

    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from googleapiclient.errors import HttpError

    creds = service_account.Credentials.from_service_account_file(
        key, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edits = service.edits()

    notes = args.notes
    if notes and notes.startswith("@"):
        notes = open(os.path.expanduser(notes[1:])).read().strip()

    try:
        edit_id = edits.insert(body={}, packageName=pkg).execute()["id"]
        print(f"edit {edit_id} opened for {pkg}")

        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True)
        up = edits.bundles().upload(packageName=pkg, editId=edit_id, media_body=media).execute()
        vc = up["versionCode"]
        print(f"uploaded AAB → versionCode {vc}")

        status = "draft" if args.draft else ("inProgress" if args.rollout else "completed")
        release = {"versionCodes": [str(vc)], "status": status}
        if args.rollout and not args.draft:
            release["userFraction"] = args.rollout
        if notes:
            release["releaseNotes"] = [{"language": "en-US", "text": notes}]

        edits.tracks().update(packageName=pkg, editId=edit_id, track=args.track,
                              body={"track": args.track, "releases": [release]}).execute()
        print(f"track '{args.track}' → versionCode {vc} ({status}"
              + (f", rollout {args.rollout}" if args.rollout and not args.draft else "") + ")")

        edits.commit(packageName=pkg, editId=edit_id).execute()
        print(f"✓ committed. versionCode {vc} is now '{status}' on the '{args.track}' track"
              + ("" if args.draft else " — Play review then rollout.") )
    except HttpError as e:
        raise SystemExit(f"Play API error: {e.status_code if hasattr(e,'status_code') else ''} {e}")

if __name__ == "__main__":
    main()
