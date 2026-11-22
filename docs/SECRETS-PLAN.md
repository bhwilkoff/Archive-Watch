# Secrets plan (Decision 186)

Owner, 2026-11-22: *"I do not want to set or keep track of keys and passwords for this repo."* The pattern is Ear
Drama's (`Ear-Drama/docs/research/SECRETS-PLAN.md`, its Decision 085). Names and places only; no value is written here.

## The rule

A secret exists in one place. CI: a GitHub Actions secret. A person's Mac: the login Keychain (`archivewatch:NAME`).
`tools/secrets.sh` is the only thing that moves a value, through a pipe, never on a command line or in a file.
`tools/test_no_secrets.py` (pre-commit and `secrets-check.yml`) fails on anything tracked that looks like one.

## Inventory

| Credential | Guards | Who needs it | Home now |
|---|---|---|---|
| `TAKEDOWN_TOKEN` (GitHub, Worker, `~/.config/archivewatch/takedown.env`) | the take-down case routes | CI check only | **gone**: GitHub OIDC token of `takedown-check.yml` |
| `INGEST_TOKEN` Worker / `PULSE_INGEST_TOKEN` GitHub / `~/.config/archivewatch/pulse-ingest.env` | Roku report drop box and the collector's read | Roku's delivery URL, `pulse.yml` | stays (a URL we do not control); file goes to Keychain `PULSE_INGEST_ENV` |
| `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `APPLE_DIST_P12`, `APPLE_INSTALLER_P12`, `APPLE_P12_PASSWORD`, `APPLE_DIST_CERT_ID` (GitHub) | App Store builds and submits | CI | GitHub only |
| `ASC_REPORTS_KEY_P8`, `ASC_REPORTS_KEY_ID`, `ASC_VENDOR_NUMBER` (GitHub) | Apple sales reports | `pulse.yml` | GitHub only |
| `~/.appstoreconnect/private_keys/AuthKey_G5549XF8RV.p8`, `tools/asc-credentials.env` | the same API key, locally | owner's Mac tools | Keychain `ASC_KEY_P8`, `ASC_KEY_ID`, `ASC_ISSUER_ID` via `tools/with_asc.sh` |
| `~/.appstoreconnect/private_keys/aw-ci-*.p12`, `aw-ci-p12.password`, `aw-ci-README.txt` | the CI signing certs (copies of the GitHub secrets) | nobody | Trash; `renew-signing` makes new ones |
| `PLAY_SERVICE_ACCOUNT_JSON`, `PLAY_REPORTS_BUCKET` (GitHub), `~/.config/play/archivewatch-play.json` | Play publish and reports | CI, local tools; **shared with Ear Drama** | GitHub; file to Keychain `PLAY_SERVICE_ACCOUNT_JSON`; phase 2 below |
| `UPLOAD_KEYSTORE_B64`, `UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_ALIAS`, `UPLOAD_KEY_PASSWORD` (GitHub), `~/keystores/archivewatch-upload.jks` | Android upload signing | CI (`play-release.yml`) | GitHub; the file is a backup, to Keychain `UPLOAD_KEYSTORE` |
| `AMAZON_APP_ID`, `AMAZON_CLIENT_ID`, `AMAZON_CLIENT_SECRET` (GitHub), `~/.config/amazon/appstore.json` | Amazon Appstore | CI, `submit-amazon.py` | GitHub; file to Keychain `AMAZON_APPSTORE_JSON` |
| `~/.config/roku/signing.env`, `~/keystores/roku-signing-key.txt`, `roku-genkey.raw` | Roku channel signing (never regenerate) | `roku_package.py` | Keychain `ROKU_SIGNING_ENV`, `ROKU_SIGNING_KEY`, `ROKU_GENKEY_RAW` |
| `secrets/tizen-certificate/*.p12` (gitignored), `~/.config/tizen` | Samsung signing (cannot be reissued) | owner | Keychain `TIZEN_AUTHOR_P12`, `TIZEN_DISTRIBUTOR_P12` |
| `tools/subtitle_keys.env` | SubDL, SubSource | `free_subtitles.py` | Keychain `SUBTITLE_KEYS_ENV` |
| `SUBDL_API_KEY`, `SUBSOURCE_API_KEY`, `OPENSUBTITLES_API_KEY`, `AW_OPENSUBTITLES_API_KEY`, `OMDB_KEY`, `THETVDB_API_KEY`, `TMDB_BEARER_TOKEN`, `IAS3_ACCESS_KEY`, `IAS3_SECRET_KEY` (GitHub) | catalog enrichment | CI | GitHub only |
| `BLUESKY_*`, `MASTODON_*`, `IG_*`, `THREADS_*`, `YOUTUBE_*`, `AW_YOUTUBE_CLIENT_ID`, `AW_TWITCH_CLIENT_ID`, `SOCIAL_MEDIA_BASE_URL`, `AW_PULSE_COUNTER`, `SECRETS_PAT` (GitHub) | social posting, refresh of tokens | CI | GitHub only |
| `Secrets.xcconfig` (gitignored) | TMDb, OMDb, TVDB, OpenSubtitles keys baked into local Apple builds | Xcode on the owner's Mac | still a file (Xcode needs one); CI writes its own. Phase 2: generate it from the Keychain at build time |

46 GitHub Actions secrets, 0 variables, 2 Worker secrets (`INGEST_TOKEN`, `TAKEDOWN_TOKEN`).

## What disappears

`TAKEDOWN_TOKEN`: the GitHub secret, the Worker secret, `takedown.env`, and the token path in `worker/src/takedown.js`
and `tools/takedown_cases.py`. The owner's `open`, `list`, `show` and `decide` read D1 through their own wrangler login.

## Owner migration (run by the main thread, with approval)

Order: deploy the Worker (`cd worker && wrangler deploy`), merge, then retire the token.

```
tools/secrets.sh keychain-import-asc --delete
tools/secrets.sh keychain-import-file PLAY_SERVICE_ACCOUNT_JSON ~/.config/play/archivewatch-play.json
tools/secrets.sh keychain-import-file AMAZON_APPSTORE_JSON ~/.config/amazon/appstore.json --delete
tools/secrets.sh keychain-import-file PULSE_INGEST_ENV ~/.config/archivewatch/pulse-ingest.env --delete
tools/secrets.sh keychain-import-file SUBTITLE_KEYS_ENV tools/subtitle_keys.env --delete
tools/secrets.sh keychain-import-file ROKU_SIGNING_ENV ~/.config/roku/signing.env
tools/secrets.sh keychain-import-file ROKU_SIGNING_KEY ~/keystores/roku-signing-key.txt
tools/secrets.sh keychain-import-file ROKU_GENKEY_RAW ~/keystores/roku-genkey.raw
tools/secrets.sh keychain-import-file UPLOAD_KEYSTORE ~/keystores/archivewatch-upload.jks
tools/secrets.sh keychain-import-file TIZEN_AUTHOR_P12 secrets/tizen-certificate/author.p12
tools/secrets.sh keychain-import-file TIZEN_DISTRIBUTOR_P12 secrets/tizen-certificate/distributor.p12
tools/secrets.sh drop-takedown-token
```

Each import is checked byte for byte before anything is deleted. `--delete` removes the file; the Roku, keystore,
Tizen and Play imports omit it on purpose: those files are irreplaceable (or shared), so the Trash step waits for the
owner to confirm the Keychain copy. Then to the Trash: `~/.config/archivewatch/takedown.env`, the `aw-ci-*` files in
`~/.appstoreconnect/private_keys/`, and `tools/asc-credentials.env` (after the ASC import).

## Phase 2: the Play service account, both apps together

One service account JSON serves Archive Watch and Ear Drama. Replace it with workload identity federation so no key
exists: create a workload identity pool and a GitHub OIDC provider in the Google Cloud project (issuer
`https://token.actions.githubusercontent.com`, attribute condition on `repository` in both repos and the workflow
files), let the service account be impersonated by that pool (`roles/iam.workloadIdentityUser`), switch each Play
workflow to `google-github-actions/auth` with the provider and service account (permission `id-token: write`), prove
a Play publish and a reports read on both repos, then delete the JSON key in Google Cloud, the GitHub secret
`PLAY_SERVICE_ACCOUNT_JSON` in both repos, and the Keychain copy. Local Play tools then use
`gcloud auth application-default login` with the owner's own account. Do not remove either repo's key before both work.

## Permission line for the owner (auto mode)

`Bash(tools/secrets.sh *)` for this repo, plus the wrapper `Bash(tools/with_asc.sh *)`.
