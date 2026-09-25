#!/usr/bin/env python3
"""Upload one video to the Archive Watch YouTube channel as UNLISTED.

For store-review evidence — Play's foreground-service declaration, Google's
OAuth verification — which wants a YouTube link a reviewer can open and the
public never sees. It uses the social program's upload credentials
(YOUTUBE_CLIENT_ID / _SECRET / _REFRESH_TOKEN, repo secrets only), so it runs
in CI: .github/workflows/youtube-unlisted-upload.yml.

    python tools/youtube_upload_unlisted.py VIDEO.mp4 --title "..." [--description "..."]
Prints the watch URL.
"""
import argparse
import datetime as dt
import json
import os
import sys
import urllib.parse
import urllib.request


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("--title", required=True)
    ap.add_argument("--description", default="")
    a = ap.parse_args()
    cid, secret, refresh = (os.environ.get(k) for k in
                            ("YOUTUBE_CLIENT_ID", "YOUTUBE_CLIENT_SECRET", "YOUTUBE_REFRESH_TOKEN"))
    if not (cid and secret and refresh):
        sys.exit("YouTube credentials are not set")
    tok = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=urllib.parse.urlencode({"client_id": cid, "client_secret": secret,
                                     "refresh_token": refresh,
                                     "grant_type": "refresh_token"}).encode()),
        timeout=60).read())
    meta = {"snippet": {"title": a.title[:100], "description": a.description[:4900],
                        "categoryId": "28"},
            "status": {"privacyStatus": "unlisted", "selfDeclaredMadeForKids": False}}
    boundary = "aw-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S%f")
    body = (f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
            f"{json.dumps(meta)}\r\n--{boundary}\r\nContent-Type: video/mp4\r\n\r\n").encode() \
        + open(a.video, "rb").read() + f"\r\n--{boundary}--\r\n".encode()
    res = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=multipart&part=snippet,status",
        data=body, headers={"Authorization": f"Bearer {tok['access_token']}",
                            "Content-Type": f"multipart/related; boundary={boundary}"}),
        timeout=900).read())
    status = res.get("status", {}).get("privacyStatus")
    if status != "unlisted":
        sys.exit(f"uploaded {res.get('id')} but privacy is {status!r}, not unlisted")
    print(f"https://youtu.be/{res['id']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
