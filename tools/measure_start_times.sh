#!/bin/zsh
# How long does a film take to reach its first frame ON THE APPLE TV?
#
# Owner decision (D077): "Films should start within 30 seconds. Waiting longer
# than that will lose users almost every time." That promise had never been
# measured across a sample — only asserted. The first three titles measured
# gave 3.7s, >75s and >75s, so the spread is the whole story and a single
# title tells you nothing.
#
# Measures setupPlayer -> itemReady from the app's own diag, which is the
# frame the viewer waits for, not a curl of the URL.
#
# Usage: tools/measure_start_times.sh <archiveID> [archiveID...]
set -u
DEV=${AW_DEVICE:-C3FBA9DE-4A60-555B-A65F-80D6809A275B}
WAIT=${AW_START_WAIT:-80}
ATV=${AW_ATV:-/tmp/atv.sh}

# AW_INTERLEAVE=1 alternates the hedged-probe arm title by title, so both arms
# meet the SAME archive.org weather. Comparing two sequential blocks does not
# work here and the numbers proved it: Yojimbo went from no-frame-in-75s to
# 5.8s within an hour, so a block-vs-block delta measures the hour. This is a
# stronger requirement than D075's repeated trials — the arms must be
# interleaved, not merely repeated.
# AW_PAIRED=1 measures EACH film under BOTH arms, back to back, alternating
# which goes first. Alternating the arm per TITLE was the first attempt and it
# is wrong for the same reason block-vs-block was: it compares different films.
# Pairing controls for the film AND keeps the two readings within a minute of
# each other, which is the only way to hold node weather roughly constant.
PAIRED=${AW_PAIRED:-0}
film_index=0
printf '%-46s %10s %s\n' "film" "to first frame" "arm"
for id in "$@"; do
  film_index=$((film_index+1))
  if [ "$PAIRED" = "1" ]; then
    if [ $((film_index % 2)) -eq 0 ]; then ARMS="1 0"; else ARMS="0 1"; fi
  else
    ARMS=${AW_HEDGE_PROBE:-0}
  fi
  for HEDGE in ${=ARMS}; do
  "$ATV" turn_on >/dev/null 2>&1; sleep 2; "$ATV" menu >/dev/null 2>&1; sleep 2
  xcrun devicectl device process launch --terminate-existing --device "$DEV" \
    -e "{\"AW_START_ITEM\":\"$id\",\"AW_AUTOPLAY\":\"1\",\"AW_DIAG_FILE\":\"1\",\"AW_PLAYBACK_DIAG\":\"1\",\"AW_NO_RESUME\":\"1\",\"AW_NO_CAPTIONS\":\"1\",\"AW_HEDGE_PROBE\":\"$HEDGE\"}" \
    app.archivewatch.tvos >/dev/null 2>&1
  sleep "$WAIT"
  log=$(mktemp)
  xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
    --domain-identifier app.archivewatch.tvos --source Library/Caches/awdiag.log \
    --destination "$log" >/dev/null 2>&1
  # Only THIS launch's lines: the diag file accumulates across runs and an
  # older session's itemReady would score the current one as instant.
  awk '/AWLIFE LAUNCH/{n=NR} {l[NR]=$0} END{for(i=n;i<=NR;i++) print l[i]}' "$log" > "$log.s"
  python3 - "$id" "$log.s" "$HEDGE" <<'PY'
import re, sys
film, path, arm = sys.argv[1], sys.argv[2], ("hedged" if sys.argv[3] == "1" else "single")
t = open(path, errors="ignore").read()
setup = re.search(r"^(\d+\.\d+) .*setupPlayer item=" + re.escape(film), t, re.M)
ready = re.search(r"^(\d+\.\d+) .*itemReady", t, re.M)
fail  = re.search(r"^(\d+\.\d+) .*itemFailed", t, re.M)
fb    = "fallback" if "FALLBACK to lower-quality" in t else ""
if setup and ready:
    print(f"{film[:46]:46} {float(ready.group(1))-float(setup.group(1)):9.1f}s {arm} {fb}")
elif setup and fail:
    print(f"{film[:46]:46} {'FAILED':>10} at {float(fail.group(1))-float(setup.group(1)):.0f}s {arm} {fb}")
else:
    print(f"{film[:46]:46} {'NO FRAME':>10} {arm} (setup seen: " + ("yes" if setup else "NO") + ")")
PY
  rm -f "$log" "$log.s"
  done
done
