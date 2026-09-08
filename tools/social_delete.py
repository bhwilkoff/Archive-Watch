#!/usr/bin/env python3
"""
social_delete.py — remove a post we should not have made, and forget it.

Written for one incident: four teasers went out with no audio (2026-09-08),
because the clip cutter kept sound only for line-led cuts. A silent Short
does not read as restraint, it reads as broken, so the posts come down.

Three rules:

* **Dry run by default.** Deleting a published post is not reversible on any
  of these platforms, so `--apply` is required and every URL is named before
  anything happens.

* **The ledger forgets it too.** `social/posted.json` is what stops a film
  repeating inside a year (SOCIAL-PROGRAM §7). A deleted post that stays in
  the ledger retires its film for 365 days for nothing — so the row goes with
  the post, and the film becomes eligible again.

* **Never a blanket success.** Two of these platforms cannot delete over their
  API at all, and saying so plainly is the whole value: Instagram's Content
  Publishing API is create-only, and YouTube's `videos.delete` needs a scope
  broader than the `youtube.upload` this project deliberately minted. Those
  are reported as MANUAL with the exact place to do it, never as done.

Run:
  python3 tools/social_delete.py --url <permalink> [--url ...]        # dry
  python3 tools/social_delete.py --url <permalink> --apply
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LEDGER = REPO / "social" / "posted.json"
UA = "ArchiveWatch/1.0 (+https://archivewatch.org)"


def http(url, data=None, method=None, headers=None, timeout=60):
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"User-Agent": UA, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        # Meta answers a wrong endpoint with a 500 and a message that says
        # WHICH — discarding the body turns a readable refusal into a shrug.
        detail = (e.read().decode("utf-8", "replace") or "")[:300]
        raise urllib.error.HTTPError(e.url, e.code, f"{e.reason} — {detail}",
                                     e.headers, None) from None
    return json.loads(body) if body.strip().startswith(("{", "[")) else {}


def platform_of(url: str) -> str:
    host = urllib.parse.urlparse(url).netloc.lower()
    if "bsky.app" in host:
        return "bluesky"
    if "threads.net" in host:
        return "threads"
    if "instagram.com" in host:
        return "instagram"
    if "youtube.com" in host or "youtu.be" in host:
        return "youtube"
    return "mastodon"          # every other host here is a Mastodon instance


# --------------------------------------------------------------------------

def delete_bluesky(url: str, apply: bool) -> tuple[bool, str]:
    handle = os.environ.get("BLUESKY_HANDLE")
    pw = os.environ.get("BLUESKY_APP_PASSWORD")
    if not (handle and pw):
        return False, "not connected"
    rkey = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    if not apply:
        return True, f"would delete record {rkey}"
    api = "https://bsky.social/xrpc"
    sess = http(f"{api}/com.atproto.server.createSession",
                data=json.dumps({"identifier": handle, "password": pw}).encode(),
                headers={"Content-Type": "application/json"})
    http(f"{api}/com.atproto.repo.deleteRecord",
         data=json.dumps({"repo": sess["did"], "collection": "app.bsky.feed.post",
                          "rkey": rkey}).encode(),
         headers={"Content-Type": "application/json",
                  "Authorization": f"Bearer {sess['accessJwt']}"})
    return True, "deleted"


def delete_mastodon(url: str, apply: bool) -> tuple[bool, str]:
    token = os.environ.get("MASTODON_ACCESS_TOKEN")
    base = (os.environ.get("MASTODON_INSTANCE")
            or f"{urllib.parse.urlparse(url).scheme}://{urllib.parse.urlparse(url).netloc}")
    if not token:
        return False, "not connected"
    sid = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    if not apply:
        return True, f"would delete status {sid}"
    http(f"{base.rstrip('/')}/api/v1/statuses/{sid}", method="DELETE",
         headers={"Authorization": f"Bearer {token}"})
    return True, "deleted"


def delete_threads(url: str, apply: bool) -> tuple[bool, str]:
    """Threads publishes a DELETE on a media id. Attempted, and reported
    honestly if the account's token will not carry it."""
    token = os.environ.get("THREADS_ACCESS_TOKEN")
    if not token:
        return False, "not connected"
    mid = urllib.parse.urlparse(url).path.rstrip("/").rsplit("/", 1)[-1]
    if not mid.isdigit():
        return False, f"cannot read a media id out of {url}"
    if not apply:
        return True, f"would delete media {mid}"
    http(f"https://graph.threads.net/v1.0/{mid}"
         f"?access_token={urllib.parse.quote(token)}", method="DELETE")
    return True, "deleted"


def delete_instagram(url: str, apply: bool) -> tuple[bool, str]:
    # Not an oversight and not worth retrying: the Instagram Content
    # Publishing API creates and publishes media and has no delete for it.
    return False, ("MANUAL — Instagram's API cannot delete media. "
                   "Remove it in the app: the post > ... > Delete")


def delete_youtube(url: str, apply: bool) -> tuple[bool, str]:
    """videos.delete needs a broader scope than we mint.

    `youtube_refresh_token.py` asks for `youtube.upload` on purpose — the
    narrowest scope that can post a Short. Deleting needs `youtube` or
    `youtube.force-ssl`, which also grants full channel management. It is
    attempted anyway (the consent screen may have granted more) and the
    refusal is reported with what to do about it.
    """
    vid = urllib.parse.parse_qs(urllib.parse.urlparse(url).query).get("v", [None])[0]
    cid = os.environ.get("YOUTUBE_CLIENT_ID")
    sec = os.environ.get("YOUTUBE_CLIENT_SECRET")
    ref = os.environ.get("YOUTUBE_REFRESH_TOKEN")
    if not (vid and cid and sec and ref):
        return False, "not connected"
    if not apply:
        return True, f"would attempt videos.delete on {vid}"
    body = urllib.parse.urlencode({"client_id": cid, "client_secret": sec,
                                   "refresh_token": ref,
                                   "grant_type": "refresh_token"}).encode()
    tok = http("https://oauth2.googleapis.com/token", data=body)["access_token"]
    try:
        http(f"https://www.googleapis.com/youtube/v3/videos?id={vid}",
             method="DELETE", headers={"Authorization": f"Bearer {tok}"})
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return False, (f"MANUAL — the token's scope is youtube.upload, which "
                           f"cannot delete (HTTP {e.code}). Remove it at "
                           f"studio.youtube.com > Content > {vid}, or re-mint the "
                           f"refresh token with youtube.force-ssl")
        raise
    return True, "deleted"


DELETERS = {"bluesky": delete_bluesky, "mastodon": delete_mastodon,
            "threads": delete_threads, "instagram": delete_instagram,
            "youtube": delete_youtube}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", action="append", default=[],
                    help="permalink to delete; repeatable")
    ap.add_argument("--urls", default="",
                    help="comma- or newline-separated permalinks")
    ap.add_argument("--apply", action="store_true", help="actually delete")
    ap.add_argument("--ledger", default=str(LEDGER))
    args = ap.parse_args()

    urls = [u.strip() for u in args.url + args.urls.replace(",", "\n").splitlines()
            if u.strip()]
    if not urls:
        print("nothing to delete: pass --url or --urls", file=sys.stderr)
        return 2

    print(f"{'DELETING' if args.apply else 'DRY RUN'} — {len(urls)} post(s)\n")
    gone, manual = [], []
    for url in urls:
        plat = platform_of(url)
        try:
            ok, note = DELETERS[plat](url, args.apply)
        except Exception as e:  # noqa: BLE001
            ok, note = False, f"failed: {e}"
        print(f"  {plat:<10} {note}\n             {url}")
        (gone if ok else manual).append(url)

    # The ledger forgets a post we removed, or the film it named stays retired
    # for a year for a post nobody can see. Only rows we actually deleted.
    if args.apply and gone:
        led = json.loads(Path(args.ledger).read_text(encoding="utf-8"))
        before = len(led.get("posts", []))
        led["posts"] = [p for p in led.get("posts", []) if p.get("url") not in set(gone)]
        Path(args.ledger).write_text(json.dumps(led, indent=1) + "\n", encoding="utf-8")
        print(f"\nledger: {before} -> {len(led['posts'])} rows "
              f"(the films are eligible again)")

    print(f"\n{len(gone)} removed, {len(manual)} need a hand")
    return 0


if __name__ == "__main__":
    sys.exit(main())
