#!/usr/bin/env python3
"""Publish an Archive Watch update to the Amazon Appstore (Fire TV) via the API.

    python3 tools/submit-amazon.py --check                  # can we authenticate yet?
    python3 tools/submit-amazon.py --apk path/to.apk        # upload, leave edit OPEN
    python3 tools/submit-amazon.py --apk path/to.apk --commit   # upload AND submit

RESOLVED 2026-09-09 — it was ONE missing mapping, not a permission
  For five weeks every scope answered `invalid_scope` and this file concluded the
  account could not reach the API. That was wrong, and the wrong conclusion was
  the expensive part: it said "Do NOT re-walk the console nav", so nobody looked
  again.

  The cause: **My Settings > API Access** (developer.amazon.com/apps-and-games/
  console/api-access/home.html) read "No Security Profile Attached" for BOTH the
  App Submission API and the Reporting API. A security profile has to be MAPPED
  to each API; creating one and enabling Login with Amazon is not enough. Two
  clicks — select the existing profile, Attach — and both scopes were granted
  immediately:

      adx_reporting::appstore:marketer   GRANTED   (Vitals / Reporting)
      appstore::apps:readwrite           GRANTED   (this tool)
      --check                            auth OK for amzn1.devportal.mobileapp...

  WHAT WAS DISPROVEN ALONG THE WAY, so nobody re-walks it:
    * "The API Access page does not exist in this console." It does, under
      My Settings > Enterprise Security Features. Two earlier walks missed it.
    * "The page appears once the app is LIVE." The app went live 2026-09-01 and
      the scope was still refused; going live was never the gate.
    * "/settings/console/apiaccess" — genuinely 404s. The real paths are
      /apps-and-games/console/api-access/home.html (mapping) and
      /reporting/console/appstore/apiaccess (the Vitals API Explorer).

  A support case is NOT needed and never was.

CONSTRAINTS THAT SHAPED THIS TOOL
  * APK only. The App Submission API does NOT accept App Bundles, which is why
    the Amazon flavor ships an APK while Play gets an AAB.
  * Edits are staged: create -> upload -> (commit). Without --commit the edit
    is left OPEN so it can be eyeballed in the console first. That default is
    deliberate: this code path has never been exercised against the live API,
    because the scope has never been granted.

Credentials live OUTSIDE the repo at ~/.config/amazon/appstore.json (chmod 600),
the same pattern as the Play service account and the ASC key. Never commit them.
"""

# THE PUBLIC LISTING URL. Archive Watch is live as ASIN B0HHBW6X29, so
# https://www.amazon.com/dp/B0HHBW6X29 is the canonical page. Link to
# https://www.amazon.com/gp/mas/dl/android?p=com.archivewatch.app instead: it
# resolves to the same listing, survives an ASIN change, and on a Fire device
# opens the Appstore app rather than a web page. Neither URL appears anywhere
# in the developer console -- it is derived from the package name, which is why
# the console is the wrong place to go looking for it.

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

CRED = os.environ.get("AMAZON_APPSTORE_JSON",
                      os.path.expanduser("~/.config/amazon/appstore.json"))
API = "https://developer.amazon.com/api/appstore/v1"


def creds():
    try:
        return json.load(open(CRED))
    except OSError:
        sys.exit(f"No credentials at {CRED}. See the docstring.")


def token(c):
    data = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": c["client_id"],
        "client_secret": c["client_secret"],
        "scope": "appstore::apps:readwrite",
    }).encode()
    req = urllib.request.Request(
        "https://api.amazon.com/auth/o2/token", data=data,
        headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=40))["access_token"]
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if "invalid_scope" in body:
            sys.exit(
                "invalid_scope — this account still cannot reach the App Submission API.\n"
                "  Everything on our side is already done (Admin owner, security profile,\n"
                "  Login with Amazon enabled). The app was still awaiting review as of\n"
                "  2026-08-31; re-run this once it is LIVE. See the docstring for why.")
        sys.exit(f"token failed: HTTP {e.code} {body[:300]}")


def call(tok, method, path, body=None, ctype="application/json", etag=None):
    """One authenticated API call. Returns (json_or_bytes, etag)."""
    url = f"{API}{path}"
    headers = {"Authorization": f"Bearer {tok}", "Accept": "application/json"}
    if body is not None:
        headers["Content-Type"] = ctype
    if etag:
        headers["If-Match"] = etag
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=600)
        raw = r.read()
        tag = r.headers.get("ETag")
        try:
            return json.loads(raw), tag
        except ValueError:
            return raw, tag
    except urllib.error.HTTPError as e:
        sys.exit(f"{method} {path} -> HTTP {e.code}: {e.read().decode()[:400]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify auth and stop")
    ap.add_argument("--apk", help="APK to upload as a new version")
    ap.add_argument("--commit", action="store_true",
                    help="submit the edit for review (default: leave it open)")
    a = ap.parse_args()

    c = creds()
    app = c["app_id"]
    tok = token(c)
    print(f"auth OK for {app}")
    if a.check or not a.apk:
        if not a.apk and not a.check:
            print("nothing to do — pass --apk to upload a build")
        return 0
    if not os.path.exists(a.apk):
        sys.exit(f"no such APK: {a.apk}")
    if a.apk.endswith(".aab"):
        sys.exit("App Bundles are not supported by this API — build the APK "
                 "(./gradlew assembleAmazonRelease).")

    # A binary that the Appstore would hide from Fire OS 7 must never be
    # uploaded. On 2026-09-10 the LIVE build was minSdk 29 — "Fire TV (98):
    # 38 selected" in the console — and users reported every one of their
    # devices as incompatible. The fix existed, unuploaded, for five weeks.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from audit_fire_tv_manifest import audit as fire_tv_audit
    try:
        findings = fire_tv_audit(a.apk)
    except RuntimeError as e:
        sys.exit(f"cannot audit the APK, so it does not ship: {e}")
    if findings:
        print("refusing to upload — this build would lose Fire TV devices:",
              file=sys.stderr)
        for f in findings:
            print(f"  - {f}", file=sys.stderr)
        sys.exit(1)
    print("fire-tv manifest audit: OK")

    edit, _ = call(tok, "POST", f"/applications/{app}/edits")
    eid = edit.get("id") if isinstance(edit, dict) else None
    if not eid:
        sys.exit(f"could not read an edit id from: {str(edit)[:200]}")
    print(f"edit {eid} opened")

    with open(a.apk, "rb") as f:
        blob = f.read()
    print(f"uploading {os.path.basename(a.apk)} ({len(blob) // 1024 // 1024} MB) …")
    up, _ = call(tok, "POST", f"/applications/{app}/edits/{eid}/apks/upload",
                 body=blob, ctype="application/octet-stream")
    print(f"uploaded: {str(up)[:160]}")

    if not a.commit:
        print(f"\nedit {eid} left OPEN — review it in the console, then re-run "
              f"with --commit, or commit it there.")
        return 0

    # The commit is conditional on the edit's current ETag; fetch it fresh so we
    # can never commit a version of the edit we did not just build.
    _, tag = call(tok, "GET", f"/applications/{app}/edits/{eid}")
    call(tok, "POST", f"/applications/{app}/edits/{eid}/commit", body=b"", etag=tag)
    print(f"edit {eid} COMMITTED — Amazon review begins.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
