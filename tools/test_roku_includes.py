#!/usr/bin/env python3
"""Every component that CALLS a shared function must INCLUDE it.

A missing <script> include is not a build error on Roku. The channel installs
clean and dies at runtime with "Function is not defined in component's
namespace" — on the first frame that happens to reach the call, which may be
several screens into the app. It has bitten this build three times:
EpisodeRow, MainScene and ChannelsScreen, each time costing a deploy-and-drive
cycle to find something a text scan answers instantly.

Maps the shared libraries to the prefixes they own, then checks every
component's .brs for calls it has not included.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "roku", "components")

# library file -> functions it defines
LIBS = ["Theme.brs", "UserStore.brs", "Sched.brs", "LayoutAudit.brs"]


def defined_in(path):
    src = open(path).read()
    return set(m.group(2) for m in re.finditer(r"^\s*(sub|function)\s+([A-Za-z_]\w*)", src, re.M))


def main():
    libfns = {lib: defined_in(os.path.join(ROOT, lib)) for lib in LIBS}
    problems = []
    for name in sorted(os.listdir(ROOT)):
        if not name.endswith(".xml"):
            continue
        xml = open(os.path.join(ROOT, name)).read()
        included = set(re.findall(r'uri="pkg:/components/([\w.]+\.brs)"', xml))
        # Every .brs the component pulls in, so a call satisfied by a sibling
        # script counts as satisfied.
        own = set()
        for b in included:
            p = os.path.join(ROOT, b)
            if os.path.isfile(p):
                own |= defined_in(p)
        called = set()
        for b in included:
            p = os.path.join(ROOT, b)
            if not os.path.isfile(p):
                continue
            for m in re.finditer(r"\b([A-Za-z_]\w*)\s*\(", open(p).read()):
                called.add(m.group(1))
        for lib, fns in libfns.items():
            if lib in included:
                continue
            missing = sorted((called & fns) - own)
            if missing:
                problems.append(f"{name}: calls {', '.join(missing)} but does not include {lib}")
    for p in problems:
        print("MISSING INCLUDE:", p)
    print(f"\n{len(problems)} problem(s) across {len(os.listdir(ROOT))//2} components")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
