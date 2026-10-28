#!/usr/bin/env bash
# Every web test in one command. These lock behaviour that a browser cannot
# easily show and a screenshot cannot show at all: which store a device is
# offered, which controls the browser already draws, whether a search chip can
# lead to an empty grid, and what the search haystack contains.
#
# Each suite reads its function out of the SHIPPED watch.js, so a test can
# never drift from what actually runs.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
for t in tools/test_web_search.mjs \
         tools/test_search_facets.mjs \
         tools/test_native_controls.mjs \
         tools/test_app_banner.mjs \
         tools/test_tmdb_rendition.mjs \
         tools/test_view_transition.mjs \
         tools/test_web_sort_rules.mjs \
         tools/test_sync_sortindex.mjs \
         tools/test_share_list.mjs \
         tools/test_drivesync_no_popup.mjs \
         tools/test_tv_focus.mjs \
         tools/test_web_audit_fixes.mjs \
         tools/test_web_sync_failures.mjs; do
  out=$(node "$t" 2>&1)
  last=$(printf '%s\n' "$out" | tail -1)
  if [ $? -ne 0 ] || printf '%s' "$out" | grep -q FAIL; then
    printf '  FAIL  %-32s %s\n' "$(basename "$t")" "$last"
    printf '%s\n' "$out" | grep FAIL | sed 's/^/          /'
    fail=1
  else
    printf '  ok    %-32s %s\n' "$(basename "$t")" "$last"
  fi
done

# Every script the viewer loads must at least parse; a syntax error in any of
# them breaks the whole viewer.
for f in watch.js tv.js sw.js cast-sender.js js/*.js; do
  if node --check "$f" 2>/dev/null; then
    printf '  ok    %-32s parses\n' "$f"
  else
    printf '  FAIL  %-32s SYNTAX ERROR\n' "$f"; fail=1
  fi
done

# Balanced braces catch a truncated CSS append, which silently drops every
# rule after it — the failure mode of appending to a stylesheet with cat >>.
python3 - <<'PY' || fail=1
import sys
s = open('watch.css').read()
ok = s.count('{') == s.count('}')
print(f"  {'ok  ' if ok else 'FAIL'}  {'watch.css':<32} braces {s.count('{')}/{s.count('}')}")
sys.exit(0 if ok else 1)
PY

exit $fail
