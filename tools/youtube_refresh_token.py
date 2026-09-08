#!/usr/bin/env python3
"""
youtube_refresh_token.py — mint the YouTube refresh token, once, on this Mac.

WHY NOT THE OAUTH PLAYGROUND. The setup doc says to create a DESKTOP app
client, and a desktop client has no "authorized redirect URIs" field — so
Google's Playground, which redirects to developers.google.com, cannot be used
with one. The alternatives were to recreate the client as a Web app (and paste
the secret into a third-party page) or to use the loopback flow Google actually
documents for desktop clients. This is that flow.

WHAT IT DOES. Starts a one-request HTTP server on 127.0.0.1, opens Google's
consent screen in your browser, catches the ?code= it redirects back with, and
exchanges it for a refresh token. Nothing is stored and nothing leaves this
machine except the code exchange with Google.

CREDENTIALS. Read from the environment if present, otherwise prompted for. The
secret is read with getpass so it never echoes and never lands in shell history.

    python3 tools/youtube_refresh_token.py

Then store the three values as repo secrets:

    gh secret set YOUTUBE_CLIENT_ID
    gh secret set YOUTUBE_CLIENT_SECRET
    gh secret set YOUTUBE_REFRESH_TOKEN

A NOTE ON THE SCOPE. youtube.upload is all the poster needs — it can add a
video and nothing else. It cannot read your account, your other videos, or
delete anything. Ask for no more than that.
"""

from __future__ import annotations

import getpass
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import urllib.parse
import urllib.request
import webbrowser

SCOPE = "https://www.googleapis.com/auth/youtube.upload"
AUTH = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN = "https://oauth2.googleapis.com/token"


def ask(prompt: str, hidden: bool = False) -> str:
    """Read one value from the CONTROLLING TERMINAL, not stdin.

    Run through a harness that pipes stdin — Claude Code's `!` prefix, a CI
    step, anything non-interactive — plain input() raises EOFError immediately.
    /dev/tty is the terminal the human is actually looking at, and it stays
    readable even when stdin is redirected. If there is no tty either, say so
    plainly instead of dying with a traceback.
    """
    try:
        tty = open("/dev/tty", "r+")
    except OSError:
        print("\nNo terminal available to prompt on. Pass the values instead:\n"
              "  YOUTUBE_CLIENT_ID=... YOUTUBE_CLIENT_SECRET=... \\\n"
              "    python3 tools/youtube_refresh_token.py\n", file=sys.stderr)
        raise SystemExit(1)
    with tty:
        if hidden:
            try:
                return getpass.getpass(prompt, stream=tty).strip()
            except Exception:
                pass                      # fall through to a visible read
        tty.write(prompt)
        tty.flush()
        return (tty.readline() or "").strip()


# A FIXED port by default, which is what makes this work for either client
# type. A DESKTOP client accepts any 127.0.0.1 port, so the number is
# irrelevant to it. A WEB client only accepts redirect URIs registered in the
# console — and you cannot register a random one, so a stable port means you
# add "http://127.0.0.1:8765" once and it keeps working.
PREFERRED_PORT = 8765


def free_port() -> int:
    try:
        with socket.socket() as s:
            s.bind(("127.0.0.1", PREFERRED_PORT))
        return PREFERRED_PORT
    except OSError:
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            return s.getsockname()[1]


class Catcher(http.server.BaseHTTPRequestHandler):
    """One request, then done. The browser lands here after consent."""
    result: dict = {}

    def do_GET(self):  # noqa: N802
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        Catcher.result = {k: v[0] for k, v in q.items()}
        ok = "code" in Catcher.result
        body = ("<h2>Done — you can close this tab.</h2>"
                if ok else
                f"<h2>No code came back.</h2><p>{Catcher.result.get('error','')}</p>")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(body.encode())

    def log_message(self, *a):        # keep the console clean
        pass


def main() -> int:
    cid = os.environ.get("YOUTUBE_CLIENT_ID") or ask("Client ID: ")
    secret = os.environ.get("YOUTUBE_CLIENT_SECRET") or ask("Client secret (hidden): ", hidden=True)
    if not cid or not secret:
        print("need both a client ID and a client secret", file=sys.stderr)
        return 1

    port = free_port()
    redirect = f"http://127.0.0.1:{port}"
    state = secrets.token_urlsafe(16)
    url = AUTH + "?" + urllib.parse.urlencode({
        "client_id": cid,
        "redirect_uri": redirect,
        "response_type": "code",
        "scope": SCOPE,
        # offline + consent together are what actually produce a REFRESH token.
        # Without prompt=consent Google returns only an access token on any
        # re-authorisation, and the script would look like it silently failed.
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    })

    srv = http.server.HTTPServer(("127.0.0.1", port), Catcher)
    threading.Thread(target=srv.handle_request, daemon=True).start()

    print(f"\nRedirect URI in use: {redirect}")
    if port != PREFERRED_PORT:
        print(f"  (port {PREFERRED_PORT} was busy; a WEB client would need this one registered)")
    print("\nIf Google answers redirect_uri_mismatch, the client is a WEB application:")
    print(f"  add {redirect} under Authorized redirect URIs, then run this again.")
    print("A DESKTOP client needs nothing — it accepts any loopback port.\n")
    print("Opening the consent screen. Approve as the account that owns the")
    print(f"ArchiveWatchApp channel.\n\n  {url}\n")
    webbrowser.open(url)
    print("waiting for the redirect…")
    srv.socket.settimeout(300)
    for _ in range(300):
        if Catcher.result:
            break
        threading.Event().wait(1)

    got = Catcher.result
    if got.get("state") != state:
        # A mismatch means the response did not come from the request we made.
        print("state mismatch — refusing the response", file=sys.stderr)
        return 1
    if "code" not in got:
        print(f"no code returned: {got.get('error', 'timed out')}", file=sys.stderr)
        return 1

    data = urllib.parse.urlencode({
        "code": got["code"], "client_id": cid, "client_secret": secret,
        "redirect_uri": redirect, "grant_type": "authorization_code",
    }).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(TOKEN, data=data), timeout=60) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"token exchange failed: {e.code} {e.read().decode()[:200]}", file=sys.stderr)
        return 1

    rt = tok.get("refresh_token")
    if not rt:
        print("Google returned no refresh token. That happens when the account has\n"
              "already granted this client and Google reuses the old grant — revoke it\n"
              "at myaccount.google.com/permissions and run this again.", file=sys.stderr)
        return 1

    print("\n" + "=" * 62)
    print("REFRESH TOKEN (store it, then clear your scrollback):\n")
    print(rt)
    print("\n" + "=" * 62)
    print("\n  gh secret set YOUTUBE_REFRESH_TOKEN --repo bhwilkoff/Archive-Watch")
    print("  (paste it when prompted; also set YOUTUBE_CLIENT_ID and _CLIENT_SECRET)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
