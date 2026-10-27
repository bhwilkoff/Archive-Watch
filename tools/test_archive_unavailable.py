#!/usr/bin/env python3
"""archive.org not answering is not archive.org finding nothing (ENGINEERING-
PROCESS §1). Found 2026-10-17: adv_search returned [] and scrape_query a bare
`return` on a refused or throttled call, so ingest marked the film
"unresolved" for good and discovery read the feed as having nothing new.

Cases: a 503 or a 429 every try raises ArchiveUnavailable from adv_search,
resolve_title and scrape_query; one refusal then an answer is retried and
answered. Controls: an honest empty answer is still [] / no items.
"""
import sys
from pathlib import Path
from unittest import mock

R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import archive_lib as A
import discover_archive_collections as D

ok = True


def check(name, cond):
    global ok
    ok &= bool(cond)
    print(f"  {'ok  ' if cond else 'FAIL'} {name}")


class Resp:
    def __init__(self, status, body=None):
        self.status_code, self.ok, self._body = status, status == 200, body

    def json(self):
        return self._body


class Session:
    def __init__(self, *answers):
        self.answers, self.calls = list(answers), 0

    def get(self, *a, **k):
        self.calls += 1
        return self.answers.pop(0) if len(self.answers) > 1 else self.answers[0]


def raises(fn):
    try:
        fn()
    except A.ArchiveUnavailable:
        return True
    return False


with mock.patch.object(A.time, "sleep", lambda s: None):
    s = Session(Resp(503))
    check("a refusal every try raises, not []", raises(lambda: A.adv_search("q", s)))
    check("... after three tries", s.calls == 3)
    check("a throttle reaches resolve_title's caller",
          raises(lambda: A.resolve_title("Nosferatu", 1922, Session(Resp(429)))))
    s = Session(Resp(503), Resp(200, {"response": {"docs": [{"identifier": "x"}]}}))
    check("one refusal then an answer is answered", A.adv_search("q", s) == [{"identifier": "x"}])
    check("control: an honest empty answer is []",
          A.adv_search("q", Session(Resp(200, {"response": {"docs": []}}))) == [])
    check("control: resolve_title on an empty answer finds nothing",
          A.resolve_title("Nosferatu", 1922, Session(Resp(200, {"response": {"docs": []}}))) == (None, 0, None))
    check("scrape_query raises on a refusal, never ends quietly",
          raises(lambda: list(D.scrape_query("q", Session(Resp(429)), limit=10, min_downloads=0))))
    check("control: scrape_query on an empty answer yields nothing",
          list(D.scrape_query("q", Session(Resp(200, {"items": []})), limit=10, min_downloads=0)) == [])

print("PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
