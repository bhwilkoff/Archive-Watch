#!/usr/bin/env python3
"""
asc_stage_assets.py — put Asset Library images on a NEW App Store version, in
order, replacing what the version inherited. Run after `asc_release.py ship`
(without --submit) has opened the version, and before submitting it.

    asc_stage_assets.py --version 1.46.0 --uploads uploads.jsonl [--dry-run]

`uploads.jsonl` is the log of `asc_asset_library.py upload` (one JSON object a
line: id, file, state). Images are matched to a placement group by the
referenceName they were uploaded with ("2026-10 <slot> <NN-name>"), so the
mapping below is the whole policy:

    slot          platform  group                                  type
    iphone        IOS       IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE   APP_SCREENSHOT
    iphone-large  IOS       IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE    APP_SCREENSHOT
    ipad          IOS       IPAD_13_PROFILE                        APP_SCREENSHOT
    mac           MAC_OS    MAC_PROFILE                            APP_SCREENSHOT
    tv            TV_OS     TV_PROFILE                             APP_SCREENSHOT
    header        IOS       DEFAULT_PROFILE                        PRODUCT_PAGE_HEADER_ASSET
    search        IOS       DEFAULT_PROFILE                        APP_STORE_SEARCH_RESULTS_ASSET

The closed-Duo set (IPHONE_DUO_PROFILE) is deliberately NOT here: it shows the
iOS 27.1 SDK's side-strip layout, and a store build made with an earlier SDK
does not have it (docs/research/IPHONE-DUO.md). Stage it with the first 27.1
build.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import asc_release as asc  # noqa: E402

GROUPS = {
    "iphone": ("IOS", "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE", "APP_SCREENSHOT"),
    "iphone-large": ("IOS", "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE", "APP_SCREENSHOT"),
    "ipad": ("IOS", "IPAD_13_PROFILE", "APP_SCREENSHOT"),
    "mac": ("MAC_OS", "MAC_PROFILE", "APP_SCREENSHOT"),
    "tv": ("TV_OS", "TV_PROFILE", "APP_SCREENSHOT"),
    "header": ("IOS", "DEFAULT_PROFILE", "PRODUCT_PAGE_HEADER_ASSET"),
    "search": ("IOS", "DEFAULT_PROFILE", "APP_STORE_SEARCH_RESULTS_ASSET"),
}


def localization(aid, platform, version):
    vs = asc.call(f"v1/apps/{aid}/appStoreVersions?filter[platform]={platform}"
                  f"&filter[versionString]={version}&limit=5")["data"]
    if not vs:
        sys.exit(f"no {platform} version {version} — run asc_release.py ship first")
    state = vs[0]["attributes"].get("appStoreState")
    locs = asc.call(f"v1/appStoreVersions/{vs[0]['id']}/appStoreVersionLocalizations?limit=50")["data"]
    en = next((l for l in locs if l["attributes"]["locale"] == "en-US"), None)
    if not en:
        sys.exit(f"{platform} {version} has no en-US localization")
    return en["id"], state


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--uploads", required=True)
    ap.add_argument("--header")
    ap.add_argument("--search")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    rows = [json.loads(l) for l in open(a.uploads) if l.startswith("{")]
    lib = asc.call(f"v1/apps/{asc.app_id()}/assetLibrary")["data"]["id"]
    names = {i["id"]: i["attributes"].get("referenceName") or ""
             for i in asc.call(f"v1/appAssetLibraries/{lib}/images?limit=200")["data"]}
    by_slot = {}
    for r in rows:
        ref = names.get(r["id"], "")
        parts = ref.split(" ", 2)
        if len(parts) == 3 and parts[0] == "2026-10" and parts[1] in GROUPS:
            by_slot.setdefault(parts[1], []).append((parts[2], r["id"]))
    if a.header:
        by_slot["header"] = [("header", a.header)]
    if a.search:
        by_slot["search"] = [("search", a.search)]

    aid = asc.app_id()
    loc_cache = {}
    for slot, (platform, group, ptype) in GROUPS.items():
        images = sorted(by_slot.get(slot, []))
        if not images:
            continue
        if platform not in loc_cache:
            loc_cache[platform] = localization(aid, platform, a.version)
        loc, state = loc_cache[platform]
        existing = asc.call(f"v1/appStoreVersionLocalizations/{loc}/placements?limit=200")["data"]
        old = [p for p in existing if p["attributes"].get("placementGroup") == group
               and p["attributes"].get("placementType") == ptype]
        print(f"{platform} {state} {group} {ptype}: replace {len(old)} with {len(images)}")
        if a.dry_run:
            continue
        for p in old:
            asc.call(f"v1/appAssetLibraryPlacements/{p['id']}", "DELETE")
        placed = []
        for name, image_id in images:
            body = {"data": {"type": "appAssetLibraryPlacements",
                             "attributes": {"placementType": ptype, "placementGroup": group},
                             "relationships": {
                                 "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                                 "appStoreVersionLocalization": {
                                     "data": {"type": "appStoreVersionLocalizations", "id": loc}}}}}
            placed.append(asc.call("v1/appAssetLibraryPlacements", "POST", body)["data"]["id"])
        if len(placed) > 1:
            asc.call("v1/appAssetLibraryPlacementOrderingRequests", "POST", {"data": {
                "type": "appAssetLibraryPlacementOrderingRequests",
                "attributes": {"placementGroup": group},
                "relationships": {
                    "orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": i} for i in placed]},
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}}}}})
        print(f"   placed {len(placed)}")


if __name__ == "__main__":
    main()
