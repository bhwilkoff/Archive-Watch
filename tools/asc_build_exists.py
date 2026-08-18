#!/usr/bin/env python3
"""Has this build number already been uploaded to App Store Connect?

The archive is the expensive step — signing, three platforms, tens of minutes —
and ASC rejects a duplicate build number only at the END of it. A run failed
exactly that way on 2026-08-18: a dispatch went out alongside a push that had
been rejected (the remote had moved under it), CI checked out a tree without
the version bump, and spent the whole archive rebuilding an already-uploaded
946 before being told no.

Exit 1 when the version/build pair is already on ASC, so the workflow can stop
in seconds instead of at the end. Never fails the build on its own account: if
ASC cannot be reached, it says so and exits 0 — a guard that blocks shipping
because it could not check is worse than no guard.

Usage: python3 tools/asc_build_exists.py <marketing_version> <build_number>
"""
import sys

try:
    import asc_certs as C
except Exception as e:                      # pragma: no cover - import guard
    print(f"[asc] cannot load the ASC client ({e}); skipping the check")
    sys.exit(0)

APP_BUNDLE = "app.archivewatch.tvos"


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: asc_build_exists.py <version> <build>")
        return 0
    version, build = sys.argv[1], sys.argv[2]
    try:
        apps = C.api("GET", f"/v1/apps?filter[bundleId]={APP_BUNDLE}")
        data = apps.get("data") or []
        if not data:
            print(f"[asc] no app for {APP_BUNDLE}; skipping the check")
            return 0
        app_id = data[0]["id"]
        # Ask for THIS build number directly rather than paging the history.
        res = C.api("GET", f"/v1/builds?filter[app]={app_id}"
                           f"&filter[version]={build}&limit=5")
        hits = res.get("data") or []
    except Exception as e:
        print(f"[asc] could not reach App Store Connect ({e}); skipping the check")
        return 0

    if hits:
        print(f"[asc] build {build} is ALREADY uploaded — archiving it again "
              f"would be rejected at the end. Bump CURRENT_PROJECT_VERSION, "
              f"and check that the bump was actually PUSHED before dispatching.")
        return 1
    print(f"[asc] build {build} (v{version}) is new — proceeding")
    return 0


if __name__ == "__main__":
    sys.exit(main())
