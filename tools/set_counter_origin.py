#!/usr/bin/env python3
"""
set_counter_origin.py — point the site and the collector at the deployed counter.

`wrangler deploy` prints a workers.dev URL. Run this with it once; it writes the
origin into watch.js (which sends nothing while it is empty) and prints the
export line for the collector.

    tools/set_counter_origin.py https://archivewatch-pulse.SUBDOMAIN.workers.dev
"""
import pathlib
import re
import sys

if len(sys.argv) != 2 or not sys.argv[1].startswith("http"):
    sys.exit(__doc__)
origin = sys.argv[1].rstrip("/")
p = pathlib.Path(__file__).resolve().parent.parent / "watch.js"
s = p.read_text()
new = re.sub(r'const AW_BEACON_ORIGIN = "[^"]*";',
             f'const AW_BEACON_ORIGIN = "{origin}";', s, count=1)
if new == s:
    sys.exit("could not find AW_BEACON_ORIGIN in watch.js")
p.write_text(new)
print(f"watch.js now beacons to {origin}")
print()
print("Then, once:")
print(f'  gh secret set AW_PULSE_COUNTER --body "{origin}"')
print("and bump the service-worker SHELL so existing installs pick up watch.js.")
