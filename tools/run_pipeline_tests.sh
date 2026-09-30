#!/usr/bin/env bash
# The catalog pipeline's own tests, run before publish-db builds anything.
# Until 2026-09-29 none of these ran in CI: two had been failing unnoticed
# (a rights bucket with no Studio sentence, a Roku feed expectation). A red
# test here stops the publish, so the last good database stays live.
# Every test listed must pass in a FRESH checkout (film_feeds reads a
# generated file, so it is not here); check with a clean clone.
set -u
cd "$(dirname "$0")/.."
TESTS="
audit_rights cleared_match_residue copyright_evidence cce_renewals tidy_credits scrub_cleared_match
propaganda_no_recommend uraa_no_recommend old_year_on_newer_upload title_identity title_cast_tail
title_handle_and_rejects accent_title uploader_voice placeholder_year title_file_pick shot_log colorized_versions list_synopsis catalog_merge prelinger_claim rights_assertions match_release_year cce_alternate placeholder_synopsis
synopsis_pointers synopsis_punctuation family_genre hand_year_holds
runtime_match_gate unanchored_tmdb_residue tv_rights_gate tv_rights_items
takedowns quoted_title_merge related channel_schedule caps_credit_title
roku_search_feed details_contract no_evidence_gate color_guard review_filter
wikipedia_lead resolve_title series_collections episode_url index_bif_column
studio_rights_coverage studio_rights_parity web_adult_gate hero_rule_parity
search_rank_parity discovery_queue_merge private_derivative mcp_data
"
fail=0; n=0
for t in $TESTS; do
  n=$((n+1))
  if ! out=$(python3 "tools/test_$t.py" 2>&1 </dev/null); then
    fail=$((fail+1)); echo "FAIL test_$t"; echo "$out" | tail -8
  fi
done
echo "pipeline tests: $((n-fail))/$n passed"
[ "$fail" -eq 0 ]
