#!/bin/bash
# The one-line platform mistakes that cost a day — checked mechanically.
#
# Both of these blocked a real broadcast, neither is visible in a diff review,
# and both would come back silently under a refactor:
#
#   §9.vvvv  `liveStreams.insert` set `contentDetails.isReusable` in its BODY
#            while declaring only `snippet,cdn,status` in `part`. YouTube
#            answers 400 `unexpectedPart: 'content_details'` — naming the part
#            it did not expect rather than the one that is missing, which reads
#            like the opposite complaint. Every YouTube go-live failed on it.
#
#   §9.vvvv  the Google auth URL asked `prompt=consent`, which re-shows consent
#            for the account Google has ALREADY chosen and never offers the
#            Brand Account picker. A host could not change channel: sign out and
#            straight back in returned the same channel in 42 seconds.
#
# SOURCE checks, and each carries a control — a checker that cannot fail is
# worth nothing (§9.rrrr learned that the expensive way).
#
#   bash tools/test_studio_request_shapes.sh
set -u
cd "$(dirname "$0")/.."
P=ArchiveWatch/ArchiveWatch/Studio/StudioPlatforms.swift
A=ArchiveWatch/ArchiveWatch/Studio/StudioPlatformAuth.swift
pass=0; fail=0

# Every part a body sets must be declared. Checked by pairing the `part` query
# of liveStreams.insert with the top-level keys of the body that follows it.
parts_declared () {   # $1 = file
    awk '
        /"\/liveStreams", method: "POST"/ { inCall=1 }
        inCall && /"part":/               { part=$0 }
        inCall && /"contentDetails":/     { body=1 }
        inCall && /\]\)\)/                { inCall=0 }
        END {
            if (!part) exit 2
            if (body && part !~ /contentDetails/) exit 1
            exit 0
        }' "$1"
}

echo "== liveStreams.insert declares every part its body sets =="
if parts_declared "$P"; then
  echo "  PASS  contentDetails is in the body and named in part"; pass=$((pass+1))
else
  [ $? -eq 2 ] && echo "  FAIL  could not find the liveStreams.insert call — has it moved?" \
               || echo "  FAIL  the body sets contentDetails and part does not declare it"
  fail=$((fail+1))
fi

echo "== the CONTROL: the same check must FAIL on a copy with the part removed =="
TMP=$(mktemp -t awshape)
sed 's/"part": "snippet,cdn,contentDetails,status"/"part": "snippet,cdn,status"/' "$P" > "$TMP"
if parts_declared "$TMP"; then
  echo "  FAIL  the control PASSED — this check cannot detect the defect"; fail=$((fail+1))
else
  echo "  PASS  the control fails, so the check can tell the two apart"; pass=$((pass+1))
fi
rm -f "$TMP"

echo "== the Google auth URL offers the account/channel chooser =="
if grep -q 'value: "select_account consent"' "$A"; then
  echo "  PASS  prompt=select_account consent"; pass=$((pass+1))
else
  echo "  FAIL  prompt does not request select_account — a host cannot change channel"
  fail=$((fail+1))
fi

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ] || exit 1
