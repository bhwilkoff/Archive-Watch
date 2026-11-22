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


def items(name, text):
    b = base64.b64encode(text.encode()).decode()
    pieces = [b[i:i + 2000] for i in range(0, len(b), 2000)]
    out = {name: str(len(pieces))}
    out.update({f"{name}.{i}": p for i, p in enumerate(pieces)})
    return out


def main():
    store = {}
    store.update(items("PLAY_SERVICE_ACCOUNT_JSON", JSON_TEXT))
    store.update(items("SUBTITLE_KEYS_ENV", ENV_TEXT))
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
    r2 = subprocess.run([sys.executable, os.path.join(HERE, "keychain.py"), "has", "PLAY_SERVICE_ACCOUNT_JSON"], env=env)
    r3 = subprocess.run([sys.executable, os.path.join(HERE, "keychain.py"), "has", "NOPE"], env=env)
    ok = r.returncode == 0 and r2.returncode == 0 and r3.returncode != 0
    print(("PASS" if ok else "FAIL") + " keychain.py: chunks, missing, half a value, precedence, env files, has")
    if not ok:
        print(r.stderr[-400:])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
