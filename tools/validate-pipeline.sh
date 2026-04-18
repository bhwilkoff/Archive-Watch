#!/usr/bin/env bash
# tools/validate-pipeline.sh
#
# Run the same pipeline checks the tvOS EnrichmentService will run, but
# from the command line. For each Archive identifier passed in (or the
# default seed list), reports:
#
#   - title, year, mediatype
#   - external-identifier IMDb tt-ID (or "missing")
#   - playable derivative (h.264 MP4 / fallback) chosen by the same
#     ranking the Swift DerivativePicker uses
#   - file size + format
#   - direct download URL
#
# Requires: bash, curl, jq.
#
# Usage:
#   tools/validate-pipeline.sh                 # runs against the personal-favorites seed
#   tools/validate-pipeline.sh ID1 ID2 ...     # runs against given identifiers
#   tools/validate-pipeline.sh --json          # emits machine-readable JSON
#   tools/validate-pipeline.sh --tmdb          # also probes TMDb /find for any IMDb hits
#                                              #   (requires TMDB_BEARER_TOKEN env var)

set -euo pipefail

SEED=(
  Despotis1946
  DontBeaS1947
  democracy_1945
  george-formby-singing
  silent-tetherball-or-do-do
  silent-his-brave-defender
  casftm_000001
)

JSON_MODE=0
TMDB_PROBE=0
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=1 ;;
    --tmdb) TMDB_PROBE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *) ARGS+=("$arg") ;;
  esac
done
if [ "${#ARGS[@]}" -eq 0 ]; then
  ARGS=("${SEED[@]}")
fi

UA="ArchiveWatch/0.1 (+https://github.com/bhwilkoff/Archive-Watch)"

# Color helpers (skipped in JSON mode + when stdout isn't a tty).
if [ "$JSON_MODE" -eq 0 ] && [ -t 1 ]; then
  C_RESET=$'\e[0m'; C_DIM=$'\e[2m'; C_BOLD=$'\e[1m'
  C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_RED=$'\e[31m'; C_CYAN=$'\e[36m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

# Mirror of Swift DerivativePicker's tier predicates as a single jq
# script. Returns the highest-priority video file as JSON, or null.
JQ_PICKER='
  def is_video($f): ($f.format // "") | ascii_downcase
    | test("mp4|h\\.?264|mpeg-?4|ogg video|matroska|quicktime|avi|webm");
  def is_deriv($f): (($f.source // "") | ascii_downcase) == "derivative";
  def is_orig($f):  (($f.source // "") | ascii_downcase) == "original";
  def fmt($f): ($f.format // "") | ascii_downcase;

  def tiers: [
    {tier: 1, reason: "h.264 MP4 derivative",   pred: (. as $f | is_deriv($f) and (fmt($f) | test("h\\.?264")))},
    {tier: 2, reason: "MP4 derivative",         pred: (. as $f | is_deriv($f) and (fmt($f) | test("mp4")))},
    {tier: 3, reason: "512Kb MPEG4 derivative", pred: (. as $f | is_deriv($f) and (fmt($f) | test("512kb")) and (fmt($f) | test("mpeg-?4")))},
    {tier: 4, reason: "MPEG4 derivative",       pred: (. as $f | is_deriv($f) and (fmt($f) | test("mpeg-?4")))},
    {tier: 5, reason: "WebM/Matroska/Ogg",      pred: (. as $f | is_deriv($f) and (fmt($f) | test("webm|matroska|ogg")))},
    {tier: 6, reason: "MP4/H.264 original",     pred: (. as $f | is_orig($f) and (fmt($f) | test("mp4|h\\.?264")))},
    {tier: 7, reason: "Any video original",     pred: (. as $f | is_orig($f))}
  ];

  . as $files
  | [$files[] | select(. as $f | is_video($f))] as $videos
  | if ($videos | length) == 0 then null
    else
      [tiers[] as $t
       | {tier: $t.tier, reason: $t.reason,
          best: ([$videos[]
                  | . as $f
                  | select($t.pred)
                  | {name, format, source, size, sizeBytes: ((.size // "0") | tonumber? // 0)}]
                 | sort_by(-.sizeBytes) | first)}
      ]
      | map(select(.best != null))
      | first
    end
'

emit_human() {
  local id="$1" json="$2"
  local title year mediatype imdb pick_tier pick_reason pick_name pick_format pick_size collections subjects download
  title=$(printf "%s" "$json" | jq -r '.metadata.title // "(no title)"')
  year=$(printf "%s" "$json" | jq -r '.metadata.year // .metadata.date // "—"' | head -c 4)
  mediatype=$(printf "%s" "$json" | jq -r '.metadata.mediatype // "—"')
  collections=$(printf "%s" "$json" | jq -r '.metadata.collection // [] | if type=="array" then join(", ") else . end')
  subjects=$(printf "%s" "$json" | jq -r '.metadata.subject // [] | if type=="array" then (. | join(", ") | .[0:80]) else . end')
  imdb=$(printf "%s" "$json" | jq -r '
    .metadata."external-identifier" // []
    | if type=="array" then . else [.] end
    | map(select(. | test("(?i)tt[0-9]{6,10}")))
    | if length==0 then "missing" else (.[0] | match("(?i)tt[0-9]{6,10}") | .string) end
  ')
  pick=$(printf "%s" "$json" | jq -c ".files | $JQ_PICKER")
  pick_tier=$(printf "%s" "$pick" | jq -r '.tier // "—"')
  pick_reason=$(printf "%s" "$pick" | jq -r '.reason // "(no playable derivative)"')
  pick_name=$(printf "%s" "$pick" | jq -r '.best.name // "—"')
  pick_format=$(printf "%s" "$pick" | jq -r '.best.format // "—"')
  pick_size=$(printf "%s" "$pick" | jq -r '.best.sizeBytes // 0' | awk '{printf "%.1f MB", $1/1048576}')

  local imdb_color
  if [ "$imdb" = "missing" ]; then imdb_color="$C_YELLOW$imdb$C_RESET"; else imdb_color="$C_GREEN$imdb$C_RESET"; fi

  local pick_color
  if [ "$pick_name" = "—" ]; then pick_color="$C_RED"; else pick_color="$C_GREEN"; fi

  printf "${C_BOLD}%s${C_RESET}\n" "$id"
  printf "  ${C_DIM}title:${C_RESET}      %s (%s)\n" "$title" "$year"
  printf "  ${C_DIM}mediatype:${C_RESET}  %s\n" "$mediatype"
  printf "  ${C_DIM}IMDb:${C_RESET}       %s\n" "$imdb_color"
  printf "  ${C_DIM}derivative:${C_RESET} ${pick_color}tier %s · %s${C_RESET}\n" "$pick_tier" "$pick_reason"
  printf "  ${C_DIM}file:${C_RESET}       %s [%s, %s]\n" "$pick_name" "$pick_format" "$pick_size"
  printf "  ${C_DIM}url:${C_RESET}        ${C_CYAN}https://archive.org/download/%s/%s${C_RESET}\n" "$id" "$pick_name"
  printf "  ${C_DIM}collections:${C_RESET} %s\n" "$collections"
  printf "  ${C_DIM}subjects:${C_RESET}   %s\n" "$subjects"

  if [ "$TMDB_PROBE" -eq 1 ] && [ "$imdb" != "missing" ]; then
    if [ -z "${TMDB_BEARER_TOKEN:-}" ]; then
      printf "  ${C_DIM}TMDb:${C_RESET}       ${C_YELLOW}skipped (set TMDB_BEARER_TOKEN to enable)${C_RESET}\n"
    else
      tmdb=$(curl -sS \
        -H "Authorization: Bearer $TMDB_BEARER_TOKEN" \
        -H "Accept: application/json" \
        "https://api.themoviedb.org/3/find/${imdb}?external_source=imdb_id&language=en-US" \
        || true)
      hit_count=$(printf "%s" "$tmdb" | jq '(.movie_results // []) | length' 2>/dev/null || echo 0)
      if [ "$hit_count" -gt 0 ]; then
        tmdb_title=$(printf "%s" "$tmdb" | jq -r '.movie_results[0].title // "?"')
        tmdb_year=$(printf "%s" "$tmdb" | jq -r '.movie_results[0].release_date // "—" | .[0:4]')
        tmdb_id=$(printf "%s" "$tmdb" | jq -r '.movie_results[0].id // "—"')
        printf "  ${C_DIM}TMDb:${C_RESET}       ${C_GREEN}match #%s · %s (%s)${C_RESET}\n" "$tmdb_id" "$tmdb_title" "$tmdb_year"
      else
        printf "  ${C_DIM}TMDb:${C_RESET}       ${C_YELLOW}no match${C_RESET}\n"
      fi
    fi
  fi
  echo ""
}

emit_json() {
  local id="$1" json="$2"
  printf "%s" "$json" | jq --arg id "$id" --argjson picker "$(echo "$JQ_PICKER" | jq -Rs .)" '
    {
      id: $id,
      title: .metadata.title,
      year: ((.metadata.year // .metadata.date // "") | .[0:4]),
      mediatype: .metadata.mediatype,
      collections: (.metadata.collection // [] | if type=="array" then . else [.] end),
      external_identifiers: (.metadata."external-identifier" // [] | if type=="array" then . else [.] end),
      file_count: (.files | length),
      pick: (.files | '"$JQ_PICKER"')
    }
  '
}

[ "$JSON_MODE" -eq 1 ] && echo "["
first=1
exit_code=0
for id in "${ARGS[@]}"; do
  if json=$(curl -sS --fail -A "$UA" "https://archive.org/metadata/$id"); then
    if [ "$JSON_MODE" -eq 1 ]; then
      [ "$first" -eq 0 ] && echo ","
      emit_json "$id" "$json"
    else
      emit_human "$id" "$json"
    fi
  else
    if [ "$JSON_MODE" -eq 1 ]; then
      [ "$first" -eq 0 ] && echo ","
      printf '{"id":"%s","error":"fetch failed"}' "$id"
    else
      printf "${C_RED}%s${C_RESET}: fetch failed\n\n" "$id"
    fi
    exit_code=1
  fi
  first=0
  # Be polite — Archive.org rate-limits aggressive callers.
  sleep 0.4
done
[ "$JSON_MODE" -eq 1 ] && echo "]"

exit $exit_code
