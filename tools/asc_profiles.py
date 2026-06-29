#!/usr/bin/env python3
"""Create + install App Store provisioning profiles for a set of bundle ids via the App Store Connect
API, and print a bundleID->profileUUID map (JSON). Used by tools/submit-appstore.sh for MANUAL signing,
because cloud-managed signing fails for this team's API key ("Cloud signing permission error") even
though the key can create certs/profiles directly via the REST API.

Usage:  asc_profiles.py <ios|tvos|mac> <distCertId> <bundleId> [bundleId ...]
Env:    ASC_KEY_ID, ASC_ISSUER_ID, and the .p8 at ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
        (or ASC_KEY_PATH). No secrets are written to the repo; profiles install to
        ~/Library/MobileDevice/Provisioning Profiles/.
"""
import sys, os, time, json, base64, urllib.request, urllib.error, urllib.parse
import jwt

PROFILE_TYPE = {"ios": "IOS_APP_STORE", "tvos": "TVOS_APP_STORE", "mac": "MAC_APP_STORE"}
EXT = {"ios": "mobileprovision", "tvos": "mobileprovision", "mac": "provisionprofile"}

def token():
    kid = os.environ["ASC_KEY_ID"]; iss = os.environ["ASC_ISSUER_ID"]
    kp = os.environ.get("ASC_KEY_PATH", os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8"))
    key = open(kp).read()
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": kid, "typ": "JWT"})

def api(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, data=data,
            headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, (json.load(r) if r.length != 0 else {})
    except urllib.error.HTTPError as e:
        raise SystemExit(f"ASC API {method} {path} -> {e.code}: {e.read().decode()[:400]}")

def bundle_resource_id(identifier):
    _, d = api("GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=20")
    for x in d.get("data", []):
        if x["attributes"]["identifier"] == identifier:
            return x["id"]
    raise SystemExit(f"bundle id not found in App Store Connect: {identifier} (register it first)")

def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    platform, dist_cert_id, bundle_ids = sys.argv[1], sys.argv[2], sys.argv[3:]
    ptype = PROFILE_TYPE[platform]; ext = EXT[platform]
    pdir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(pdir, exist_ok=True)
    out = {}
    for ident in bundle_ids:
        name = f"AW {platform} {ident}"
        # Delete any existing profile with this name (a stale one can't be reused if the cert changed).
        _, d = api("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(name)}&limit=20")
        for x in d.get("data", []):
            if x["attributes"]["name"] == name:
                api("DELETE", f"/v1/profiles/{x['id']}")
        bid = bundle_resource_id(ident)
        body = {"data": {"type": "profiles",
                         "attributes": {"name": name, "profileType": ptype},
                         "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}},
                                           "certificates": {"data": [{"type": "certificates", "id": dist_cert_id}]}}}}
        _, d = api("POST", "/v1/profiles", body)
        a = d["data"]["attributes"]
        path = os.path.join(pdir, f"{a['uuid']}.{ext}")
        open(path, "wb").write(base64.b64decode(a["profileContent"]))
        out[ident] = a["uuid"]
        print(f"  profile: {ident} -> {a['uuid']} ({name})", file=sys.stderr)
    print(json.dumps(out))

if __name__ == "__main__":
    main()
