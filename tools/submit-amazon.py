#!/usr/bin/env python3
"""Publish an Archive Watch update to the Amazon Appstore (Fire TV) via the API.

    python3 tools/submit-amazon.py --check                  # can we authenticate yet?
    python3 tools/submit-amazon.py --apk path/to.apk        # upload, leave edit OPEN
    python3 tools/submit-amazon.py --apk path/to.apk --commit   # upload AND submit

WHY IT MAY NOT WORK YET (read before filing a support case)
  The token call returns `invalid_scope` until this developer account can reach
  the App Submission API. As of 2026-08-31 every prerequisite on our side is
  satisfied and the API is still refusing:

      account role .......... Administrator (owner)          [checked]
      security profile ...... Archive Watch Appstore Submission
                              amzn1.application.1ae9e1cdfaf243729f9a72e2913ff2c3
      Login with Amazon ..... ENABLED, consent notice =
                              https://archivewatch.org/privacy.html
      app ................... SUBMITTED 2026-08-31, NOT YET LIVE (no ASIN)

  Amazon's docs name an "API Access" page three different ways (Tools &
  Services / Apps & Services / My Settings). None of them exists in this
  console. Walked on 2026-08-31: the settings nav (My Account, Company
  Profile, Payments, Tax Identity, User Permissions, Identity, Security
  Profiles, Activity Log), the whole Appstore nav (My Apps, My Appstore
  Cases, My Reports, My Settings, Tools & Services > Develop/Test/Publish/
  Monetize, Connect), the app's App Services page, and the "..." menu
  (Support / Contact Us / My Cases). /settings/console/apiaccess and
  .../overview.html both 404.

  BEST-SUPPORTED EXPLANATION: the page appears once the app is LIVE. Two
  pieces of evidence, not a guess:
    1. This console demonstrably gates features on the app having an ASIN —
       App Services says verbatim "SSI cannot be enabled because the ASIN has
       not been generated yet. Submit the app to generate the ASIN."
    2. The API docs say "You need to submit the first version of your app
       using the Developer Console", i.e. the API only ever creates NEW
       versions of an app that already exists in the store.

  So: re-run `--check` after the app goes live (estimated 2026-09-05). If it
  authenticates, everything below is ready and Fire TV releases stop being
  manual. Only if it STILL fails once the app is live is a support case worth
  opening — the wording is in docs/mac-app-store-submission.md's sibling notes
  and in the git history for this file.

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
