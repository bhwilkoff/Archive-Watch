#!/usr/bin/env python3
"""
social_post.py — publish a post spec to the connected platforms.

Every platform is an INDEPENDENT ADAPTER that no-ops when its credentials are
absent (docs/SOCIAL-PROGRAM.md §8.4). The owner connects one account at a time;
the rest stay dark, and a run never fails because a platform is not set up yet.
Bluesky needs only an app password, so it works the day it is pasted; the Meta
platforms need app review, and TikTok an audit, so they wait.

The ledger (social/posted.json) is written PER PLATFORM and only after the
platform confirms — a retry after a half-failed run must not double-post where
it already landed (§7).

Environment (all optional; a missing set skips that platform):
  BLUESKY_HANDLE, BLUESKY_APP_PASSWORD
  THREADS_USER_ID, THREADS_ACCESS_TOKEN
  IG_USER_ID, IG_ACCESS_TOKEN
  FB_PAGE_ID, FB_PAGE_ACCESS_TOKEN
  YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN
  SOCIAL_MEDIA_BASE_URL   public https base the Meta platforms can fetch cards from

Run:
  python tools/social_post.py --spec social/out/post.json --card social/out/card.jpg
  python tools/social_post.py --spec ... --card ... --live      # actually post
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import mimetypes
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOCIAL = REPO / "social"
LEDGER = SOCIAL / "posted.json"
UA = "ArchiveWatch-Social/1.0 (+https://archivewatch.org)"
MEDIA_TAG = "social-cards"          # rolling Release; Decision 018 — never git

# Mastodon's 500 is the DEFAULT, not the rule — an instance sets its own and
# many run higher. resolve_mastodon_limit() asks the instance at run time and
# only ever raises this floor, so an unreachable instance still composes a
# post every server will accept.
LIMITS = {"bluesky": 300, "threads": 500, "instagram": 2200,
          "facebook": 5000, "youtube": 4900, "mastodon": 500}


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------

def http(url: str, data=None, headers=None, method=None, timeout=90):
    body = None
    hdrs = {"User-Agent": UA}
    if isinstance(data, (dict, list)):
        body = json.dumps(data).encode()
        hdrs["Content-Type"] = "application/json"
    elif isinstance(data, bytes):
        body = data
    hdrs.update(headers or {})
    req = urllib.request.Request(url, data=body, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            return json.loads(raw) if raw.strip().startswith(("{", "[")) else raw
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:400]
        raise RuntimeError(f"HTTP {e.code} {url.split('?')[0]} — {detail}") from None


def multipart(url: str, fields: dict, files: dict, headers=None, timeout=300):
    """multipart/form-data, built by hand so this stays dependency-free like
    every other tool here. `files` maps field name -> (filename, bytes)."""
    boundary = "aw-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S%f")
    body = b""
    for k, v in fields.items():
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"\r\n"
                 f"\r\n{v}\r\n").encode()
    for k, (name, raw) in files.items():
        mime = mimetypes.guess_type(name)[0] or "application/octet-stream"
        body += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{k}\"; "
                 f"filename=\"{name}\"\r\nContent-Type: {mime}\r\n\r\n").encode()
        body += raw + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return http(url, data=body, timeout=timeout,
                headers={**(headers or {}),
                         "Content-Type": f"multipart/form-data; boundary={boundary}"})


def form(url: str, fields: dict, timeout=90):
    return http(url, data=urllib.parse.urlencode(fields).encode(),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                timeout=timeout)


# --------------------------------------------------------------------------
# The copy. Assembled from the spec's sourced fragments — never generated.
# --------------------------------------------------------------------------

def compose(spec: dict, platform: str) -> str:
    frag = {f["kind"]: f["text"] for f in spec.get("fragments", [])}
    limit = LIMITS[platform]
    link = spec["link"]
    title = spec["title"]
    year = f" ({spec['year']})" if spec.get("year") else ""

    head = f"{title}{year}"
    lines = [head]
    if frag.get("meta"):
        # The head already carries the year, so drop the meta line's leading
        # copy of it — "The Wizard of Mars (1965) · 1965 · Feature film" reads
        # like a template with a hole in it.
        meta = frag["meta"].replace("  ·  ", " · ")
        if spec.get("year") and meta.startswith(f"{spec['year']} · "):
            meta = meta[len(f"{spec['year']} · "):]
        lines.append(meta)

    # The body: a viewer's words when we have them, else the film's own
    # synopsis. Both are quoted material, not our claims.
    body = []
    if frag.get("line"):
        body.append(frag["line"])
        body.append(f"— {title}")
    elif frag.get("review"):
        body.append(frag["review"])
        if frag.get("review_credit"):
            body.append(frag["review_credit"])
    elif frag.get("synopsis"):
        body.append(frag["synopsis"])

    if spec.get("partner"):
        p = spec["partner"]
        body.append(f"Double bill with {p['title']} ({p['year']}) — {p['why']}.")

    # The public-domain basis is the most genuinely useful sentence in the
    # post: it tells a reader WHY this is free, which is the thing almost
    # nobody knows about this catalog (§2, deepens understanding). It rides
    # above the link and is dropped first only if the post will not fit.
    rights = frag.get("rights")
    tail = f"Free to watch: {link}"

    def assemble(bodylines, with_rights=True):
        parts = [" · ".join(lines[:1] + lines[1:2])]
        if bodylines:
            parts.append("\n".join(bodylines))
        if rights and with_rights:
            parts.append(rights)
        parts.append(tail)
        return "\n\n".join(parts)

    text = assemble(body)
    # Trim the BODY (never the facts or the link) until it fits. A post that
    # loses its link is a post that sends nobody anywhere.
    #
    # Trim by the MEASURED overflow, not by a guess plus a margin: the first
    # version subtracted the overflow AND a fixed 24, then dropped a whole
    # word, and compounded that every pass — a Hercules Unchained review came
    # out at 47 characters with 27 characters of headroom going spare.
    guard = 0
    while len(text) > limit and body and guard < 12:
        guard += 1
        longest = max(range(len(body)), key=lambda i: len(body[i]))
        cut = body[longest]
        over = len(text) - limit
        keep = len(cut) - over - 2          # 2 = the ellipsis we add back
        if keep < 40:
            body.pop(longest)
        else:
            trimmed = cut[:keep]
            if " " in trimmed:
                trimmed = trimmed.rsplit(" ", 1)[0]
            trimmed = trimmed.rstrip(" ,.;:—-")
            body[longest] = (trimmed + '…"') if cut.startswith('"') else (trimmed + "…")
        text = assemble(body)
    if len(text) > limit and rights:
        text = assemble(body, with_rights=False)   # the link outranks the basis
    if len(text) > limit:
        text = f"{head}\n\n{tail}"

    if platform == "instagram":
        tags = ["#PublicDomain", "#ClassicFilm"]
        kind = spec.get("contentType", "")
        tags += {"silent-film": ["#SilentFilm"], "animation": ["#ClassicAnimation"],
                 "newsreel": ["#Newsreel"], "ephemeral": ["#EphemeralFilm"],
                 "tv-series": ["#ClassicTV"], "tv-special": ["#ClassicTV"],
                 "documentary": ["#Documentary"]}.get(kind, [])
        for g in spec.get("genres", [])[:2]:
            tags.append("#" + g.replace(" ", "").replace("-", ""))
        extra = "\n\n" + " ".join(dict.fromkeys(tags))
        if len(text) + len(extra) <= limit:
            text += extra
    return text


# --------------------------------------------------------------------------
# Media hosting — Meta fetches from a public URL, so a card must be published
# before it can be posted. A rolling GitHub Release keeps it off git.
# --------------------------------------------------------------------------

def publish_media(card: Path, spec: dict, live: bool) -> str | None:
    base = os.environ.get("SOCIAL_MEDIA_BASE_URL")
    name = f"{spec['date']}-{spec['id'][:48]}-{card.stem}{card.suffix}"
    name = "".join(c if c.isalnum() or c in "-._" else "-" for c in name)
    if base:
        url = base.rstrip("/") + "/" + name
        if not live:
            print(f"[media] would publish {card.name} -> {url}")
            return url
        staged = card.parent / name
        if staged != card:
            staged.write_bytes(card.read_bytes())
        r = subprocess.run(["gh", "release", "upload", MEDIA_TAG, str(staged), "--clobber"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            subprocess.run(["gh", "release", "create", MEDIA_TAG, "--notes",
                            "Rolling social card media (generated; see docs/SOCIAL-PROGRAM.md)",
                            "--title", "Social cards"], capture_output=True, text=True)
            r = subprocess.run(["gh", "release", "upload", MEDIA_TAG, str(staged), "--clobber"],
                               capture_output=True, text=True)
        if r.returncode != 0:
            print(f"[media] upload failed: {r.stderr.strip()[:200]}", file=sys.stderr)
            return None
        print(f"[media] published {url}")
        return url
    return None


# --------------------------------------------------------------------------
# Platform adapters. Each returns a permalink, or raises. None = not connected.
# --------------------------------------------------------------------------

def bsky_pds_host(session: dict, did: str) -> str:
    """The host of the user's OWN PDS — the audience for the service auth
    token. It is NOT video.bsky.app: the token authorises the PDS to speak
    for you, and the video service checks that. The session usually carries
    a didDoc; plc.directory is the fallback for the accounts that do not."""
    doc = session.get("didDoc") or {}
    for svc in doc.get("service", []) or []:
        if svc.get("type") == "AtprotoPersonalDataServer" and svc.get("serviceEndpoint"):
            return urllib.parse.urlparse(svc["serviceEndpoint"]).netloc
    try:
        doc = http(f"https://plc.directory/{did}")
        for svc in doc.get("service", []) or []:
            if svc.get("serviceEndpoint"):
                return urllib.parse.urlparse(svc["serviceEndpoint"]).netloc
    except Exception:  # noqa: BLE001
        pass
    return "bsky.social"


def bsky_upload_video(jwt: str, did: str, session: dict, video: Path) -> dict:
    """Upload through the video service and wait for the blob.

    Video does not go through uploadBlob: it is a separate service that
    transcodes, so the flow is service-auth -> upload -> poll for a job -> use
    the blob it hands back.
    """
    api = "https://bsky.social/xrpc"
    host = bsky_pds_host(session, did)
    exp = int(time.time()) + 30 * 60
    q = urllib.parse.urlencode({"aud": f"did:web:{host}",
                                "lxm": "com.atproto.repo.uploadBlob", "exp": exp})
    token = http(f"{api}/com.atproto.server.getServiceAuth?{q}",
                 headers={"Authorization": f"Bearer {jwt}"})["token"]

    raw = video.read_bytes()
    if len(raw) > 100_000_000:
        raise RuntimeError(f"clip is {len(raw)/1e6:.0f} MB; Bluesky's ceiling is 100 MB")
    up = urllib.parse.urlencode({"did": did, "name": video.name})
    job = http(f"https://video.bsky.app/xrpc/app.bsky.video.uploadVideo?{up}",
               data=raw, headers={"Authorization": f"Bearer {token}",
                                  "Content-Type": "video/mp4"}, timeout=600)
    status = job.get("jobStatus") or job
    job_id = status.get("jobId")
    blob = status.get("blob")
    for _ in range(90):
        if blob:
            return blob
        time.sleep(4)
        st = http("https://video.bsky.app/xrpc/app.bsky.video.getJobStatus"
                  f"?jobId={urllib.parse.quote(job_id)}",
                  headers={"Authorization": f"Bearer {token}"})
        js = st.get("jobStatus") or st
        blob = js.get("blob")
        if js.get("state") in ("JOB_STATE_FAILED", "failed"):
            raise RuntimeError(f"video job failed: {js.get('error') or js}")
    raise RuntimeError("video job did not finish in six minutes")


def video_size(path: Path) -> tuple[int, int]:
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                            "-show_entries", "stream=width,height", "-of", "csv=p=0:s=x",
                            str(path)], capture_output=True, text=True, timeout=60)
        w, h = r.stdout.strip().split("x")[:2]
        return int(w), int(h)
    except Exception:  # noqa: BLE001
        return 1080, 1920


def post_bluesky(spec, text, card: Path, live: bool, video: Path | None = None):
    handle = os.environ.get("BLUESKY_HANDLE")
    app_pw = os.environ.get("BLUESKY_APP_PASSWORD")
    if not (handle and app_pw):
        return None, "not connected"
    if not live:
        return "DRY-RUN", None

    api = "https://bsky.social/xrpc"
    sess = http(f"{api}/com.atproto.server.createSession",
                data={"identifier": handle, "password": app_pw})
    jwt, did = sess["accessJwt"], sess["did"]
    auth = {"Authorization": f"Bearer {jwt}"}

    # A moving picture beats a still on a feed, and Bluesky is the one
    # platform that takes video with no review at all. The review quote still
    # rides in the text either way.
    if video and video.exists():
        vblob = bsky_upload_video(jwt, did, sess, video)
        w, h = video_size(video)
        embed = {"$type": "app.bsky.embed.video", "video": vblob,
                 "aspectRatio": {"width": w, "height": h},
                 "alt": f"A scene from {spec['title']}"
                        + (f" ({spec['year']})" if spec.get("year") else "")}
    else:
        embed = None

    blob = None
    if embed is None and card and card.exists():
        raw = card.read_bytes()
        if len(raw) > 1_000_000:      # the AT Protocol lexicon's hard ceiling
            raise RuntimeError(f"card is {len(raw)} bytes; Bluesky's limit is 1,000,000")
        mime = mimetypes.guess_type(card.name)[0] or "image/jpeg"
        blob = http(f"{api}/com.atproto.repo.uploadBlob", data=raw,
                    headers={**auth, "Content-Type": mime})["blob"]

    # Links are only clickable with a richtext facet, and the facet indexes
    # BYTES, not characters — a title with an accent shifts every offset.
    facets = []
    raw_text = text.encode("utf-8")
    link_b = spec["link"].encode("utf-8")
    at = raw_text.find(link_b)
    if at >= 0:
        facets.append({"index": {"byteStart": at, "byteEnd": at + len(link_b)},
                       "features": [{"$type": "app.bsky.richtext.facet#link",
                                     "uri": spec["link"]}]})

    record = {"$type": "app.bsky.feed.post", "text": text, "langs": ["en"],
              "createdAt": dt.datetime.now(dt.timezone.utc)
                             .isoformat().replace("+00:00", "Z")}
    if facets:
        record["facets"] = facets
    if embed:
        record["embed"] = embed
    elif blob:
        alt = f"Poster for {spec['title']}" + (f" ({spec['year']})" if spec.get("year") else "")
        record["embed"] = {"$type": "app.bsky.embed.images",
                           "images": [{"alt": alt, "image": blob}]}

    res = http(f"{api}/com.atproto.repo.createRecord", headers=auth,
               data={"repo": did, "collection": "app.bsky.feed.post", "record": record})
    rkey = res["uri"].rsplit("/", 1)[-1]
    return f"https://bsky.app/profile/{handle}/post/{rkey}", None


def post_threads(spec, text, media_url, live: bool):
    uid = os.environ.get("THREADS_USER_ID")
    token = os.environ.get("THREADS_ACCESS_TOKEN")
    if not (uid and token):
        return None, "not connected"
    if not media_url:
        return None, "no public media URL (set SOCIAL_MEDIA_BASE_URL)"
    if not live:
        return "DRY-RUN", None

    api = "https://graph.threads.net/v1.0"
    # Only DOCUMENTED fields. Threads' create-container reference lists
    # media_type / image_url / video_url / text / is_carousel_item /
    # link_attachment / topic_tag / gif_attachment / access_token — and NOT
    # alt_text (Instagram's endpoint does document it, since March 2025, and
    # keeps it below). Checked 2026-09-06 because the live-endpoint probe
    # cannot tell a bad field from a bad token: Meta validates the token
    # first, so both answer the same OAuthException.
    fields = {"media_type": "IMAGE", "image_url": media_url, "text": text,
              "access_token": token}
    container = form(f"{api}/{uid}/threads", fields)["id"]
    time.sleep(30)          # Meta's documented container processing window
    res = form(f"{api}/{uid}/threads_publish",
               {"creation_id": container, "access_token": token})
    return f"https://www.threads.net/@me/post/{res.get('id')}", None


def post_instagram(spec, text, media_url, live: bool):
    uid = os.environ.get("IG_USER_ID")
    token = os.environ.get("IG_ACCESS_TOKEN")
    if not (uid and token):
        return None, "not connected"
    if not media_url:
        return None, "no public media URL (set SOCIAL_MEDIA_BASE_URL)"
    if not live:
        return "DRY-RUN", None

    api = "https://graph.facebook.com/v21.0"
    container = form(f"{api}/{uid}/media",
                     {"image_url": media_url, "caption": text,
                      "alt_text": f"Poster for {spec['title']}",
                      "access_token": token})["id"]
    # Poll rather than sleep blind: a container that is not FINISHED publishes
    # as an error, and the wait is usually a few seconds, not thirty.
    for _ in range(20):
        time.sleep(6)
        st = http(f"{api}/{container}?fields=status_code&access_token="
                  f"{urllib.parse.quote(token)}")
        if st.get("status_code") == "FINISHED":
            break
        if st.get("status_code") == "ERROR":
            raise RuntimeError("Instagram rejected the media container")
    res = form(f"{api}/{uid}/media_publish",
               {"creation_id": container, "access_token": token})
    return f"https://www.instagram.com/p/{res.get('id')}", None


def post_youtube(spec, text, video: Path | None, live: bool):
    """A Short. The teaser is already 1080x1920 and ~18 s, which is what makes
    it one — YouTube classifies by shape and length, not by a flag.

    Auth is a refresh token the owner mints once in a browser; the workflow
    never sees a password. Uploads bill to their own daily bucket, so one a
    day is nowhere near any ceiling.
    """
    cid = os.environ.get("YOUTUBE_CLIENT_ID")
    secret = os.environ.get("YOUTUBE_CLIENT_SECRET")
    refresh = os.environ.get("YOUTUBE_REFRESH_TOKEN")
    if not (cid and secret and refresh):
        return None, "not connected"
    if not video or not video.exists():
        return None, "no teaser for this film"
    if not live:
        return "DRY-RUN", None

    tok = form("https://oauth2.googleapis.com/token",
               {"client_id": cid, "client_secret": secret,
                "refresh_token": refresh, "grant_type": "refresh_token"})
    access = tok["access_token"]

    year = f" ({spec['year']})" if spec.get("year") else ""
    title = f"{spec['title']}{year} — free to watch"[:100]
    body_lines = [l for l in text.splitlines() if l.strip()]
    description = "\n".join(body_lines) + (
        "\n\nArchive Watch is a free, ad-free way to watch public-domain film "
        "on Apple TV, Android TV, Roku, iPhone, Android and the web.")
    meta = {"snippet": {"title": title, "description": description[:4900],
                        "categoryId": "1",
                        "tags": ["public domain", "classic film", "archive"]},
            "status": {"privacyStatus": "public", "selfDeclaredMadeForKids": False,
                       "license": "creativeCommon"}}

    # Multipart related: the metadata part, then the bytes. Building it by
    # hand keeps this dependency-free, which every other tool here is too.
    boundary = "aw-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S%f")
    parts = (
        f"--{boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
        f"{json.dumps(meta)}\r\n--{boundary}\r\nContent-Type: video/mp4\r\n\r\n"
    ).encode() + video.read_bytes() + f"\r\n--{boundary}--\r\n".encode()

    res = http("https://www.googleapis.com/upload/youtube/v3/videos"
               "?uploadType=multipart&part=snippet,status",
               data=parts,
               headers={"Authorization": f"Bearer {access}",
                        "Content-Type": f"multipart/related; boundary={boundary}"},
               timeout=900)
    vid = res.get("id")
    return f"https://youtube.com/watch?v={vid}", None


def mastodon_base() -> str | None:
    """Normalise whatever the owner pasted into an API base. People copy the
    instance out of the address bar, so it arrives as "mastodon.social",
    "https://mastodon.social" or with a trailing slash."""
    raw = (os.environ.get("MASTODON_INSTANCE") or "").strip()
    if not raw:
        return None
    if not raw.startswith(("http://", "https://")):
        raw = "https://" + raw
    return raw.rstrip("/")


def resolve_mastodon_limit() -> None:
    """Ask the instance for its own character ceiling. The Fediverse has no
    single limit — 500 is only Mastodon's default — so composing against a
    hardcoded number either wastes room or overflows. Never LOWERS the floor,
    so a server that answers oddly cannot produce an unpostable draft."""
    base = mastodon_base()
    if not base or not os.environ.get("MASTODON_ACCESS_TOKEN"):
        return
    try:
        info = http(f"{base}/api/v1/instance", timeout=20)
        n = int((info.get("configuration", {})
                     .get("statuses", {}) or {}).get("max_characters") or 0)
        if n > LIMITS["mastodon"]:
            LIMITS["mastodon"] = n
            print(f"[mastodon] {base} allows {n} characters")
    except Exception as e:  # noqa: BLE001 — the 500 floor is always safe
        print(f"[mastodon] using the default 500 ({e})")


def post_mastodon(spec, text, card: Path, live: bool, video: Path | None = None):
    """One access token the owner generates in their own account settings.
    There is no app review anywhere in this flow, which is what makes it the
    cheapest platform here to connect.
    """
    base = mastodon_base()
    token = os.environ.get("MASTODON_ACCESS_TOKEN")
    if not (base and token):
        return None, "not connected"
    if not live:
        return "DRY-RUN", None

    auth = {"Authorization": f"Bearer {token}"}
    year = f" ({spec['year']})" if spec.get("year") else ""

    # Alt text is not optional here as a matter of manners: the Fediverse
    # treats an undescribed image as a discourtesy, and this is a community
    # we want to arrive in well.
    media_id = None
    if video and video.exists() and len(video.read_bytes()) <= 40_000_000:
        alt = f"A scene from {spec['title']}{year}."
        up = multipart(f"{base}/api/v2/media", {"description": alt},
                       {"file": (video.name, video.read_bytes())},
                       headers=auth, timeout=600)
        media_id = up.get("id")
    elif card and card.exists():
        alt = (f"Poster for {spec['title']}{year}, on a card reading "
               f"\u201cFree to watch on Archive Watch\u201d.")
        up = multipart(f"{base}/api/v2/media", {"description": alt},
                       {"file": (card.name, card.read_bytes())}, headers=auth)
        media_id = up.get("id")

    # v2/media answers 202 while it transcodes, and attaching an unprocessed
    # id posts a status with a broken attachment. The GET returns 206 until
    # the file is ready, so poll for a url rather than trusting the first
    # response.
    if media_id:
        for _ in range(30):
            got = http(f"{base}/api/v1/media/{media_id}", headers=auth, timeout=30)
            if isinstance(got, dict) and got.get("url"):
                break
            time.sleep(4)

    fields = {"status": text, "visibility": "public", "language": "en"}
    if media_id:
        fields["media_ids[]"] = media_id
    # An Idempotency-Key makes a retried workflow safe: the server returns the
    # SAME status instead of posting the film twice. No other platform here
    # offers this, and a duplicate post is the most visible failure a feed can
    # have.
    key = f"aw-{spec['date']}-{spec['id']}"[:255]
    res = http(f"{base}/api/v1/statuses",
               data=urllib.parse.urlencode(fields).encode(),
               headers={**auth, "Idempotency-Key": key,
                        "Content-Type": "application/x-www-form-urlencoded"})
    return res.get("url") or res.get("uri") or f"{base}/", None


def post_facebook(spec, text, media_url, card: Path, live: bool):
    page = os.environ.get("FB_PAGE_ID")
    token = os.environ.get("FB_PAGE_ACCESS_TOKEN")
    if not (page and token):
        return None, "not connected"
    if not live:
        return "DRY-RUN", None

    api = "https://graph.facebook.com/v21.0"
    if media_url:
        res = form(f"{api}/{page}/photos",
                   {"url": media_url, "caption": text, "access_token": token})
    else:
        res = form(f"{api}/{page}/feed",
                   {"message": text, "link": spec["link"], "access_token": token})
    pid = res.get("post_id") or res.get("id")
    return f"https://www.facebook.com/{pid}", None


# --------------------------------------------------------------------------

def append_ledger(entries: list) -> None:
    SOCIAL.mkdir(parents=True, exist_ok=True)
    data = {"posts": []}
    if LEDGER.exists():
        try:
            data = json.loads(LEDGER.read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            data = {"posts": []}
    data.setdefault("posts", []).extend(entries)
    LEDGER.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n",
                      encoding="utf-8")
    print(f"[ledger] {len(entries)} entr{'y' if len(entries)==1 else 'ies'} "
          f"-> {LEDGER} ({len(data['posts'])} total)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec", required=True)
    ap.add_argument("--card", default=None, help="square card (Bluesky/Threads/FB)")
    ap.add_argument("--card-portrait", default=None, help="portrait card (Instagram)")
    ap.add_argument("--video", default=None,
                    help="vertical teaser; Bluesky posts it instead of the card")
    ap.add_argument("--live", action="store_true",
                    help="actually post. Without it, everything is a dry run.")
    ap.add_argument("--only", default=None, help="comma-separated platform allow-list")
    args = ap.parse_args()

    spec = json.loads(Path(args.spec).read_text(encoding="utf-8"))
    card = Path(args.card) if args.card else None
    card_pt = Path(args.card_portrait) if args.card_portrait else card
    video = Path(args.video) if args.video and Path(args.video).exists() else None
    only = {p.strip() for p in args.only.split(",")} if args.only else None

    print(f"film : {spec['title']} ({spec.get('year')})   slot: {spec['slot']}")
    print(f"link : {spec['link']}")
    print(f"media: {'teaser ' + video.name if video else 'card'}")
    print(f"mode : {'LIVE' if args.live else 'dry run (no --live)'}\n")

    media_url = publish_media(card, spec, args.live) if card else None
    media_pt = (publish_media(card_pt, spec, args.live)
                if card_pt and card_pt != card else media_url)

    resolve_mastodon_limit()
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    entries, failures = [], []

    plan = [
        ("bluesky", lambda t: post_bluesky(spec, t, card, args.live, video)),
        ("mastodon", lambda t: post_mastodon(spec, t, card, args.live, video)),
        ("threads", lambda t: post_threads(spec, t, media_url, args.live)),
        ("instagram", lambda t: post_instagram(spec, t, media_pt, args.live)),
        ("facebook", lambda t: post_facebook(spec, t, media_url, card, args.live)),
        ("youtube", lambda t: post_youtube(spec, t, video, args.live)),
    ]

    for name, fn in plan:
        if only and name not in only:
            continue
        text = compose(spec, name)
        print(f"── {name}  ({len(text)}/{LIMITS[name]} chars)")
        for line in text.splitlines():
            print(f"   {line}")
        try:
            url, skip = fn(text)
        except Exception as e:  # noqa: BLE001 — one platform must not stop the rest
            print(f"   !! {e}\n", file=sys.stderr)
            failures.append(name)
            continue
        if url is None:
            print(f"   (skipped — {skip})\n")
            continue
        if url == "DRY-RUN":
            print("   (dry run — would post)\n")
            continue
        print(f"   posted: {url}\n")
        entries.append({"at": now, "id": spec["id"], "title": spec["title"],
                        "slot": spec["slot"], "platform": name, "url": url,
                        "kind": spec.get("contentType"),
                        "reviewer": spec.get("reviewer")})

    if entries:
        append_ledger(entries)
    if failures:
        print(f"failed: {', '.join(failures)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
