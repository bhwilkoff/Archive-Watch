#!/usr/bin/env python3
"""Mint a dedicated App Store signing certificate via the ASC API and bundle it (leaf cert + its
private key) into a password-protected .p12 — with NO keychain import and NO interactive prompt — so
it can seed a GitHub Actions secret for the cloud build workflow (.github/workflows/appstore-build.yml).
Prints "<certId>\t<p12Path>" on success.

Why a dedicated CI cert (not the existing one): the existing Apple Distribution cert's private key is
in the login keychain, and exporting it triggers a GUI auth prompt. Minting a fresh cert gives us the
private key locally (we generate the keypair), so the .p12 is built with openssl, no prompt. Apple
allows 2 Apple Distribution certs; this uses the 2nd slot. Local builds are dead (beta-OS, ITMS-90301),
so the CI cert becomes the one that owns the App Store provisioning profiles.

Usage:  ci_make_signing_p12.py <distribution|mac_installer> <out.p12> <p12password>
Env:    ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8). NOTHING is written to git (build/ ignored).
"""
import sys, os, time, json, base64, subprocess, urllib.request, urllib.error
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


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in TYPE:
        raise SystemExit(__doc__)
    ctype = TYPE[sys.argv[1]]; out_p12 = sys.argv[2]; pw = sys.argv[3]
    os.makedirs("build", exist_ok=True)
    base = os.path.join("build", f"ci_{ctype.lower()}")
    key, csr, cer, pem = base + ".key", base + ".csr", base + ".cer", base + ".pem"
    subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", key, "-out", csr,
                    "-subj", "/CN=Archive Watch CI/O=Learning is Change, Inc./C=US"],
                   check=True, capture_output=True)
    # csrContent is the raw PEM CSR string (WITH the BEGIN/END headers) — NOT base64-of-the-file.
    # (Base64-encoding the PEM is rejected 409 ENTITY_ERROR.ATTRIBUTE.INVALID "Invalid Certificate".)
    d = api("POST", "/v1/certificates",
            {"data": {"type": "certificates",
                      "attributes": {"certificateType": ctype, "csrContent": open(csr).read()}}})
    cid = d["data"]["id"]
    open(cer, "wb").write(base64.b64decode(d["data"]["attributes"]["certificateContent"]))
    # DER cert -> PEM, then leaf + key -> .p12 (no chain; the CI runner's keychain supplies the
    # Apple WWDR intermediate, and the workflow also imports it explicitly as insurance).
    subprocess.run(["openssl", "x509", "-inform", "DER", "-in", cer, "-out", pem],
                   check=True, capture_output=True)
    # -legacy: OpenSSL 3 defaults to PBES2/AES-256/SHA-256, which macOS `security import` CANNOT read
    # ("MAC verification failed"). -legacy uses SHA1/3DES PBE that the macOS keychain accepts.
    subprocess.run(["openssl", "pkcs12", "-export", "-legacy", "-inkey", key, "-in", pem,
                    "-out", out_p12, "-passout", f"pass:{pw}", "-name", f"AW CI {sys.argv[1]}"],
                   check=True, capture_output=True)
    print(f"{cid}\t{out_p12}")


if __name__ == "__main__":
    main()
