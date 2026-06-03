# Runbook — recover the full catalog after a clobber

The catalog (`catalog.json`, ~30k items) lives on the `catalog-source` GitHub
Release, not in git (Decision 018). Release assets are clobbered on each publish,
so a bad publish leaves no version history on the release itself. This is how to
recover. It actually happened on 2026-06-03 (see Decision 020) and both paths
below were verified to work.

## Symptom
`catalog-source` asset (`catalog.json.gz`) suddenly small, or the app DB
(`catalog-db` → `catalog.sqlite`) drops from ~26k items to ~1k. Confirm:

```sh
python tools/catalog_release.py fetch
python3 -c "import json; print(len(json.load(open('catalog.json'))['items']))"
```

## Path A — dangling pre-Decision-018 git commit (BEST: fullest, ~30k)
The catalog WAS committed in git until Decision 018 removed it (2026-06-02), then
`git filter-repo` purged the blobs and force-pushed. GitHub keeps the unreachable
("dangling") commits for ~90 days, fetchable by full SHA.

```sh
# 1. Find the history rewrite — the force_push 'before' SHA is the old tip.
gh api "repos/bhwilkoff/Archive-Watch/activity?per_page=100" \
  | python3 -c "import json,sys; [print(a['before'],a['timestamp']) for a in json.load(sys.stdin) if a.get('activity_type')=='force_push']"

# 2. Fetch that dangling commit (GitHub serves it by full SHA even unreachable).
git fetch origin <OLD_TIP_SHA>

# 3. Walk its ancestry to the last commit that still had catalog.json
#    (the parent of the "Decision 018 …" removal commit).
git log <OLD_TIP_SHA> -- catalog.json | head

# 4. Extract it.
git show <THAT_SHA>:catalog.json > catalog.json
```

On 2026-06-03 this yielded commit `5ef1795` with **30,645 items** — more than was
lost. After ~90 days the dangling objects may be GC'd; Path B is the fallback.

## Path B — the simulator's cached full DB (fallback, ~1 day stale)
The app downloads the full DB and caches it. Rebuild `catalog.json` from its
`item_json` table.

```sh
find ~/Library/Developer/CoreSimulator -name catalog.sqlite -size +50M
python3 - <<'PY'
import sqlite3, json, datetime
db = sqlite3.connect("<PATH>/catalog.sqlite")
items = [json.loads(r[0]) for r in db.execute("SELECT json FROM item_json")]
json.dump({"version":2,
           "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
           "generator":"recovery-from-cached-sqlite",
           "stats":{"totalItems":len(items)}, "items":items},
          open("catalog.json","w"), ensure_ascii=False)
print("recovered", len(items))
PY
```

## Finish (both paths)
```sh
python tools/remediate_catalog.py          # re-apply deterministic data fixes
python tools/catalog_release.py publish     # gzip + clobber catalog-source
gh workflow run publish-db.yml              # rebuild the app DB (catalog-db)
rm -f catalog.json
```

## Re-apply lost network enrichment
The recovered catalog predates whatever enrichment drained after its snapshot.
The enrichment workflows are idempotent (fill only gaps) — dispatch them
**one at a time** (the `catalog-writers` concurrency group keeps only one pending
run, so firing several at once cancels the middle ones):

```sh
gh workflow run wikidata-posters.yml   && gh run watch <id> --exit-status
gh workflow run omdb-backfill.yml      && gh run watch <id> --exit-status
gh workflow run wikipedia-synopsis.yml && gh run watch <id> --exit-status
```

Commons posters + Wikipedia synopses re-fill from the network; OMDb cast/identity
drains over days (~950/day) via the daily cron — that's by design, not a failure.

## Prevention
Decision 020: catalog-mutating builds are additive + merge-guarded
(`tools/merge_catalogs.py`), so a build can never replace the catalog again.
