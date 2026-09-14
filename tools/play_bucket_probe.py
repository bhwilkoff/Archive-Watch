#!/usr/bin/env python3
"""What is ACTUALLY in the Play reports bucket, and when was it last written?

Pulse reported Play installs as "stale by 24 days" and a previous session
labelled the export "broken". Neither was measured — both were inferred from
the newest ROW in a CSV, which cannot tell the difference between:

  * Google no longer writing the object,
  * Google writing it with rows we do not parse,
  * the object having moved or been renamed,
  * us reading the wrong months.

Those have different fixes and one of them is not a fix at all. So: list the
objects, print their names, sizes and updated timestamps, and let the bucket
answer. The bucket name is a repo secret, which is why this runs in CI.

    python3 tools/play_bucket_probe.py            # needs PLAY_REPORTS_BUCKET
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
import urllib.request

PKG = "com.archivewatch.app"


def token():
    from google.oauth2 import service_account
    import google.auth.transport.requests as gtr
    raw = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON", "")
    if raw.strip().startswith("{"):
        info = json.loads(raw)
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/devstorage.read_only"])
    else:
        creds = service_account.Credentials.from_service_account_file(
            os.path.expanduser(raw or "~/.config/play/archivewatch-play.json"),
            scopes=["https://www.googleapis.com/auth/devstorage.read_only"])
    creds.refresh(gtr.Request())
    return creds.token


def main() -> int:
    bucket = os.environ.get("PLAY_REPORTS_BUCKET", "").strip()
    bucket = bucket.replace("gs://", "").strip("/").split("/")[0]
    if not bucket:
        print("no PLAY_REPORTS_BUCKET in this environment")
        return 1
    tok = token()
    # Print a REDACTED bucket name: its id is a secret, its CONTENTS are the
    # question. A probe that leaks the thing it was given is not worth running.
    print(f"bucket: {bucket[:14]}… ({len(bucket)} chars)")

    for prefix in ("stats/installs/", "stats/ratings/", "stats/crashes/", "stats/"):
        objs, page = [], None
        while True:
            q = {"prefix": prefix, "maxResults": "1000"}
            if page:
                q["pageToken"] = page
            url = (f"https://storage.googleapis.com/storage/v1/b/"
                   f"{urllib.parse.quote(bucket)}/o?{urllib.parse.urlencode(q)}")
            req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
            try:
                d = json.load(urllib.request.urlopen(req, timeout=60))
            except Exception as e:                                   # noqa: BLE001
                print(f"\n{prefix}  COULD NOT LIST: {str(e)[:160]}")
                break
            objs.extend(d.get("items", []))
            page = d.get("nextPageToken")
            if not page:
                break
        if not objs:
            continue
        print(f"\n=== {prefix}  {len(objs)} object(s)")
        # Newest first by update time: the question is what STOPPED.
        for o in sorted(objs, key=lambda x: x.get("updated", ""), reverse=True)[:25]:
            name = o["name"].rsplit("/", 1)[-1]
            print(f"  {o.get('updated','?')[:19]}  {int(o.get('size',0)):>9}  {name}")
        if prefix == "stats/":
            kinds = sorted({o["name"].split("/")[1] for o in objs if o["name"].count("/") > 1})
            print(f"  report kinds present: {kinds}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
