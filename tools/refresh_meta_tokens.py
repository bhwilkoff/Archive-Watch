#!/usr/bin/env python3
"""
refresh_meta_tokens.py — keep the Instagram and Threads tokens alive forever.

WHY THIS EXISTS. Meta's long-lived tokens last ~60 days. Bluesky's app
password, the Mastodon token and the YouTube refresh token do not expire, so
Instagram and Threads were the only two platforms that would quietly stop
posting — with the workflow still green, because a missing credential is a SKIP
and not an error. Nobody would notice until someone looked at the accounts.

There is nothing manual about it. Both platforms expose a refresh endpoint that
returns a NEW 60-day token, and neither requires the old one to be near expiry
(measured: a token minted minutes earlier refreshed fine, expires_in 5,183,318s
= 59.99 days). Refreshing on every daily run therefore keeps both permanently
~60 days from lapsing, and the window only ever shrinks if the workflow itself
stops running for two months.

  Instagram  GET graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token
  Threads    GET graph.threads.net/refresh_access_token?grant_type=th_refresh_token

STORING THE RESULT is the part that needs a credential the workflow does not
get for free: GITHUB_TOKEN cannot write repository secrets. A fine-grained PAT
with Secrets: write, stored as SECRETS_PAT, is the one prerequisite. Without it
this tool still runs — it reports how long each token has left and changes
nothing, which is worth having on its own.

Run:
  python tools/refresh_meta_tokens.py            # report only
  python tools/refresh_meta_tokens.py --apply    # refresh and store
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

REPO = os.environ.get("GITHUB_REPOSITORY", "bhwilkoff/Archive-Watch")

PLATFORMS = [
    {"name": "instagram",
     "url": "https://graph.instagram.com/refresh_access_token",
     "grant": "ig_refresh_token",
     "secret": "IG_ACCESS_TOKEN",
     "env": "IG_ACCESS_TOKEN"},
    {"name": "threads",
     "url": "https://graph.threads.net/refresh_access_token",
     "grant": "th_refresh_token",
     "secret": "THREADS_ACCESS_TOKEN",
     "env": "THREADS_ACCESS_TOKEN"},
]

# Shout while there is still time to act by hand. A token inside this window
# means the daily refresh has not run for weeks, which is itself the problem.
WARN_DAYS = 14


def refresh(p: dict, token: str) -> tuple[str | None, int | None, str | None]:
    q = urllib.parse.urlencode({"grant_type": p["grant"], "access_token": token})
    try:
        with urllib.request.urlopen(f"{p['url']}?{q}", timeout=60) as r:
            d = json.load(r)
        return d.get("access_token"), d.get("expires_in"), None
    except urllib.error.HTTPError as e:
        body = e.read().decode()[:200]
        return None, None, f"{e.code} {body}"
    except Exception as e:                                   # noqa: BLE001
        return None, None, str(e)[:200]


def store(secret: str, value: str) -> str | None:
    """`gh secret set` does the libsodium sealing itself, so this needs no
    crypto here — only a token that may write secrets."""
    if not os.environ.get("SECRETS_PAT"):
        return "no SECRETS_PAT (a fine-grained PAT with Secrets: write)"
    r = subprocess.run(["gh", "secret", "set", secret, "--repo", REPO, "--body", value],
                       capture_output=True, text=True,
                       env={**os.environ, "GH_TOKEN": os.environ["SECRETS_PAT"]})
    return None if r.returncode == 0 else (r.stderr.strip()[:200] or "gh failed")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="store the refreshed tokens")
    a = ap.parse_args()

    worst_days, problems = None, []
    for p in PLATFORMS:
        token = os.environ.get(p["env"])
        if not token:
            print(f"[{p['name']}] not connected — nothing to refresh")
            continue
        new, expires, err = refresh(p, token)
        if err:
            # A refresh failure is NOT fatal: the current token is still valid
            # today, and killing the run would cost the day's post over a
            # problem that only matters in weeks.
            print(f"[{p['name']}] refresh FAILED: {err}", file=sys.stderr)
            problems.append(p["name"])
            continue
        days = round((expires or 0) / 86400, 1)
        worst_days = days if worst_days is None else min(worst_days, days)
        if not a.apply:
            print(f"[{p['name']}] refreshable; a new token would last {days} days "
                  f"(not stored — no --apply)")
            continue
        if (e := store(p["secret"], new)):
            print(f"[{p['name']}] refreshed but NOT STORED: {e}", file=sys.stderr)
            problems.append(p["name"])
        else:
            print(f"[{p['name']}] refreshed and stored — {days} days")

    if worst_days is not None and worst_days < WARN_DAYS:
        print(f"::warning::Meta token within {worst_days} days of expiry")
    if problems:
        print(f"::warning::token refresh incomplete: {', '.join(problems)}")
    return 0            # never fail the run over this


if __name__ == "__main__":
    sys.exit(main())
