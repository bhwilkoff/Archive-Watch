#!/usr/bin/env python3
"""tools/keychain.py reads chunked Keychain items and prefers the environment (docs/SECRETS-PLAN.md).
`security` is a stand-in on PATH holding planted items. Run: python3 tools/test_keychain.py"""
import base64
import os
import stat
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
JSON_TEXT = '{"type": "service_account", "k": "' + "PLANTED0123456789" * 300 + '"}'
ENV_TEXT = "# note\nexport SUBDL_API_KEY=PLANTEDsubdl\nPULSE_INGEST_TOKEN='PLANTEDingest'\n"


BIN = bytes(range(256)) * 30 + b"\xff\xfe"
P8_TEXT = "-----BEGIN PRIVATE KEY-----\nPLANTEDp8body0123\n-----END PRIVATE KEY-----\n"


def items(name, text):
    raw = text if isinstance(text, bytes) else text.encode()
    b = base64.b64encode(raw).decode()
    pieces = [b[i:i + 2000] for i in range(0, len(b), 2000)]
    out = {name: str(len(pieces))}
    out.update({f"{name}.{i}": p for i, p in enumerate(pieces)})
    return out


def main():
    store = {}
    store.update(items("PLAY_SERVICE_ACCOUNT_JSON", JSON_TEXT))
    store.update(items("SUBTITLE_KEYS_ENV", ENV_TEXT))
    store.update(items("UPLOAD_KEYSTORE", BIN))
    store.update(items("ASC_KEY_P8", P8_TEXT))
    store.update(items("ASC_KEY_ID", "ABCDE12345"))
    store["BROKEN"] = "2"
    store["BROKEN.0"] = "QUJD"
    d = tempfile.mkdtemp()
    fake = os.path.join(d, "security")
    open(fake, "w").write("#!" + sys.executable + "\nimport sys\nS = " + repr({"archivewatch:" + k: v for k, v in store.items()}) +
                          "\na = sys.argv[1:]\ns = a[a.index('-s') + 1]\nif s in S: print(S[s])\nelse: sys.exit(44)\n")
    os.chmod(fake, os.stat(fake).st_mode | stat.S_IEXEC)
    env = {**os.environ, "PATH": d + os.pathsep + os.environ["PATH"]}
    env.pop("PLAY_SERVICE_ACCOUNT_JSON", None)
    code = ("import sys; sys.path.insert(0, %r); import keychain as k, os\n"
            "assert k.get('PLAY_SERVICE_ACCOUNT_JSON') == %r, 'chunks'\n"
            "assert k.get('NOPE') is None, 'missing'\n"
            "assert k.get('BROKEN') is None, 'a missing chunk must not return half a value'\n"
            "assert k.play_key() == %r, 'keychain'\n"
            "os.environ['PLAY_SERVICE_ACCOUNT_JSON'] = 'from-ci'\n"
            "assert k.play_key() == 'from-ci', 'the environment wins'\n"
            "assert k.env_file('SUBTITLE_KEYS_ENV') == {'SUBDL_API_KEY': 'PLANTEDsubdl', 'PULSE_INGEST_TOKEN': 'PLANTEDingest'}, 'env file'\n"
            "os.environ['SUBDL_API_KEY'] = 'kept'; k.load_env('SUBTITLE_KEYS_ENV')\n"
            "assert os.environ['SUBDL_API_KEY'] == 'kept' and os.environ['PULSE_INGEST_TOKEN'] == 'PLANTEDingest', 'load_env'\n"
            % (HERE, JSON_TEXT, JSON_TEXT))
    r = subprocess.run([sys.executable, "-c", code], env=env, capture_output=True, text=True)
    bcode = ("import sys, os, stat; sys.path.insert(0, %r); import keychain as k\n"
             "assert k.get_bytes('UPLOAD_KEYSTORE') == %r, 'binary round trip'\n"
             "assert k.get('UPLOAD_KEYSTORE') is None, 'text get must refuse binary'\n"
             "assert k.get_bytes('NOPE') is None and k.get_bytes('BROKEN') is None\n"
             "with k.private_file('UPLOAD_KEYSTORE', '.jks') as p:\n"
             "    assert open(p, 'rb').read() == %r, 'file content'\n"
             "    assert stat.S_IMODE(os.stat(p).st_mode) == 0o600, 'file mode'\n"
             "    assert stat.S_IMODE(os.stat(os.path.dirname(p)).st_mode) == 0o700, 'dir mode'\n"
             "    assert p.endswith('.jks')\n"
             "assert not os.path.exists(os.path.dirname(p)), 'deleted on close'\n"
             "f = k.private_file('UPLOAD_KEYSTORE'); q = f.path; f.close(); assert not os.path.exists(q)\n"
             "try:\n    k.private_file('NOPE'); raise SystemExit('missing item must raise')\n"
             "except LookupError: pass\n"
             "for v in ('ASC_KEY_PATH', 'ASC_KEY_P8', 'ASC_KEY_ID'): os.environ.pop(v, None)\n"
             "assert k.asc_value('ASC_KEY_ID') == 'ABCDE12345' and k.asc_key_pem('ABCDE12345') == %r, 'keychain asc'\n"
             "os.environ['ASC_KEY_ID'] = 'FROMCI'; assert k.asc_value('ASC_KEY_ID') == 'FROMCI'\n"
             "import base64; os.environ['ASC_KEY_P8'] = base64.b64encode(b'ci-pem').decode()\n"
             "assert k.asc_key_pem('X') == 'ci-pem', 'CI env beats the Keychain'\n"
             "open(%r, 'w').write('path-pem'); os.environ['ASC_KEY_PATH'] = %r\n"
             "assert k.asc_key_pem('X') == 'path-pem', 'ASC_KEY_PATH beats everything'\n"
             % (HERE, BIN, BIN, P8_TEXT, os.path.join(d, "p"), os.path.join(d, "p")))
    rb = subprocess.run([sys.executable, "-c", bcode], env=env, capture_output=True, text=True)
    # negative control: a keychain.py whose close() leaves the file behind must fail the same checks
    bad = os.path.join(d, "bad")
    os.makedirs(bad)
    src = open(os.path.join(HERE, "keychain.py")).read()
    assert "shutil.rmtree(self._dir, ignore_errors=True)" in src
    open(os.path.join(bad, "keychain.py"), "w").write(src.replace("shutil.rmtree(self._dir, ignore_errors=True)", "pass"))
    rn = subprocess.run([sys.executable, "-c", bcode.replace(repr(HERE), repr(bad), 1)], env=env, capture_output=True, text=True)
    r2 = subprocess.run([sys.executable, os.path.join(HERE, "keychain.py"), "has", "PLAY_SERVICE_ACCOUNT_JSON"], env=env)
    r3 = subprocess.run([sys.executable, os.path.join(HERE, "keychain.py"), "has", "NOPE"], env=env)
    ok = r.returncode == 0 and r2.returncode == 0 and r3.returncode != 0
    ok_b = rb.returncode == 0 and rn.returncode != 0
    print(("PASS" if ok else "FAIL") + " keychain.py: chunks, missing, half a value, precedence, env files, has")
    print(("PASS" if ok_b else "FAIL") + " keychain.py: binary items, private_file (0600, deleted on close), ASC key order, negative control")
    ok = ok and ok_b
    if not ok:
        print(r.stderr[-400:], rb.stderr[-400:], "negative control exit", rn.returncode)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
