#!/usr/bin/env python3
"""US English in everything a person reads on a screen (CLAUDE.md).

WHY THIS IS MECHANICAL. The owner found "program" on a label on 2026-09-22
and said they thought there was a standing rule. There was not — not in
CLAUDE.md, not in ENGINEERING-PROCESS, not in any design doc. So the words had
been drifting for as long as somebody British-flavored had been writing them,
which is the whole history of the Studio. A rule written down and checked by
nobody would drift again the same way; this is the part that does not.

WHAT IT CHECKS: string literals, on every platform, in the files a person's
eyes reach. Not comments and not the design docs — those matter too and are
being cleaned separately, but a red suite over a comment teaches people to
ignore the suite.

WHAT IT DELIBERATELY ALLOWS, and this is the interesting half:

  1. Strings that MATCH SOMEBODY ELSE'S DATA. The Party-Play keyword lists
     carry "color" AND "colour" because archive.org's own metadata carries
     both, and an uploader in Britain who typed "color" would vanish from the
     search if we tidied it. Matching other people's words is not writing our
     own.
  2. Framework identifiers. `labelLarge` is Material's name and `LabelList` is
     Roku's; they are names, not words.

    python3 tools/test_us_english.py
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

# British -> American, for words this project has actually produced. Kept
# small on purpose: a giant list from the internet fires on things like
# "practise"/"practice" where both spellings are correct in some sense, and a
# check that cries wolf is a check people disable.
BRITISH = {
    "programme": "program", "colour": "color", "behaviour": "behavior",
    "centred": "centered", "licence": "license", "favourite": "favorite",
    "cancelled": "canceled", "cancelling": "canceling",
    "normalise": "normalize", "normalised": "normalized", "normalising": "normalizing",
    "synchronise": "synchronize", "synchronised": "synchronized",
    "organise": "organize", "organised": "organized",
    "recognise": "recognize", "recognised": "recognized",
    "authorise": "authorize", "authorised": "authorized", "authorisation": "authorization",
    "minimise": "minimize", "optimise": "optimize", "customise": "customize",
    "summarise": "summarize", "realise": "realize", "prioritise": "prioritize",
    "travelled": "traveled", "labelled": "labeled", "signalled": "signaled",
    "catalogue": "catalog", "whilst": "while", "amongst": "among",
    "apologise": "apologize", "analyse": "analyze",
}
WORD = re.compile(r"\b(" + "|".join(sorted(BRITISH, key=len, reverse=True)) + r")\b", re.I)

# Files whose string literals a person reads. Deliberately NOT everything:
# harness output and test names are read by us, not by them.
TARGETS = [
    ("swift", "ArchiveWatch/ArchiveWatch/**/*.swift"),
    ("kotlin", "android/app/src/main/java/**/*.kt"),
    ("android-xml", "android/app/src/main/res/values/*.xml"),
    ("web", "*.html"),
    ("brightscript", "roku/components/**/*.brs"),
]

# THE EXCEPTIONS, each with the reason it exists. A bare list of allowed
# strings is how a real defect gets added to an allowlist by somebody in a
# hurry; a reason makes that awkward.
ALLOWED = [
    ('"colour"', "archive.org's own metadata spells it both ways; the Party-Play "
                 "keyword search must match an uploader who typed either"),
]

STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"')
COMMENT_START = ("//", "///", "*", "'", "<!--", "#")


def literals(path):
    for i, line in enumerate(path.read_text(errors="ignore").split("\n"), 1):
        st = line.lstrip()
        if st.startswith(COMMENT_START):
            continue
        if path.suffix in (".html", ".xml"):
            # Prose in markup is the text between tags, not a quoted literal.
            text = re.sub(r"<[^>]+>", " ", line)
            yield i, text, line
        else:
            for m in STRING.finditer(line):
                yield i, m.group(0), line


def main():
    failures = []
    checked = 0
    for label, pattern in TARGETS:
        for path in ROOT.glob(pattern):
            if "build/" in str(path) or "/Tests/" in str(path):
                continue
            for lineno, text, raw in literals(path):
                checked += 1
                for m in WORD.finditer(text):
                    word = m.group(0)
                    if any(a[0].strip('"').lower() == word.lower()
                           and a[0] in raw for a in ALLOWED):
                        continue
                    rel = path.relative_to(ROOT)
                    failures.append((f"{rel}:{lineno}", word,
                                     BRITISH[word.lower()], text.strip()[:90]))

    # NEGATIVE CONTROL. Every assertion above is a regex over files found by a
    # glob, and a glob that matches nothing passes silently — which is how a
    # check goes green for a year while checking nothing (Decision 130).
    if checked < 500:
        print(f"FAIL: only {checked} strings were examined — the globs are "
              f"matching almost nothing, so this check proves nothing.")
        return 1
    probe = "the programme is a colour behaviour"
    if len(WORD.findall(probe)) != 3:
        print("FAIL: control — the matcher does not find known British spellings.")
        return 1
    print(f"  ok   control — {checked} strings examined; the matcher finds "
          f"{len(WORD.findall(probe))} of 3 planted spellings")

    if failures:
        print(f"\nFAIL: {len(failures)} British spelling(s) in text a person reads:\n")
        for where, got, want, ctx in failures:
            print(f"  {where}\n      '{got}' -> '{want}'   {ctx}")
        print("\n  CLAUDE.md: US English everywhere we write prose. If a string must")
        print("  keep a British spelling because it matches somebody else's data,")
        print("  add it to ALLOWED in this file WITH THE REASON.")
        return 1

    print("PASS: every user-facing string is US English")
    return 0


if __name__ == "__main__":
    sys.exit(main())
