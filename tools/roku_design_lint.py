#!/usr/bin/env python3
"""ROKU-DESIGN §13.11 — the ship gate, as a lint over roku/components.

Each rule here is a defect that was on the glass at least once this project:
  - a Roku system font by name (§13.1: every level is a bundled face at a size)
  - an instruction sentence on screen (§13.8: nothing narrates navigation)
  - a raw contentType printed as a label (§13.2: KindLabel() or nothing)
  - a focused LABEL painted marquee (§13.3: orange means "plays", never focus)
  - the old orange ring 9-patch (§13.3: the ring is light)
  - a Rectangle behind content that is not a title card or chrome (§13.6)

It reads source, so it cannot see geometry; the adversarial screenshot pass
still owns "does it look designed". This owns "did a banned shape come back".
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "roku" / "components"
RULES = [
    ("§13.1 system font by name",      re.compile(r'"font:[A-Za-z]+SystemFont"')),
    ("§13.8 instruction on screen",    re.compile(r'\.text\s*=\s*"[^"]*\bPress (OK|Right|Left|Up|Down|\*)\b')),
    ("§13.8 instruction on screen",    re.compile(r'"[^"]*\b(OK|Select) to (open|play|tune)\b')),
    ("§13.2 raw slug as label",        re.compile(r'\.text\s*=\s*UCase\((it|c|item)\.awType\)')),
    ("§13.3 focused label in marquee", re.compile(r'(title|label|caption)\.color\s*=\s*m\.t\.marquee')),
    ("§13.3 orange ring bitmap",       re.compile(r'focus_ring\.9\.png|focus_footprint\.9\.png')),
    ("§13.5 flat plate button",        re.compile(r'CreateChild\("Rectangle"\)\s*\n\s*\w+\.height\s*=\s*66')),
]
ALLOW = {
    # A rule-scoped exception must say why, here, or it is a defect.
    "GuideRow.brs:m.chip.color = m.t.marquee": "the ON NOW tag is meaning (§5.3), not focus",
    "EpisodeRow.brs:m.bar.color = m.t.marquee": "progress is meaning (§5.3)",
    "NavRail.brs:r.pill.color = m.t.marquee": "the selected rail item is the one allowed marquee chrome (§5.3)",
}

def main():
    findings = []
    for f in sorted(ROOT.glob("*.brs")):
        raw = f.read_text()
        # Comments are not UI. Blank them, keeping line numbers.
        text = "\n".join(("" if ln.lstrip().startswith("'") else ln) for ln in raw.splitlines())
        for name, rx in RULES:
            for m in rx.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                snippet = text[m.start(): m.end()].strip().splitlines()[0][:90]
                key = f"{f.name}:{snippet}"
                if any(key.startswith(k) for k in ALLOW):
                    continue
                findings.append((f.name, line, name, snippet))
    for fn, line, name, snip in findings:
        print(f"{fn}:{line}: {name}: {snip}")
    print(f"\n{len(findings)} finding(s) across {len(list(ROOT.glob('*.brs')))} components")
    return 1 if findings else 0

if __name__ == "__main__":
    sys.exit(main())
