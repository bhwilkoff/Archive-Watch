#!/usr/bin/env python3
"""
test_workflow_health.py — the auditor must never be blind to a FAILURE.

The regression this exists for: "Publish catalog DB" — the workflow that ships
the app's catalog — sat on this tool's exemption list because it prints no
yield summary, and the list was read as "never look at it". It then failed
every hour for two days, 2026-09-06 to 09-08, entirely unreported, while the
daily audit said nothing needed attention.

Checked to FAIL against the exempt-entirely build.

Run: python3 tools/test_workflow_health.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_workflow_health as A

ok = fail = 0


def check(name, cond, detail=""):
    global ok, fail
    if cond:
        ok += 1; print(f"  PASS  {name}")
    else:
        fail += 1; print(f"  FAIL  {name}  {detail}")


def run(concl, mins=20, rid=1):
    return {"id": rid, "conclusion": concl,
            "run_started_at": "2026-09-08T00:00:00Z",
            "updated_at": f"2026-09-08T00:{mins:02d}:00Z"}


# No network: every judgement below is decided before an API or log call, or
# the stub answers it.
A.api = lambda path: {"jobs": [{"steps": []}]}
A.gh = lambda *a: "ran fine\n"

print("a failure is a failure whoever produced it")
for name in sorted(A.NO_YIELD_LINE):
    v = A.judge(name, run("failure"), yield_ok=False)
    check(f"{name[:34]}: FAILED is reported", v and v[0] == "FAILED", str(v))

print("\nthe yield analysis is still skipped for them")
check("a green no-yield run is not called SILENT",
      A.judge("Publish catalog DB", run("success"), yield_ok=False) is None)
check("a green PRODUCER with no yield line IS silent",
      (A.judge("Discover content", run("success"), yield_ok=True) or ("",))[0] == "SILENT")

print("\nthe exemption lists say different things")
check("only the auditor itself is exempt from judgement", A.SELF == {"Workflow health"})
check("the catalog publish is NOT exempt from judgement",
      "Publish catalog DB" not in A.SELF)
check("it is still exempt from the yield analysis",
      "Publish catalog DB" in A.NO_YIELD_LINE)
check("the old blanket name is gone", not hasattr(A, "NOT_PRODUCERS"))

print("\ndisplacement carries no information")
# The shape that failed the audit EVERY DAY: a Decision-066 split whose probe
# job succeeded and whose queued apply job was destroyed with zero steps.
def jobs_reply(probe_steps, apply_concl, apply_steps):
    return lambda path: {"jobs": [
        {"conclusion": "success", "steps": [{"name": "s", "conclusion": "success"}] * probe_steps},
        {"conclusion": apply_concl, "steps": [{"name": "s", "conclusion": "success"}] * apply_steps},
    ]}

_api = A.api
A._DISPLACED.clear()
A.api = jobs_reply(10, "cancelled", 0)
check("a displaced APPLY job counts as displaced, not killed",
      A.displaced(run("cancelled", rid=101)))
A._DISPLACED.clear()
check("...and is reported DROPPED",
      (A.judge("Codec audit", run("cancelled", rid=101)) or ("",))[0] == "DROPPED")

# A human or a timeout cancelling a RUNNING job always leaves steps behind.
A._DISPLACED.clear()
A.api = jobs_reply(10, "cancelled", 4)
check("a job cancelled MID-RUN is still KILLED, never dropped",
      not A.displaced(run("cancelled", rid=102)))
A._DISPLACED.clear()
check("...and reports KILLED",
      (A.judge("X", run("cancelled", rid=102)) or ("",))[0] == "KILLED")

# The auditor and the sweeper must not disagree about what displacement is.
import re as _re
sweeper = (Path(A.__file__).parent / "retry_infra_failures.py").read_text()
check("the sweeper uses the same zero-steps-on-bad-jobs test",
      'not any(j.get("steps") for j in bad)' in sweeper)
check("and so does the auditor",
      'not any(j.get("steps") for j in bad)' in Path(A.__file__).read_text())
A.api = _api
A._DISPLACED.clear()

A._DISPLACED.clear()
check("a cancelled run with no steps is displaced", A.displaced(run("cancelled", rid=7)))
check("and is reported DROPPED, not KILLED",
      (A.judge("X", run("cancelled", rid=7)) or ("",))[0] == "DROPPED")
check("a success is never displaced", not A.displaced(run("success", rid=8)))
calls = []
_api = A.api
A.api = lambda p: (calls.append(p), {"jobs": [{"steps": []}]})[1]
A._DISPLACED.clear()
A.displaced(run("cancelled", rid=9)); A.displaced(run("cancelled", rid=9))
check("the jobs call is made once per run, not per question", len(calls) == 1, str(calls))
A.api = _api

check("DROPPED is reported, never emailed twice",
      "DROPPED" not in A.URGENT_SEVERITIES)
check("a real break still pages", set(A.URGENT_SEVERITIES) == {"BROKEN", "KILLED"})

print(f"\n{ok} passed, {fail} failed")
sys.exit(1 if fail else 0)
