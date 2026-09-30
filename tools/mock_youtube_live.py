#!/usr/bin/env python3
"""A LOCAL stand-in for the YouTube Data API's live endpoints (macOS-DESIGN §D39).

Used by tools/test_studio_schedule.swift so scheduling, rescheduling, cancelling
and going live on a scheduled show can be exercised with no account, no token
and no network: nothing here talks to Google.

It binds 127.0.0.1 on a free port and prints `PORT <n>` as its first line.
Control endpoints (not part of the API):
  POST /__reset?scenario=<name>   clear the log and pick how the mock answers
  GET  /__log                      every API request since the reset, as JSON
Scenarios: ok, bindfail, thumbfail, gone, ended, streamgone.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STATE = {"scenario": "ok", "log": []}

STREAM = {
    "id": "stream-1",
    "cdn": {"ingestionInfo": {
        "streamName": "MOCK-KEY",
        "ingestionAddress": "rtmp://a.rtmp.mock.invalid/live2",
        "rtmpsIngestionAddress": "rtmps://a.rtmps.mock.invalid/live2",
        "rtmpsBackupIngestionAddress": "rtmps://b.rtmps.mock.invalid/live2?backup=1"}},
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, obj=None):
        body = b"" if obj is None else json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _record(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        u = urlparse(self.path)
        entry = {
            "method": self.command,
            "path": u.path,
            "query": {k: v[0] for k, v in parse_qs(u.query).items()},
            "contentType": self.headers.get("Content-Type", ""),
            "auth": self.headers.get("Authorization", ""),
            "bodyLength": len(raw),
            "bodyHead": raw[:4].hex(),
        }
        if entry["contentType"].startswith("application/json") and raw:
            entry["json"] = json.loads(raw)
        return u, entry

    def _handle(self):
        u, entry = self._record()
        sc = STATE["scenario"]
        if u.path == "/__reset":
            STATE["scenario"] = parse_qs(u.query).get("scenario", ["ok"])[0]
            STATE["log"] = []
            return self._send(200, {"scenario": STATE["scenario"]})
        if u.path == "/__log":
            return self._send(200, STATE["log"])
        STATE["log"].append(entry)
        p, m = u.path, self.command
        if p == "/youtube/v3/liveStreams" and m == "POST":
            return self._send(200, STREAM)
        if p == "/youtube/v3/liveStreams" and m == "GET":
            return self._send(200, {"items": [] if sc == "streamgone" else [STREAM]})
        if p == "/youtube/v3/liveBroadcasts" and m == "POST":
            return self._send(200, {"id": "bc-1", "snippet": {"liveChatId": "chat-1"}})
        if p == "/youtube/v3/liveBroadcasts/bind" and m == "POST":
            if sc == "bindfail":
                return self._send(400, {"error": {"message": "mock: bind refused"}})
            return self._send(200, {"id": "bc-1"})
        if p == "/youtube/v3/liveBroadcasts" and m == "DELETE":
            return self._send(204)
        if p == "/youtube/v3/liveBroadcasts" and m == "PUT":
            return self._send(200, entry.get("json", {}))
        if p == "/youtube/v3/liveBroadcasts" and m == "GET":
            if sc == "gone":
                return self._send(200, {"items": []})
            life = "complete" if sc == "ended" else "ready"
            return self._send(200, {"items": [{
                "id": entry["query"].get("id", ""),
                "snippet": {"liveChatId": "chat-1"},
                "status": {"lifeCycleStatus": life},
                "contentDetails": {"boundStreamId": "stream-1"}}]})
        if p == "/upload/youtube/v3/thumbnails/set" and m == "POST":
            if sc == "thumbfail":
                return self._send(403, {"error": {"message":
                    "mock: the channel is not allowed custom thumbnails"}})
            return self._send(200, {"items": []})
        return self._send(404, {"error": {"message": "mock: no such endpoint " + p}})

    do_GET = do_POST = do_PUT = do_DELETE = _handle


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print("PORT", srv.server_address[1], flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    sys.exit(main())
