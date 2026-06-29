# Getting a Google Play Developer API service-account JSON key (June 2026)

This is the one piece `tools/submit-play.sh` needs. Earlier walkthroughs tend to fail for **one
specific reason in 2026**: a Google Cloud *organization policy* now silently blocks JSON-key
creation. This guide gives the happy path first, then fixes that block head-on.

> **The 2026 simplification:** you **no longer need to "link" your Play developer account to a Google
> Cloud project**. Google's own docs now say: *"You no longer need to link your developer account to a
> Google Cloud Project in order to access the Google Play Developer API."* Old guides that hinge on the
> "API access → link project" dance are out of date — ignore that step. You just need (a) a service
> account with a JSON key, and (b) that service account invited into Play Console with permissions.

End state we want:
- a service-account JSON key saved at **`~/.config/play/archivewatch-play.json`**
- that service account **invited in Play Console** with release permission for **com.archivewatch.app**

---

## Part A — Create the service account + JSON key (Google Cloud Console)

1. Go to **console.cloud.google.com**. Top bar → **project picker** → **New Project** (name it e.g.
   `archivewatch-play`). Use the project picker to make sure it's *selected* afterward.
   - *If your Google login is a plain Gmail with no Workspace/organization, the project is created
     "No organization" — and key creation will just work (skip Part C).*

2. Enable the API: open
   **https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com**, confirm the
   right project is selected, click **Enable**.

3. Create the service account: **IAM & Admin → Service Accounts → + Create service account**.
   - Name: `archivewatch-ci` (anything).
   - **Skip** the "Grant this service account access to project" (roles) step — Play permissions are
     granted later in Play Console, not here. Click **Done**.

4. Create the key: in the Service Accounts list, click your new account → **Keys** tab (or Actions ⋮ →
   **Manage keys**) → **Add key → Create new key → JSON → Create**. The `.json` downloads.
   - **You cannot re-download a key.** If lost, just create another.
   - ➡️ **If this step is greyed out or errors "Service account key creation is disabled," go to
     Part C — that's the 2026 blocker.**

5. Move it out of Downloads into the expected location:
   ```bash
   mkdir -p ~/.config/play
   mv ~/Downloads/archivewatch-play-*.json ~/.config/play/archivewatch-play.json
   chmod 600 ~/.config/play/archivewatch-play.json
   ```

---

## Part B — Invite the service account in Play Console

1. Copy the service account's **email** (looks like
   `archivewatch-ci@archivewatch-play.iam.gserviceaccount.com`) — it's on the Service Accounts page.
2. **Play Console → Users and permissions → Invite new users.** Paste the email.
3. **App permissions** tab → **Add app** → select **Archive Watch** → grant at least:
   - **Release to production, exclude devices, and use Play App Signing** (this covers production
     releases), and
   - **Release apps to testing tracks** (for internal/closed if you ever use them).
   You can instead grant these as *account* permissions; app-scoped is tighter.
4. **Invite user.** Permissions can take a few minutes to propagate before the API accepts a release.

> Only the **Play Console account owner** sees Users-and-permissions / can grant API access. If you
> don't see it, you're not signed in as the developer-account owner.

---

## Part C — If the JSON key won't generate (the usual 2026 failure)

This happens when your Google account belongs to a **Workspace / Cloud organization** that enforces a
policy against downloadable keys. Two constraints exist and **both** must be off, because Google is
mid-migration and evaluates the legacy *and* the managed one:

- legacy: `constraints/iam.disableServiceAccountKeyCreation`
- managed: `constraints/iam.managed.disableServiceAccountKeyCreation`

You need the **Organization Policy Administrator** role at the **organization** level (Project Owner is
*not* enough). Then:

1. **console.cloud.google.com → IAM & Admin → Organization policies** (switch the resource scope at the
   top to your **organization**, or to the specific project).
2. Search **`disableServiceAccountKeyCreation`**. Open it → **Manage policy** → set enforcement to
   **Off** (or, scoped to just this project, add a rule that turns it off for the project). **Repeat for
   the `iam.managed.…` one.** Save.
3. Back in Part A step 4, create the key — it now works.

**Per-service-account exemption (if you can't flip the whole policy):** attach the tag
`disableServiceAccountKeyCreation = not_enforced` to the service account, which overrides the inherited
org value for just that account.

**Easiest escape hatch:** create the project under a **personal Gmail with no organization** (a brand
new free Google account works). No org → no policy → key creation just works. The service account from
*any* project can be invited into the Play Console; they don't have to be the same Google identity.

---

## Part D — gcloud CLI alternative (bypasses Console UI quirks)

Same result, fewer clicks — and handy if the web UI misbehaves. (It's still subject to Part C's org
policy.) Install once: `brew install --cask google-cloud-sdk`, then in a terminal **you** run:

```bash
gcloud auth login                                   # opens a browser; sign in as the developer
PROJECT=archivewatch-play
gcloud projects create $PROJECT 2>/dev/null || true
gcloud config set project $PROJECT
gcloud services enable androidpublisher.googleapis.com
gcloud iam service-accounts create archivewatch-ci --display-name "Archive Watch CI"
SA=archivewatch-ci@$PROJECT.iam.gserviceaccount.com
mkdir -p ~/.config/play
gcloud iam service-accounts keys create ~/.config/play/archivewatch-play.json --iam-account $SA
chmod 600 ~/.config/play/archivewatch-play.json
echo "Service account email to invite in Play Console: $SA"
```

Then do **Part B** (invite `$SA` in Play Console). If the last command errors
`FAILED_PRECONDITION … key creation is not allowed`, that's the org policy → **Part C**.

> Tip: you can run any of these from this chat by prefixing with `!` (e.g. `! gcloud auth login`), so
> the output lands here and I can take it from there.

---

## Part E — Verify + first release

Once the JSON is at `~/.config/play/archivewatch-play.json` and the SA is invited, I (or you) can run:

```bash
tools/submit-play.sh --track production --notes "…"     # bumps versionCode, builds the AAB, uploads
```

A zero-cost connectivity check before a real release (lists tracks; proves the key + permissions work):

```bash
python3 - <<'PY'
from google.oauth2 import service_account
from googleapiclient.discovery import build
c=service_account.Credentials.from_service_account_file(
  __import__('os').path.expanduser('~/.config/play/archivewatch-play.json'),
  scopes=['https://www.googleapis.com/auth/androidpublisher'])
s=build('androidpublisher','v3',credentials=c,cache_discovery=False)
e=s.edits().insert(packageName='com.archivewatch.app',body={}).execute()
print('OK — API + permissions work. edit id', e['id'])
PY
```
(That needs the libs from `tools/.play-venv`; `tools/submit-play.sh` creates that venv, or
`pip install google-api-python-client google-auth`.)

---

### Sources (verified June 2026)
- Google for Developers — Google Play Developer API, *Getting Started* (the "no longer need to link"
  statement + invite-in-Play-Console permissions): https://developers.google.com/android-publisher/getting_started
- ASO.dev — Google Play service-account JSON key guide (current Console click-path):
  https://aso.dev/google-play/service-account/
- Google Cloud IAM docs — disable/enable service account keys & org-policy troubleshooting:
  https://docs.cloud.google.com/iam/docs/keys-disable-enable ,
  https://docs.cloud.google.com/iam/docs/troubleshoot-org-policies
- On enforcing/disabling the key-creation constraints (legacy + managed):
  https://oneuptime.com/blog/post/2026-02-17-how-to-enforce-service-account-key-creation-restrictions-with-organization-policies/view
