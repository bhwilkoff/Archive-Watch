#!/usr/bin/env python3
"""Removal cases: the owner's commands and the takedown-check workflow's
(docs/TAKEDOWNS.md, Decision 175).

    open --links URL --work "NAME" [--source google --ref ID --complete]
    list                      open, held and approved cases, no personal details
    show TD-XXXXXXXX          the whole private record; for a person, never CI
    decide TD-XXXXXXXX remove|keep [--note TEXT]
    judge --out FILE          the workflow: read cases, check files, write the list
    report --updates FILE     the workflow, after the list is pushed

The workflow's log and the issues it opens are public. Nothing it prints or
files comes from a requester's own words: it says only a case number, an
archive id and a reason from REASONS below.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import takedown_check as C
import takedown_lib as T

API = "https://archivewatch-pulse.benwilkoff.workers.dev"
ENV_FILE = Path.home() / ".config/archivewatch/takedown.env"
MAX_REMOVALS = 5     # a run removes at most this many on its own; the rest wait

REASONS = {
    "title_word_only": "The claim names only a word of this title, which is how a "
                       "notice matched on a word reads.",
    "public_domain_by_age": "The file was read and shows nothing modern, and the "
                            "title is old enough to be public domain in the US.",
    "not_copyright": "This request is not a copyright notice, so it is yours to decide.",
    "incomplete_notice": "This notice is missing an element the law requires.",
    "unread_link": "A link in this request names nothing the check could read.",
    "run_limit": "This run reached its limit on automatic removals.",
}


def token() -> str:
    t = os.environ.get("TAKEDOWN_TOKEN")
    if not t and ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            if line.startswith("TAKEDOWN_TOKEN="):
                t = line.split("=", 1)[1].strip()
    if not t:
        sys.exit("No TAKEDOWN_TOKEN in the environment or " + str(ENV_FILE))
    return t


def call(path, body=None):
    req = urllib.request.Request(
        API + path, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json",
                 "User-Agent": "ArchiveWatch-takedown"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"{path}: HTTP {e.code}")


def gh(*args) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def owner_decision(ref):
    """The owner's newest `remove` or `keep` on the case's issue, and the issue."""
    found = json.loads(gh("issue", "list", "--state", "open", "--search", f"{ref} in:title",
                          "--json", "number,title"))
    issue = next((i for i in found if ref in i["title"]), None)
    if not issue:
        return None, None
    data = json.loads(gh("issue", "view", str(issue["number"]), "--json", "comments"))
    for c in reversed(data["comments"]):
        if c.get("authorAssociation") == "OWNER":
            word = (c.get("body") or "").strip().split()[:1]
            if word and word[0].lower() in ("remove", "keep"):
                return word[0].lower(), issue["number"]
    return None, issue["number"]


def add_lines(ids, ref, table, date):
    """Append to the public list. Only the date and case number, ever."""
    if not ids:
        return
    p = T.path()
    raw = json.loads(p.read_text(encoding="utf-8"))
    for aid in ids:
        raw.setdefault(aid, {"date": date, "case": ref})
        table[aid] = raw[aid]
    p.write_text(json.dumps(raw, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def judge_case(case, cat):
    """[{id, action, reason, evidence}], one per link."""
    out = []
    for t in C.targets(case.get("links")):
        if "unread" in t:
            out.append({"id": None, "action": "hold", "reason": "unread_link"})
            continue
        aid = cat.resolve(t["id"])
        item = cat.find(aid)
        ev = C.read_file(item.get("url")) if item else {"read": False}
        v = C.verdict({"kind": case.get("kind"), "complete": bool(case.get("complete")),
                       "work": case.get("work")}, item, ev)
        out.append({"id": aid, **v, "evidence": ev})
    return out or [{"id": None, "action": "hold", "reason": "unread_link"}]


def cmd_judge(a):
    cases = call("/takedown/cases?status=open,approved,held")["cases"]
    today = datetime.date.today().isoformat()
    updates, table, removed = [], T.load(), 0
    cat = C.Catalog()
    for case in cases:
        ref = case["ref"]
        if case["status"] == "held":
            word, number = owner_decision(ref)
            if word == "keep":
                updates.append({"ref": ref, "status": "declined", "issue": number})
                print(f"{ref}: declined by the owner")
                continue
            if word != "remove":
                continue
            case["status"] = "approved"
            print(f"{ref}: approved by the owner")
        elif case["status"] == "approved":
            number = owner_decision(ref)[1]
        else:
            number = None
        if case["status"] == "approved":
            ids = [cat.resolve(t["id"]) for t in C.targets(case.get("links")) if "id" in t]
            ids = [i for i in ids if cat.find(i)]
            add_lines(ids, ref, table, today)
            updates.append({"ref": ref, "status": "removed", "issue": number, "ids": ids})
            print(f"{ref}: removing {' '.join(ids)}")
            continue
        results = judge_case(case, cat)
        go = [r for r in results if r["action"] == "remove"]
        room = max(0, MAX_REMOVALS - removed)
        for r in go[room:]:
            r.update(action="hold", reason="run_limit")
        go = go[:room]
        removed += len(go)
        add_lines([r["id"] for r in go], ref, table, today)
        holds = [r for r in results if r["action"] == "hold"]
        status = "held" if holds else ("removed" if go else "closed")
        updates.append({"ref": ref, "status": status, "verdict": results,
                        "ids": [r["id"] for r in go]})
        for r in results:
            print(f"{ref}: {r['id']} {r['action']} {r['reason']}")
    T.strip_spines()
    Path(a.out).write_text(json.dumps(updates))
    print(f"{len(cases)} cases read, {len(updates)} changed")


def issue_body(u):
    lines = [f"Case `{u['ref']}` needs your decision. Reply `remove` or `keep`.", ""]
    for r in u["verdict"]:
        if r["action"] != "hold":
            continue
        ev = r.get("evidence") or {}
        read = (f"{ev.get('minutes')} min; burned-in logo: "
                f"{'yes' if ev.get('logo') else 'no'}; sound: "
                f"{'yes' if ev.get('hasAudio') else 'no'}") if ev.get("read") else "file not read"
        link = f"https://archivewatch.org/item/{r['id']}/ " if r.get("id") else ""
        lines.append(f"- {link}{REASONS[r['reason']]} ({read})")
    lines += ["", f"The request itself: `python3 tools/takedown_cases.py show {u['ref']}`"]
    return "\n".join(lines)


def cmd_report(a):
    for u in json.loads(Path(a.updates).read_text()):
        call(f"/takedown/cases/{u['ref']}",
             {"status": u["status"], **({"verdict": u["verdict"]} if "verdict" in u else {})})
        if u["status"] == "held":
            gh("issue", "create", "--title", f"Removal case {u['ref']}",
               "--body", issue_body(u))
        if u.get("issue"):
            gh("issue", "close", str(u["issue"]), "--comment", f"Case is now {u['status']}.")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    o = sub.add_parser("open")
    o.add_argument("--links", required=True)
    o.add_argument("--work", default="")
    o.add_argument("--source", default="email", choices=["email", "google"])
    o.add_argument("--ref", default="")
    o.add_argument("--name", default="")
    o.add_argument("--org", default="")
    o.add_argument("--complete", action="store_true")
    sub.add_parser("list")
    s = sub.add_parser("show")
    s.add_argument("ref")
    d = sub.add_parser("decide")
    d.add_argument("ref")
    d.add_argument("word", choices=["remove", "keep"])
    d.add_argument("--note", default="")
    j = sub.add_parser("judge")
    j.add_argument("--out", required=True)
    r = sub.add_parser("report")
    r.add_argument("--updates", required=True)
    a = ap.parse_args()
    if a.cmd == "open":
        print(call("/takedown/cases", {
            "kind": "copyright", "links": a.links, "work": a.work, "source": a.source,
            "external_ref": a.ref, "name": a.name, "org": a.org, "complete": a.complete})["ref"])
    elif a.cmd == "list":
        for c in call("/takedown/cases?status=open,approved,held")["cases"]:
            print(c["ref"], c["status"], c["source"], c["links"].split()[0])
    elif a.cmd == "show":
        print(json.dumps(call("/takedown/cases/" + a.ref), indent=1))
    elif a.cmd == "decide":
        status = "approved" if a.word == "remove" else "declined"
        call("/takedown/cases/" + a.ref, {"status": status, "note": a.note})
        if a.word == "keep":
            number = owner_decision(a.ref)[1]
            if number:
                gh("issue", "close", str(number), "--comment", "Case is now declined.")
        print(a.ref, status)
    elif a.cmd == "judge":
        cmd_judge(a)
    elif a.cmd == "report":
        cmd_report(a)


if __name__ == "__main__":
    main()
