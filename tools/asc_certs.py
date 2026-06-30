#!/usr/bin/env python3
"""Find (or create + import) an Apple signing certificate via the App Store Connect API, and print
its certificate id. Used by tools/submit-appstore.sh for MANUAL signing — cloud-managed signing
fails for this team's API key, but the key can create certs directly via REST.

Usage:  asc_certs.py <distribution|mac_installer>
Env:    ASC_KEY_ID, ASC_ISSUER_ID, ~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8 (or ASC_KEY_PATH)

If a usable cert of the requested type already exists in App Store Connect it is reused (its id is
printed). Otherwise a private key + CSR are generated with openssl, the cert is created via the API,
and BOTH the private key and the issued cert are imported into the login keychain (required for
xcodebuild to sign). The generated .p12/.cer live under build/ (gitignored).
"""
import sys, os, time, json, base64, subprocess, tempfile, urllib.request, urllib.error
import jwt

TYPE = {"distribution": "DISTRIBUTION", "mac_installer": "MAC_INSTALLER_DISTRIBUTION"}

def token():
    kid = os.environ["ASC_KEY_ID"]; iss = os.environ["ASC_ISSUER_ID"]
    kp = os.environ.get("ASC_KEY_PATH", os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8"))
    now = int(time.time())
    return jwt.encode({"iss": iss, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
                      open(kp).read(), algorithm="ES256", headers={"kid": kid, "typ": "JWT"})

def api(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, data=data,
            headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return json.load(r) if r.length != 0 else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"ASC API {method} {path} -> {e.code}: {e.read().decode()[:400]}")

def find(ctype):
    d = api("GET", "/v1/certificates?limit=200")
    for c in d.get("data", []):
        a = c["attributes"]
        if a.get("certificateType") == ctype:
            return c["id"]
    return None

def create_and_import(ctype):
    os.makedirs("build", exist_ok=True)
    key = os.path.join("build", f"{ctype.lower()}.key")
    csr = os.path.join("build", f"{ctype.lower()}.csr")
    subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", key, "-out", csr, "-subj", "/CN=Archive Watch/O=Learning is Change, Inc./C=US"],
                   check=True, capture_output=True)
    # csrContent is the raw PEM CSR string (WITH the BEGIN/END headers), NOT base64-of-the-file —
    # the latter is rejected 409 ENTITY_ERROR.ATTRIBUTE.INVALID "Invalid Certificate".
    body = {"data": {"type": "certificates",
                     "attributes": {"certificateType": ctype, "csrContent": open(csr).read()}}}
    d = api("POST", "/v1/certificates", body)
    cid = d["data"]["id"]
    cer = os.path.join("build", f"{ctype.lower()}.cer")
    open(cer, "wb").write(base64.b64decode(d["data"]["attributes"]["certificateContent"]))
    # Import the private key + issued cert into the login keychain so xcodebuild can sign.
    subprocess.run(["security", "import", key, "-k", os.path.expanduser("~/Library/Keychains/login.keychain-db"),
                    "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild"], check=False, capture_output=True)
    subprocess.run(["security", "import", cer, "-k", os.path.expanduser("~/Library/Keychains/login.keychain-db"),
                    "-T", "/usr/bin/codesign", "-T", "/usr/bin/productbuild"], check=False, capture_output=True)
    return cid

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in TYPE:
        raise SystemExit(__doc__)
    ctype = TYPE[sys.argv[1]]
    cid = find(ctype) or create_and_import(ctype)
    print(cid)

if __name__ == "__main__":
    main()
