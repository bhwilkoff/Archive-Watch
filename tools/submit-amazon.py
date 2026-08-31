#!/usr/bin/env python3
"""Submit an Archive Watch build to the Amazon Appstore from the command line.

STATUS (2026-08-31): the credentials exist and are wired, but Amazon has NOT
granted this developer account the App Submission API scope, so every call
below fails at the token step with `invalid_scope`. Run it to see exactly where
you stand; the fix is an account entitlement, not code — see OWNER STEP.

    python3 tools/submit-amazon.py --check          # auth only
    python3 tools/submit-amazon.py --apk path.apk   # once access is granted

OWNER STEP (one-time, ~2 minutes, then this script works forever):
  Amazon's docs say to attach the security profile at
  "Tools & Services > API Access" in the Developer Console. That page does NOT
  exist in this account's console — Publish, Develop and My Settings were all
  checked on 2026-08-31, and /settings/console/apiaccess/overview.html 404s.
  So open a developer support case ("Contact Us" in the console) and ask:

      "Please enable Amazon App Submission API access for security profile
       'Archive Watch Appstore Submission'
       (amzn1.application.1ae9e1cdfaf243729f9a72e2913ff2c3) so it can obtain
       the appstore::apps:readwrite scope. App: Archive Watch,
       amzn1.devportal.mobileapp.05436508d304458ea47ef31dca23b1b6"

Credentials live OUTSIDE the repo at ~/.config/amazon/appstore.json (chmod 600),
the same pattern as the Play service account and the ASC key. Never commit them.
"""
import argparse, json, os, sys, urllib.parse, urllib.request, urllib.error

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
        "grant_type": "client_credentials", "client_id": c["client_id"],
        "client_secret": c["client_secret"], "scope": "appstore::apps:readwrite",
    }).encode()
    req = urllib.request.Request("https://api.amazon.com/auth/o2/token", data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=40))["access_token"]
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        if "invalid_scope" in body:
            sys.exit("invalid_scope — the security profile is not attached to the App "
                     "Submission API yet. See OWNER STEP in this file's docstring.")
        sys.exit(f"token failed: HTTP {e.code} {body[:300]}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="verify auth only")
    ap.add_argument("--apk", help="APK to upload as a new edit")
    a = ap.parse_args()
    c = creds()
    t = token(c)
    print(f"auth OK (token {len(t)} chars) for app {c['app_id']}")
    if a.check or not a.apk:
        return 0
    # Deliberately not implemented past auth: it has never been reachable, and
    # an untested upload path is worse than none. Fill in edits/apks/commit
    # against the live API once access is granted.
    print("Access is granted — implement the edit/upload/commit calls against "
          f"{API}/applications/{c['app_id']}/edits")
    return 0


if __name__ == "__main__":
    sys.exit(main())
