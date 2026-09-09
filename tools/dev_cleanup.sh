#!/usr/bin/env bash
# dev_cleanup.sh — find, and optionally stop, development processes this repo
# left running on the machine.
#
# WHY. The owner asked twice why the Mac had slowed down. The first answer was
# two `social_card.py` processes that had spun at 98% CPU for three and a half
# days; the second was a Gradle release build. A third, smaller instance turned
# up later: three `python -m http.server` preview servers, two of them older
# than two days. None of those was noticed by the person who started them,
# because a process that is merely IDLE is invisible until something else needs
# the machine.
#
#   tools/dev_cleanup.sh          # report only
#   tools/dev_cleanup.sh --stop   # stop what it finds
set -uo pipefail
STOP=0
[ "${1:-}" = "--stop" ] && STOP=1

# Patterns this repo is responsible for. Deliberately narrow: never match a
# process the owner might be using for something else.
PATTERNS=(
  "python.* -m http\.server"       # local previews of the web app / dashboard
  "tools/social_card\.py"          # the renderer that once span for 3.5 days
  "tools/draft_server\.py"
  "GradleDaemon"
  "KotlinCompileDaemon"
  "[f]fmpeg .*archive"             # a transcode from one of our tools
)

found=0
for pat in "${PATTERNS[@]}"; do
  while read -r pid etime pcpu rss cmd; do
    [ -z "${pid:-}" ] && continue
    found=$((found + 1))
    printf "  %-8s %-12s %5s%% %6sMB  %s\n" "$pid" "$etime" "$pcpu" \
      "$((rss / 1024))" "$(echo "$cmd" | cut -c1-58)"
    [ "$STOP" -eq 1 ] && kill "$pid" 2>/dev/null
  done < <(ps -axo pid=,etime=,pcpu=,rss=,command= | grep -E "$pat" | grep -v grep)
done

if [ "$found" -eq 0 ]; then
  echo "nothing of this repo's is running."
else
  echo
  if [ "$STOP" -eq 1 ]; then
    echo "stopped $found process(es)."
  else
    echo "$found process(es) — run with --stop to end them."
  fi
fi

# Gradle's daemons need their own goodbye or they linger with their heap held.
if [ "$STOP" -eq 1 ] && [ -x android/gradlew ]; then
  ( cd android && ./gradlew --stop >/dev/null 2>&1 ) && echo "gradle daemons stopped."
fi
