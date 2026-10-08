#!/usr/bin/env python3
"""
asc_asset_library.py — App Store Connect's Asset Library (API 4.5, 2026-10-05)
for screenshots, the product page header and the search results asset.

The legacy appScreenshotSets API is deprecated and has NO iPhone Duo type
(ScreenshotDisplayType stops at APP_IPHONE_67), so every Duo screenshot and
every creative asset goes through here. The flow, from Apple's API reference:

  reserve   POST  /v1/appAssetLibraryImages          {category, fileName, fileSize}
  upload    PUT   each uploadOperations[] url        (pre-signed; no JWT)
  commit    PATCH /v1/appAssetLibraryImages/{id}      {uploaded: true}   (no checksum)
  poll      GET   /v1/appAssetLibraryImages/{id}      -> PREPARE_FOR_SUBMISSION | FAILED
  place     POST  /v1/appAssetLibraryPlacements       {placementType, placementGroup}
                  + image + appStoreVersionLocalization (must be EDITABLE: a new version)
  order     POST  /v1/appAssetLibraryPlacementOrderingRequests

placementGroup values come from GET /v1/appAssetLibraryRefData (read 2026-10-08):
  IPHONE_DUO_PROFILE, IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE, IPAD_13_PROFILE,
  MAC_PROFILE, TV_PROFILE; the header and search assets use DEFAULT_PROFILE.

Usage (tools/.play-venv/bin/python, with tools/asc-credentials.env sourced):
  asc_asset_library.py refdata
  asc_asset_library.py upload FILE --category screens|creative [--name NAME]
  asc_asset_library.py place IMAGE_ID --type APP_SCREENSHOT|PRODUCT_PAGE_HEADER_ASSET|APP_STORE_SEARCH_RESULTS_ASSET
                             --group GROUP --loc VERSION_LOCALIZATION_ID
  asc_asset_library.py order --group GROUP --loc LOC_ID PLACEMENT_ID...
  asc_asset_library.py list [--loc LOC_ID]
"""

import argparse
import json
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import asc_release as asc  # noqa: E402  (JWT + call() + app_id())

CATEGORY = {"screens": "APP_SCREENSHOTS_AND_PREVIEWS", "creative": "CREATIVE_ASSETS"}


def refdata():
    at = asc.call("v1/appAssetLibraryRefData")["data"]
    at = at["attributes"] if isinstance(at, dict) else at[0]["attributes"]
    spec = {s["specId"]: s for s in at["imageSpecs"]}
    for t in at["placementTypes"]:
        print(t["placementTypeId"], "accepts", t.get("acceptsAssetCategories"))
        for m in t.get("specMappings", []):
            sizes = [f'{spec[x]["dimensions"]["minWidth"]}x{spec[x]["dimensions"]["minHeight"]}'
                     f'{",".join(spec[x]["fileExtensions"])}' for x in m["specs"] if x in spec]
            print("   ", m["placementGroupId"], " ".join(sizes))


def upload(path, category, name=None):
    lib = asc.call(f"v1/apps/{asc.app_id()}/assetLibrary")["data"]["id"]
    size = os.path.getsize(path)
    body = {"data": {"type": "appAssetLibraryImages",
                     "attributes": {"category": CATEGORY[category],
                                    "fileName": os.path.basename(path), "fileSize": size,
                                    "referenceName": name or os.path.basename(path)},
                     "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": lib}}}}}
    img = asc.call("v1/appAssetLibraryImages", "POST", body)["data"]
    with open(path, "rb") as f:
        data = f.read()
    for op in img["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req, timeout=300) as r:
            if r.status >= 300:
                sys.exit(f"upload part failed: HTTP {r.status}")
    asc.call(f"v1/appAssetLibraryImages/{img['id']}", "PATCH",
             {"data": {"type": "appAssetLibraryImages", "id": img["id"], "attributes": {"uploaded": True}}})
    for _ in range(60):
        a = asc.call(f"v1/appAssetLibraryImages/{img['id']}")["data"]["attributes"]
        if a["state"] in ("PREPARE_FOR_SUBMISSION", "FAILED"):
            break
        time.sleep(5)
    print(json.dumps({"id": img["id"], "file": os.path.basename(path), "state": a["state"],
                      "specId": a.get("specId"), "detail": a.get("stateDetails")}))
    return img["id"], a["state"]


def place(image_id, ptype, group, loc):
    body = {"data": {"type": "appAssetLibraryPlacements",
                     "attributes": {"placementType": ptype, "placementGroup": group},
                     "relationships": {
                         "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                         "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}}}}}
    p = asc.call("v1/appAssetLibraryPlacements", "POST", body)["data"]
    print(json.dumps({"placement": p["id"], "state": p["attributes"].get("state")}))
    return p["id"]


def order(group, loc, ids):
    body = {"data": {"type": "appAssetLibraryPlacementOrderingRequests",
                     "attributes": {"placementGroup": group},
                     "relationships": {
                         "orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": i} for i in ids]},
                         "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc}}}}}
    asc.call("v1/appAssetLibraryPlacementOrderingRequests", "POST", body)
    print(f"ordered {len(ids)} in {group}")


def listing(loc=None):
    if loc:
        d = asc.call(f"v1/appStoreVersionLocalizations/{loc}/placements?sort=placementGroupPosition&limit=200&include=image")
        for p in d["data"]:
            print(p["id"], p["attributes"].get("placementType"), p["attributes"].get("placementGroup"),
                  p["attributes"].get("state"))
        return
    lib = asc.call(f"v1/apps/{asc.app_id()}/assetLibrary")["data"]["id"]
    d = asc.call(f"v1/appAssetLibraries/{lib}/images?limit=200")
    for i in d["data"]:
        at = i["attributes"]
        print(i["id"], at.get("state"), at.get("category"), at.get("referenceName"))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("refdata")
    u = sub.add_parser("upload"); u.add_argument("file"); u.add_argument("--category", choices=CATEGORY, required=True); u.add_argument("--name")
    p = sub.add_parser("place"); p.add_argument("image"); p.add_argument("--type", required=True); p.add_argument("--group", required=True); p.add_argument("--loc", required=True)
    o = sub.add_parser("order"); o.add_argument("ids", nargs="+"); o.add_argument("--group", required=True); o.add_argument("--loc", required=True)
    l = sub.add_parser("list"); l.add_argument("--loc")
    a = ap.parse_args()
    if a.cmd == "refdata":
        refdata()
    elif a.cmd == "upload":
        upload(a.file, a.category, a.name)
    elif a.cmd == "place":
        place(a.image, a.type, a.group, a.loc)
    elif a.cmd == "order":
        order(a.group, a.loc, a.ids)
    else:
        listing(a.loc)


if __name__ == "__main__":
    main()
