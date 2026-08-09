#!/usr/bin/env python3
"""Revoke the throwaway DEVELOPMENT certificates the cloud build mints each run.

WHY THIS EXISTS. `tools/submit-appstore.sh` archives with
`-allowProvisioningUpdates`, which lets Xcode provision on demand. Every GitHub
runner is a fresh machine with an empty keychain, so Xcode mints a NEW Apple
Development certificate on every single build. They accumulate on the account —
11 development certs by 2026-08-09, ten of them "Created via API", four from
that day alone — until Apple refuses:

    error: Choose a certificate to revoke. Your account has reached the maximum
    number of certificates.

At which point provisioning falls back to development profiles that do not
exist, the archive fails, and NOTHING can ship. That is what happened on
2026-08-09, three builds after the account filled.

These certificates are disposable by construction: the runner that owned the
private key was destroyed minutes after the build. Nothing can ever use them
again, so revoking them costs nothing and is exactly the action Apple's error
asks for.

WHAT IT WILL NOT TOUCH — the whole safety of this tool is in the narrowness of
what it selects:
  * DISTRIBUTION and MAC_INSTALLER_DISTRIBUTION certificates. Those are the ones
    that actually sign shipping builds and live in the repo's .p12 secrets.
  * Any development certificate NOT named "Created via API" — notably the
    owner's own "Ben Wilkoff" cert, which their local Xcode signs with. Revoking
    that would break the dev machine.
  * The newest --keep (default 2) API-created certs, in case a build is in
    flight while this runs.

Usage:
    python3 tools/asc_prune_certs.py            # report only
    python3 tools/asc_prune_certs.py --apply    # revoke
    python3 tools/asc_prune_certs.py --apply --keep 2 --older-than-days 0

Env: ASC_KEY_ID / ASC_ISSUER_ID / the .p8 in ~/.appstoreconnect/private_keys
(the same credentials asc_certs.py uses; source tools/asc-credentials.env).
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timedelta, timezone

sys.path.insert(0, __file__.rsplit("/", 1)[0])
import asc_certs as C  # noqa: E402  (shares the ASC JWT + api helper)

# The display name Xcode/the API gives a machine-provisioned certificate. A human
# cert carries the person's name instead, which is what keeps this off the
# owner's own signing identity.
API_NAME = "Created via API"
PROTECTED = {"DISTRIBUTION", "MAC_INSTALLER_DISTRIBUTION"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="actually revoke (default: report)")
    ap.add_argument("--keep", type=int, default=2,
                    help="keep this many of the newest API-created dev certs (default 2)")
    ap.add_argument("--older-than-days", type=int, default=0,
                    help="only revoke certs created more than this many days ago")
    args = ap.parse_args()

    certs = C.api("GET", "/v1/certificates?limit=200")["data"]

    def created(cert) -> datetime:
        # The API exposes expiration, not creation; Apple issues these for one
        # year, so expiry-minus-a-year orders them correctly.
        exp = cert["attributes"].get("expirationDate") or ""
        try:
            return datetime.fromisoformat(exp.replace("Z", "+00:00"))
        except ValueError:
            return datetime.now(timezone.utc)

    disposable = [c for c in certs
                  if c["attributes"].get("certificateType") == "DEVELOPMENT"
                  and (c["attributes"].get("displayName") or "") == API_NAME]
    disposable.sort(key=created, reverse=True)

    protected = [c for c in certs if c["attributes"].get("certificateType") in PROTECTED]
    human_dev = [c for c in certs
                 if c["attributes"].get("certificateType") == "DEVELOPMENT"
                 and (c["attributes"].get("displayName") or "") != API_NAME]

    print(f"{len(certs)} certificates on the account")
    print(f"  protected (distribution/installer): {len(protected)}")
    print(f"  human development (never touched):  {len(human_dev)}"
          + (f"  -> {', '.join((c['attributes'].get('displayName') or '?') for c in human_dev)}"
             if human_dev else ""))
    print(f"  machine '{API_NAME}' development:   {len(disposable)}")

    keep = disposable[:max(args.keep, 0)]
    rest = disposable[max(args.keep, 0):]
    if args.older_than_days > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.older_than_days)
        # created ~= expiry - 1y
        rest = [c for c in rest if created(c) - timedelta(days=365) < cutoff]

    print(f"\nkeeping {len(keep)} newest; {len(rest)} eligible to revoke")
    if not rest:
        print("nothing to do")
        return 0

    for c in rest:
        exp = (c["attributes"].get("expirationDate") or "")[:10]
        print(f"  {'REVOKE' if args.apply else 'would revoke'} {c['id']}  expires {exp}")
        if args.apply:
            try:
                C.api("DELETE", f"/v1/certificates/{c['id']}")
            except Exception as exc:                      # noqa: BLE001
                print(f"    failed: {type(exc).__name__} {exc}")
                return 1
    if not args.apply:
        print("\n(report only — pass --apply to revoke)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
