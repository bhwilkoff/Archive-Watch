#!/bin/bash
# §D19 — a staged card reaches the HOST's thumbnail and nothing else.
#
# WHY THIS IS A SOURCE CHECK AND NOT A WIRE CHECK. The wire check exists too
# and is the better evidence: arm a show against a local server, stage a card,
# read the recording back and find the film still there (WATCH-TOGETHER
# §9.dddddd). But that measures ONE staged value at ONE moment. What this
# feature actually has to guarantee is structural — that there is no path at
# all from `stagedCard` to the engine — and a path that opens next month will
# not announce itself in a recording nobody re-runs.
#
# It is the same reasoning as §8.12: a rule that is only ever verified by
# somebody remembering to look is not verified.
#
# The divergence §D5 forbids is being deliberately reintroduced here, in one
# labelled corner, so the check is against the ONE thing that makes it safe:
# `stagedCard` is read by the thumbnail and by TAKE, and by nothing else.
#
#   bash tools/test_studio_staging.sh
set -u
cd "$(dirname "$0")/.."
fail=0
WIN=ArchiveWatch/ArchiveWatch/macOS/StudioWindow_macOS.swift
NEXT=ArchiveWatch/ArchiveWatch/macOS/StudioNextCard_macOS.swift
ROOT=ArchiveWatch/ArchiveWatch/macOS/RootView_macOS.swift

for f in "$WIN" "$NEXT"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; fail=1; }
done
[ $fail -eq 0 ] || { echo "RESULT: FAIL"; exit 1; }

# 1. EVERY reader of stagedCard, named. A new one is a failure until somebody
#    decides it is safe, which is the entire point.
readers=$(grep -rn "stagedCard" ArchiveWatch/ArchiveWatch --include=*.swift \
          | grep -v "^$ROOT:" | grep -vE "^\s*//" | grep -v "//.*stagedCard")
unexpected=$(echo "$readers" | grep -vE "^($WIN|$NEXT):")
if [ -n "$unexpected" ]; then
  echo "FAIL: stagedCard is read outside the Studio window and the NEXT card:"
  echo "$unexpected"
  fail=1
else
  echo "ok: stagedCard lives in $(basename "$WIN") and $(basename "$NEXT") only"
fi

# 2. NO LINE MAY SEND IT. The engine is reached through setCard/armCard; a
#    staged value must never appear on such a line. `cardChoice` may, and does.
sent=$(grep -rn "stagedCard" ArchiveWatch/ArchiveWatch --include=*.swift \
       | grep -E "setCard|armCard|StudioSession\.shared\.(setCard|setOverlay)")
if [ -n "$sent" ]; then
  echo "FAIL: a staged card is handed to the engine:"
  echo "$sent"
  fail=1
else
  echo "ok: no line hands stagedCard to the engine"
fi

# 3. TAKE CLEARS IT. A staged card that stays staged after it is shown means
#    the NEXT panel keeps advertising something already on air, which is the
#    divergence this rule exists to prevent, wearing the opposite sign.
if grep -A4 "cardChoice = controls.stagedCard" "$NEXT" | grep -q "stagedCard = .none"; then
  echo "ok: taking a staged card clears the staging"
else
  echo "FAIL: $NEXT takes a staged card without clearing it"
  fail=1
fi

# 4. ONE RENDERER. §D19's guard against building a second compositor that
#    drifts from the programme's — Decision 133 in its graphical form.
if grep -q "StudioOverlayRenderer(" "$NEXT"; then
  echo "ok: the thumbnail draws through the programme's own overlay renderer"
else
  echo "FAIL: $NEXT does not use StudioOverlayRenderer"
  fail=1
fi

# 5. THE NEGATIVE CONTROL. Every assertion above is a grep, and a grep that
#    matches nothing passes checks 2 and 5 for the wrong reason. Prove the
#    corpus is really being read: the ordinary card path MUST be found.
if grep -rq "setCard(" ArchiveWatch/ArchiveWatch --include=*.swift; then
  echo "ok: control — the unstaged card path is visible to this search"
else
  echo "FAIL: control failed; this test is searching nothing"
  fail=1
fi

[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
