#!/usr/bin/env python3
"""tools/secrets.sh refuses anything but its fixed recipes and never prints a value or puts one
on a command line (docs/research/SECRETS-PLAN.md).

Every recipe runs against a fake store: gh, npx (wrangler), security and openssl are stand-ins on
PATH that keep values in a temp directory and log their own command lines, and the signing script
is a stand-in too. Planted values must reach the right store and appear in no output and no
command line. Negative controls: copies of the script that echo a value, or pass one as an
argument, must be caught.  Run: python3 tools/test_secrets_sh.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "secrets.sh")

RAND = "PLANTEDrandomSESSIONvalue0123456789abcdefABCDEFghij+/=="
PW = "PLANTEDp12password0123456789abcdef0123"
PEM = "-----BEGIN PRIVATE KEY-----\nPLANTEDpemBODYforTHEtest0123456789\n-----END PRIVATE KEY-----\n"
P12 = b"PLANTEDp12bytes\x00\x01"
ISSUER = "12345678-abcd-4ef0-9abc-1234567890ab"

FAKES = {
    "gh": r'''
import os, sys
S = os.environ["FAKE_STORE"]; a = sys.argv[1:]
open(os.path.join(S, "argv.log"), "a").write("gh " + " ".join(a) + "\n")
if a[:2] == ["secret", "set"]:
    os.makedirs(os.path.join(S, "gh"), exist_ok=True)
    open(os.path.join(S, "gh", a[2]), "w").write(sys.stdin.read())
elif a[:2] == ["secret", "delete"]:
    p = os.path.join(S, "gh", a[2])
    if os.path.exists(p): os.remove(p)
elif a[:2] == ["secret", "list"]:
    d = os.path.join(S, "gh")
    for n in sorted(os.listdir(d)) if os.path.isdir(d) else ["ASC_KEY_ID"]:
        print(n)
else:
    sys.exit("fake gh: " + " ".join(a))
''',
    "npx": r'''
import json, os, sys
S = os.environ["FAKE_STORE"]; a = [("wrangler" if x.startswith("wrangler@") else x) for x in sys.argv[1:] if x not in ("--no-install", "--yes")]
open(os.path.join(S, "argv.log"), "a").write("npx " + " ".join(a) + "\n")
d = os.path.join(S, "worker"); os.makedirs(d, exist_ok=True)
if a[:3] == ["wrangler", "secret", "put"]:
    open(os.path.join(d, a[3]), "w").write(sys.stdin.read())
    print("Success! Uploaded secret " + a[3])
elif a[:3] == ["wrangler", "secret", "delete"]:
    sys.stdin.read()
    if os.environ.get("FAKE_WRANGLER_FAILS"): sys.exit("fake wrangler: not logged in")
    p = os.path.join(d, a[3])
    if os.path.exists(p): os.remove(p)
elif a[:3] == ["wrangler", "secret", "list"]:
    print(json.dumps([{"name": n, "type": "secret_text"} for n in sorted(os.listdir(d))]))
else:
    sys.exit("fake npx: " + " ".join(a))
''',
    "security": r'''
import os, shlex, sys
S = os.environ["FAKE_STORE"]; a = sys.argv[1:]
open(os.path.join(S, "argv.log"), "a").write("security " + " ".join(a) + "\n")
d = os.path.join(S, "kc"); os.makedirs(d, exist_ok=True)
def opt(args, k): return args[args.index(k) + 1]
if a and a[0] == "find-generic-password":
    p = os.path.join(d, opt(a, "-s"))
    if not os.path.exists(p): sys.exit(44)
    sys.stdout.write(open(p).read() + "\n")
elif a and a[0] == "delete-generic-password":
    p = os.path.join(d, opt(a, "-s"))
    if os.path.exists(p): os.remove(p)
elif a == ["-i"]:
    for line in sys.stdin:
        w = shlex.split(line)
        if w and w[0] == "add-generic-password":
            open(os.path.join(d, opt(w, "-s")), "w").write(opt(w, "-w"))
            print("security> ")
elif a and a[0] == "dump-keychain":
    print('    "svce"<blob>="someone-else:THING"')
    for n in sorted(os.listdir(d)):
        print('    "svce"<blob>="%s"' % n)
else:
    sys.exit("fake security: " + " ".join(a))
''',
    "openssl": r'''
import os, sys
S = os.environ["FAKE_STORE"]; a = sys.argv[1:]
open(os.path.join(S, "argv.log"), "a").write("openssl " + " ".join(a) + "\n")
if a[:2] == ["rand", "-base64"]: print(os.environ["PLANT_RAND"])
elif a[:2] == ["rand", "-hex"]: print(os.environ["PLANT_PW"])
else: sys.exit("fake openssl: " + " ".join(a))
''',
}

FAKE_SIGNING = r'''
import base64, os, sys
S = os.environ["FAKE_STORE"]
kind, out, pw = sys.argv[1:4]
ok = (pw == "-" and os.environ.get("P12_PASSWORD") == os.environ["PLANT_PW"]
      and base64.b64decode(os.environ["ASC_KEY_P8"]).decode() == os.environ["PLANT_PEM"]
      and os.environ.get("ASC_ISSUER_ID") == os.environ["PLANT_ISSUER"])
open(os.path.join(S, "signing.log"), "a").write(f"{kind} {'env-ok' if ok else 'env-WRONG'}\n")
open(out, "wb").write(b"PLANTEDp12bytes\x00\x01")
print(f"CERT{kind.upper()}\t{out}")
'''


def make_world(script_text):
    w = tempfile.mkdtemp(prefix="secrets-test-")
    os.makedirs(os.path.join(w, "root", "tools"))
    os.makedirs(os.path.join(w, "root", "worker"))
    os.makedirs(os.path.join(w, "bin"))
    os.makedirs(os.path.join(w, "store"))
    os.makedirs(os.path.join(w, "tmp"))
    os.makedirs(os.path.join(w, "home", ".appstoreconnect", "private_keys"))
    s = os.path.join(w, "root", "tools", "secrets.sh")
    open(s, "w").write(script_text)
    os.chmod(s, 0o755)
    open(os.path.join(w, "root", "tools", "ci_make_signing_p12.py"), "w").write(FAKE_SIGNING)
    for name, body in FAKES.items():
        p = os.path.join(w, "bin", name)
        open(p, "w").write("#!" + sys.executable + "\n" + body)
        os.chmod(p, 0o755)
    return w


def run(w, *args):
    env = {**os.environ, "PATH": os.path.join(w, "bin") + os.pathsep + os.environ["PATH"],
           "FAKE_STORE": os.path.join(w, "store"), "HOME": os.path.join(w, "home"), "TMPDIR": os.path.join(w, "tmp"),
           "PLANT_RAND": RAND, "PLANT_PW": PW, "PLANT_PEM": PEM, "PLANT_ISSUER": ISSUER}
    r = subprocess.run(["bash", os.path.join(w, "root", "tools", "secrets.sh"), *args], env=env,
                       capture_output=True, text=True, timeout=60)
    return r.returncode, r.stdout + r.stderr


def read(w, *p):
    path = os.path.join(w, "store", *p)
    return open(path).read() if os.path.exists(path) else None


def suite(script_text):
    """The failures found running every recipe against the fake store."""
    import base64
    fails = []
    w = make_world(script_text)
    try:
        p8_b64 = base64.b64encode(PEM.encode()).decode()
        big = ("PLANTEDplay" + "0123456789abcdef" * 600).encode()      # far over one `security -i` line
        big_b64 = base64.b64encode(big).decode()
        planted = [RAND, PW, "PLANTEDpemBODY", p8_b64, "PLANTEDp12bytes", base64.b64encode(P12).decode(), big_b64[:60]]

        def clean(name, out):
            for v in planted:
                if v in out:
                    fails.append(f"{name}: printed a value")

        def kc(name):
            n = read(w, "kc", "archivewatch:" + name)
            if n is None or not n.isdigit():
                return None
            parts = [read(w, "kc", f"archivewatch:{name}.{i}") for i in range(int(n))]
            return None if None in parts else "".join(parts)

        for args in [[], ["exec", "ls"], ["gen", "SESSION_SECRET"], ["put-file", "X", "/etc/hosts"],
                     ["keychain-import-file", "NOT_A_NAME", "/etc/hosts"], ["keychain-import-file", "PLAY_SERVICE_ACCOUNT_JSON"],
                     ["keychain-import-file", "PLAY_SERVICE_ACCOUNT_JSON", "/no/such/file"],
                     ["keychain-import-file", "PLAY_SERVICE_ACCOUNT_JSON", "/etc/hosts", "/etc/hosts"],
                     ["renew-signing", "distribution"], ["keychain-import-asc", "not an id"], ["list", "x"],
                     ["drop-takedown-token", "x"], ["keychain-import-file", "PULSE_INGEST_ENV;id", "/etc/hosts"]]:
            code, out = run(w, *args)
            if code != 2:
                fails.append(f"refuse {args}: exit {code}")
            if read(w, "argv.log"):
                fails.append(f"refuse {args}: ran a command")
                os.remove(os.path.join(w, "store", "argv.log"))

        f = os.path.join(w, "play.json")
        open(f, "wb").write(big)
        code, out = run(w, "keychain-import-file", "PLAY_SERVICE_ACCOUNT_JSON", f)
        clean("keychain-import-file", out)
        if code != 0 or kc("PLAY_SERVICE_ACCOUNT_JSON") != big_b64:
            fails.append(f"keychain-import-file: exit {code} or the chunked Keychain value is wrong")
        if int(read(w, "kc", "archivewatch:PLAY_SERVICE_ACCOUNT_JSON") or 0) < 2:
            fails.append("keychain-import-file: a long value was not chunked")
        if not os.path.exists(f):
            fails.append("keychain-import-file: deleted the file without --delete")
        open(f, "wb").write(b"short")
        code, out = run(w, "keychain-import-file", "PLAY_SERVICE_ACCOUNT_JSON", f, "--delete")
        if code != 0 or os.path.exists(f) or kc("PLAY_SERVICE_ACCOUNT_JSON") != base64.b64encode(b"short").decode():
            fails.append(f"keychain-import-file --delete: exit {code}, the file or a shorter value is wrong")
        if read(w, "kc", "archivewatch:PLAY_SERVICE_ACCOUNT_JSON.1") is not None:
            fails.append("keychain-import-file: a stale chunk was left after a shorter value")

        p8 = os.path.join(w, "home", ".appstoreconnect", "private_keys", "AuthKey_ABCDE12345.p8")
        open(p8, "w").write(PEM)
        code, out = run(w, "keychain-import-asc", ISSUER)
        clean("keychain-import-asc", out)
        if code != 0 or kc("ASC_KEY_P8") != p8_b64 or kc("ASC_KEY_ID") != base64.b64encode(b"ABCDE12345").decode() \
                or kc("ASC_ISSUER_ID") != base64.b64encode(ISSUER.encode()).decode():
            fails.append(f"keychain-import-asc: exit {code} or a Keychain value is wrong")
        if not os.path.exists(p8):
            fails.append("keychain-import-asc: deleted the .p8 without --delete")
        code, out = run(w, "keychain-import-asc", p8, "--delete")
        clean("keychain-import-asc --delete", out)
        if code != 0 or os.path.exists(p8):
            fails.append(f"keychain-import-asc --delete: exit {code}, file {'kept' if os.path.exists(p8) else 'gone'}")

        code, out = run(w, "renew-signing")
        clean("renew-signing", out)
        gh = {n: read(w, "gh", n) for n in ["APPLE_DIST_P12", "APPLE_INSTALLER_P12", "APPLE_P12_PASSWORD", "APPLE_DIST_CERT_ID"]}
        p12_b64 = base64.b64encode(P12).decode()
        if code != 0 or gh["APPLE_P12_PASSWORD"] != PW or gh["APPLE_DIST_P12"] != p12_b64 \
                or gh["APPLE_INSTALLER_P12"] != p12_b64 or gh["APPLE_DIST_CERT_ID"] != "CERTDISTRIBUTION":
            fails.append(f"renew-signing: exit {code} or a GitHub secret is wrong")
        if (read(w, "signing.log") or "") != "distribution env-ok\nmac_installer env-ok\n":
            fails.append("renew-signing: the signing script did not get the Keychain values and password by environment")
        if os.listdir(os.path.join(w, "tmp")):
            fails.append("renew-signing: left its temp directory behind")

        os.makedirs(os.path.join(w, "store", "gh"), exist_ok=True)
        open(os.path.join(w, "store", "gh", "TAKEDOWN_TOKEN"), "w").write("x")
        os.makedirs(os.path.join(w, "store", "worker"), exist_ok=True)
        open(os.path.join(w, "store", "worker", "TAKEDOWN_TOKEN"), "w").write("x")
        open(os.path.join(w, "store", "worker", "INGEST_TOKEN"), "w").write("x")
        code, out = run(w, "drop-takedown-token")
        if code != 0 or read(w, "gh", "TAKEDOWN_TOKEN") is not None or read(w, "worker", "TAKEDOWN_TOKEN") is not None \
                or read(w, "worker", "INGEST_TOKEN") is None:
            fails.append(f"drop-takedown-token: exit {code}, it left the token or took another")

        # A Worker delete that fails must fail the recipe, never print "deleted" (2026-11-22: an old
        # cached wrangler failed and the recipe still reported success).
        open(os.path.join(w, "store", "gh", "TAKEDOWN_TOKEN"), "w").write("x")
        open(os.path.join(w, "store", "worker", "TAKEDOWN_TOKEN"), "w").write("x")
        os.environ["FAKE_WRANGLER_FAILS"] = "1"
        try:
            code, out = run(w, "drop-takedown-token")
        finally:
            del os.environ["FAKE_WRANGLER_FAILS"]
        if code == 0 or "FAILED" not in out:
            fails.append(f"drop-takedown-token: a failed Worker delete exited {code} without FAILED")

        code, out = run(w, "list")
        clean("list", out)
        if code != 0 or "INGEST_TOKEN" not in out or "ASC_KEY_P8" not in out or "APPLE_P12_PASSWORD" not in out \
                or "someone-else" in out or "PLAY_SERVICE_ACCOUNT_JSON.0" in out:
            fails.append(f"list: exit {code} or the names are wrong")

        argv = read(w, "argv.log") or ""
        for v in planted + [ISSUER]:
            if v in argv:
                fails.append("a value was on a command line")
                break
    finally:
        shutil.rmtree(w, ignore_errors=True)
    return fails


def main():
    src = open(SCRIPT).read()
    ran = failed = 0

    def check(name, ok):
        nonlocal ran, failed
        ran += 1
        if not ok:
            failed += 1
            print("FAIL", name)

    fails = suite(src)
    for f in fails:
        print("  ", f)
    check("tools/secrets.sh: fixed recipes only, no value printed or on a command line", fails == [])

    controls = {
        "echoes the password": ('pw="$(openssl rand -hex 24)"\n', 'pw="$(openssl rand -hex 24)"\n    echo "$pw"\n'),
        "passes the password as an argument": ("printf '%s' \"$pw\" | gh secret set APPLE_P12_PASSWORD --repo \"$REPO\"",
                                               'gh secret set APPLE_P12_PASSWORD --repo "$REPO" --body "$pw" </dev/null'),
        "puts a value on the security command line": ("printf 'add-generic-password -U -a %s -s %s -w %s\\n' \"$KC_ACCOUNT\" \"$KC_PREFIX$1\" \"$2\" | security -i >/dev/null",
                                                      'security add-generic-password -U -a "$KC_ACCOUNT" -s "$KC_PREFIX$1" -w "$2" >/dev/null'),
        "accepts any name": ('in_list "${args[0]}" "${FILE_NAMES[@]}" || die', 'true || die'),
        "keeps the downloaded .p8 on --delete": ('rm -f -- "$p8"; echo "the .p8 file is deleted"', 'echo "the .p8 file is deleted"'),
        "stores one long line": ('kc_item_put "$1.$n" "${v:0:$CHUNK}"', 'kc_item_put "$1.$n" "$v"; v=""'),
        "echoes the imported value": ('b64 "$f" | kc_put "${args[0]}"', 'b64 "$f" | tee /dev/stderr | kc_put "${args[0]}"'),
    }
    for name, (a, b) in controls.items():
        if src.count(a) != 1:
            check(f"control '{name}' still matches the script", False)
            continue
        check(f"CONTROL: a script that {name} is caught", suite(src.replace(a, b)) != [])

    print(f"{ran - failed}/{ran} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
