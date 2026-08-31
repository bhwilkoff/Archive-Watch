"""Submit an Archive Watch build to the Amazon Appstore from the command line.

STATUS (2026-08-31): credentials exist and LWA is enabled, but Amazon has not
granted this account the App Submission API scope, so the token call still
fails `invalid_scope`. The remaining step is not code — see OWNER STEP.

    python3 tools/submit-amazon.py --check          # auth only
    python3 tools/submit-amazon.py --apk path.apk   # once access is granted

WHAT THE API CAN AND CANNOT DO (docs, 2026-08-31)
  * Android APKs ONLY. **AAB is not supported** — which is why the Amazon
    flavor ships an APK while Play gets a bundle.
  * It manages NEW VERSIONS of an EXISTING app: "You need to submit the first
    version of your app using the Developer Console." That first submission
    happened 2026-08-31, so every future Fire TV update is API-eligible.
  * Endpoints, once authorized:
      POST {API}/applications/{appId}/edits
      POST {API}/applications/{appId}/edits/{editId}/apks/upload
      POST {API}/applications/{appId}/edits/{editId}/commit

SETUP DONE HERE
  1. Security profile "Archive Watch Appstore Submission" created
     (amzn1.application.1ae9e1cdfaf243729f9a72e2913ff2c3).
  2. Login with Amazon ENABLED for it, with the consent privacy notice URL
     https://archivewatch.org/privacy.html — this step was genuinely missing
     and is easy to skip, but on its own it does NOT grant the scope.

OWNER STEP (the only thing left)
  Amazon's docs say to attach the profile at "API Access" — variously
  documented as "Tools & Services > API Access", "Apps & Services > API
  Access" and "My Settings > API Access". **No such page exists in this
  account.** Walked on 2026-08-31: the settings nav (My Account, Company
  Profile, Payments, Tax Identity, User Permissions, Identity, Security
  Profiles, Activity Log), the Appstore console nav (My Apps, My Appstore
  Cases, My Reports, My Settings, Tools & Services > Develop/Test/Publish/
  Monetize, Connect), and the app's own App Services page (SSI, Real-Time
  Notifications, Maps). /settings/console/apiaccess and .../overview.html
  both 404.

  So open a developer support case (console > Contact Us) asking:

      "Please enable Amazon App Submission API access for security profile
       'Archive Watch Appstore Submission'
       (amzn1.application.1ae9e1cdfaf243729f9a72e2913ff2c3) so it can obtain
       the appstore::apps:readwrite scope. Login with Amazon is already
       enabled for this profile. The API Access page described in your docs
       does not appear anywhere in my console.
       App: Archive Watch, amzn1.devportal.mobileapp.05436508d304458ea47ef31dca23b1b6"

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
