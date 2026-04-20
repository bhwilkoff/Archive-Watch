#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Full overnight pipeline runner for Archive Watch.
# ---------------------------------------------------------------------------
# Chains: ingest → derivative resolution → HEAD verification →
# tiered export (seed + full) → validate. Every step is idempotent /
# resumable, so if the run dies partway through, re-running continues
# from where it stopped without re-scraping or re-resolving done work.
#
# Logs go to /tmp/archive_watch_pipeline.log; `tail -f` to watch.
# Final artifacts:
#   • SchemaWork/video_registry.db            — source of truth DB
#   • ArchiveWatch/ArchiveWatch/catalog.json  — bundled seed (~5–10 MB)
#   • docs/catalog.json                       — hosted full catalog
#   • tools/validation_report.txt             — final guardrails result
#
# Usage:
#   tools/run_full_pipeline.sh            # full run, all sources
#   tools/run_full_pipeline.sh --smoke    # --limit 50 per collection, no SPARQL
#
# Safe to Ctrl-C: partial state survives; re-invoking picks up.

set -eo pipefail  # fail fast; but each step wrapped to survive transient HTTP

# ---- setup ----------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LOG=/tmp/archive_watch_pipeline.log
DB=SchemaWork/video_registry.db
: > "$LOG"   # truncate log so each run starts fresh

SMOKE=false
for arg in "$@"; do
    case "$arg" in
        --smoke) SMOKE=true ;;
    esac
done

# Helpers — timestamped log + run-with-logging
ts()  { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "[$(ts)] $*" | tee -a "$LOG"; }
run() {
    log "▸ $*"
    if ! "$@" >>"$LOG" 2>&1; then
        log "✗ command failed: $*"
        # Don't bail out on transient HTTP errors — the pipeline is designed
        # to be re-run and pick up where it left off. Keep going.
        return 0
    fi
}

log "=========================================="
log "Archive Watch pipeline run (smoke=$SMOKE)"
log "=========================================="

# ---- 1. Ingest ------------------------------------------------------------

if $SMOKE; then
    log "[1/5] INGEST (smoke: 50 per collection, IA only, no SPARQL)"
    run python3 SchemaWork/registry_pipeline.py \
        --limit 50 --sources ia --skip-enrichment
else
    log "[1/5] INGEST (full: all sources, full Wikidata SPARQL enrichment)"
    run python3 SchemaWork/registry_pipeline.py
fi

# ---- 2. Resolve archive.org derivatives ----------------------------------

log "[2/5] RESOLVE derivatives (hit /metadata/{id} for every IA source,"
log "       pick best h.264 MP4, detect audio absence, promote silent flag)"
run python3 SchemaWork/registry_pipeline.py --resolve-derivatives

# ---- 3. HEAD-verify playability ------------------------------------------

log "[3/5] VERIFY playability (HEAD every stream URL)"
run python3 SchemaWork/registry_pipeline.py --verify-playable

# ---- 4. Export both tiers -------------------------------------------------

mkdir -p docs

log "[4a/5] EXPORT seed (bundled, diversity-aware, ~3k items)"
run python3 tools/export_catalog.py \
    --mode seed \
    --out ArchiveWatch/ArchiveWatch/catalog.json

log "[4b/5] EXPORT full (hosted, ~25k items)"
run python3 tools/export_catalog.py \
    --mode full \
    --out docs/catalog.json

# ---- 5. Validate ----------------------------------------------------------

log "[5/5] VALIDATE exports"
python3 tools/validate_export.py \
    --catalog ArchiveWatch/ArchiveWatch/catalog.json \
    --featured featured.json \
    > tools/validation_report.txt 2>&1 || true
log "validation report written to tools/validation_report.txt"

log "=========================================="
log "DONE. Summary:"
if [[ -f "$DB" ]]; then
    log "  DB size: $(du -h "$DB" | awk '{print $1}')"
fi
if [[ -f ArchiveWatch/ArchiveWatch/catalog.json ]]; then
    log "  seed: $(du -h ArchiveWatch/ArchiveWatch/catalog.json | awk '{print $1}')"
fi
if [[ -f docs/catalog.json ]]; then
    log "  full: $(du -h docs/catalog.json | awk '{print $1}')"
fi
log "  validation: tools/validation_report.txt"
log "=========================================="
