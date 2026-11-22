#!/usr/bin/env python3
"""tools/with_signing.sh and the secrets.sh keychain-import-gradle recipe (docs/SECRETS-PLAN.md). `security` is a
stand-in on PATH with a planted store; HOME is a temp directory holding a planted gradle.properties. No real value
is read. Planted values must reach the command's ORG_GRADLE_PROJECT_* environment and a 0600 keystore that is gone
afterwards, and appear in no output. Negative control: a wrapper that leaves the keystore behind is caught.
Run: python3 tools/test_with_signing.py"""
import base64, os, shlex, stat, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
JKS = bytes(range(256)) * 5 + b"\xff"
VALS = {"UPLOAD_STORE_PASSWORD": "PLANTEDstorepw123", "UPLOAD_KEY_PASSWORD": "PLANTEDkeypw456", "UPLOAD_KEY_ALIAS": "plantedalias"}
PROPS = {"UPLOAD_KEYSTORE_PASSWORD": VALS["UPLOAD_STORE_PASSWORD"], "UPLOAD_KEY_PASSWORD": VALS["UPLOAD_KEY_PASSWORD"],
         "UPLOAD_KEY_ALIAS": VALS["UPLOAD_KEY_ALIAS"]}

FAKE_SECURITY = r'''
import os, shlex, sys
d = os.path.join(os.environ["FAKE_STORE"], "kc"); os.makedirs(d, exist_ok=True)
a = sys.argv[1:]
def opt(x, k): return x[x.index(k) + 1]
if a and a[0] == "find-generic-password":
    p = os.path.join(d, opt(a, "-s"))
    if not os.path.exists(p): sys.exit(44)
    print(open(p).read())
elif a == ["-i"]:
    for line in sys.stdin:
        w = shlex.split(line)
        if w and w[0] == "add-generic-password":
            open(os.path.join(d, opt(w, "-s")), "w").write(opt(w, "-w"))
else:
    sys.exit("fake security: " + " ".join(a))
'''


def chunks(name, raw, size=40):
    b = base64.b64encode(raw).decode()
    ps = [b[i:i + size] for i in range(0, len(b), size)]
    out = {f"archivewatch:{name}": str(len(ps))}
    out.update({f"archivewatch:{name}.{i}": p for i, p in enumerate(ps)})
    return out


def world(planted=True, props=True):
    w = tempfile.mkdtemp(prefix="withsign-")
    for sub in ("bin", "store/kc", "home/.gradle", "tmp"):
        os.makedirs(os.path.join(w, sub))
    p = os.path.join(w, "bin", "security")
    open(p, "w").write("#!" + sys.executable + "\n" + FAKE_SECURITY)
    os.chmod(p, 0o755)
    if planted:
        items = chunks("UPLOAD_KEYSTORE", JKS)
        for n, v in VALS.items():
            items.update(chunks(n, v.encode()))
        for k, v in items.items():
            open(os.path.join(w, "store", "kc", k), "w").write(v)
    if props:
        open(os.path.join(w, "home/.gradle/gradle.properties"), "w").write(
            "org.gradle.jvmargs=-Xmx2g\n" + "".join(f"{k}={v}\n" for k, v in PROPS.items()))
    return w


def env(w, **extra):
    e = {k: v for k, v in os.environ.items() if not k.startswith(("ORG_GRADLE", "CI"))}
    e.update(PATH=os.path.join(w, "bin") + os.pathsep + e["PATH"], FAKE_STORE=os.path.join(w, "store"),
             HOME=os.path.join(w, "home"), TMPDIR=os.path.join(w, "tmp"))
    e.update(extra)
    return e


def main(wrapper=os.path.join(HERE, "with_signing.sh")):
    fails = []
    # 1. the wrapper: keystore bytes, mode, env, removal, no output of values
    w = world(props=False)
    probe = os.path.join(w, "probe")
    cmd = ('p="$ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PATH"; echo "$p" > %s; stat -f %%Lp "$p" >> %s; cmp -s "$p" %s && echo same >> %s; '
           'echo "$ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PASSWORD $ORG_GRADLE_PROJECT_UPLOAD_KEY_PASSWORD $ORG_GRADLE_PROJECT_UPLOAD_KEY_ALIAS" >> %s'
           % tuple(shlex.quote(x) for x in (probe, probe, os.path.join(w, "jks.bin"), probe, probe)))
    open(os.path.join(w, "jks.bin"), "wb").write(JKS)
    r = subprocess.run(["bash", wrapper, "sh", "-c", cmd], env=env(w), capture_output=True, text=True)
    L = open(probe).read().split("\n") if os.path.exists(probe) else []
    ok = (r.returncode == 0 and len(L) >= 4 and L[1] == "600" and L[2] == "same"
          and L[3] == f"{VALS['UPLOAD_STORE_PASSWORD']} {VALS['UPLOAD_KEY_PASSWORD']} {VALS['UPLOAD_KEY_ALIAS']}"
          and not os.path.exists(L[0]))
    if not ok:
        fails.append(f"wrapper: exit {r.returncode} {r.stderr[-200:]} {L[:3]}")
    if any(v in r.stdout + r.stderr for v in VALS.values()):
        fails.append("wrapper printed a value")
    # 2. already set (a CI-like environment): nothing is read from the Keychain
    r = subprocess.run(["bash", wrapper, "sh", "-c", 'echo "$ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PATH"'],
                       env=env(world(planted=False), ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PATH="/ci/ks.jks"), capture_output=True, text=True)
    if r.returncode or r.stdout.strip() != "/ci/ks.jks":
        fails.append("pre-set path was not left alone")
    # 3. empty Keychain: refuses and does not run the command
    w0 = world(planted=False)
    r = subprocess.run(["bash", wrapper, "touch", os.path.join(w0, "ran")], env=env(w0), capture_output=True, text=True)
    if r.returncode == 0 or os.path.exists(os.path.join(w0, "ran")):
        fails.append("ran the command with no keystore in the Keychain")
    # 4. the import recipe: reads gradle.properties itself, stores the three items, prints no value, leaves the file
    wi = world(planted=False)
    store = os.path.join(wi, "root"); os.makedirs(os.path.join(store, "tools")); os.makedirs(os.path.join(store, "worker"))
    sec = os.path.join(store, "tools", "secrets.sh")
    open(sec, "w").write(open(os.path.join(HERE, "secrets.sh")).read()); os.chmod(sec, 0o755)
    before = open(os.path.join(wi, "home/.gradle/gradle.properties")).read()
    r = subprocess.run(["bash", sec, "keychain-import-gradle"], env=env(wi), capture_output=True, text=True)
    out = r.stdout + r.stderr
    got = {}
    for n in VALS:
        try:
            cnt = int(open(os.path.join(wi, "store/kc", f"archivewatch:{n}")).read())
            got[n] = base64.b64decode("".join(open(os.path.join(wi, "store/kc", f"archivewatch:{n}.{i}")).read() for i in range(cnt))).decode()
        except OSError:
            got[n] = None
    if r.returncode or got != VALS:
        fails.append(f"import recipe: exit {r.returncode} {out[-200:]}")
    if any(v in out for v in VALS.values()):
        fails.append("import recipe printed a value")
    if open(os.path.join(wi, "home/.gradle/gradle.properties")).read() != before:
        fails.append("import recipe touched gradle.properties")
    # 5. import with a missing property dies
    wm = world(planted=False, props=False)
    os.makedirs(os.path.join(wm, "root/tools")); os.makedirs(os.path.join(wm, "root/worker"))
    s2 = os.path.join(wm, "root/tools/secrets.sh"); open(s2, "w").write(open(sec).read()); os.chmod(s2, 0o755)
    open(os.path.join(wm, "home/.gradle/gradle.properties"), "w").write("UPLOAD_KEY_ALIAS=x\n")
    r = subprocess.run(["bash", s2, "keychain-import-gradle"], env=env(wm), capture_output=True, text=True)
    if r.returncode == 0:
        fails.append("import succeeded with passwords missing")
    return fails


if __name__ == "__main__":
    fails = main()
    # negative control: a wrapper that leaves the temporary keystore behind must be caught by the removal check
    src = open(os.path.join(HERE, "with_signing.sh")).read()
    assert "trap 'rm -rf \"$dir\"' EXIT" in src
    bad = os.path.join(tempfile.mkdtemp(), "bad.sh")
    open(bad, "w").write(src.replace("trap 'rm -rf \"$dir\"' EXIT", "true"))
    if not [f for f in main(bad) if f.startswith("wrapper")]:
        fails.append("negative control: a wrapper that keeps the keystore passed")
    print(("FAIL " + "; ".join(fails)) if fails else "PASS with_signing.sh + keychain-import-gradle: keystore 0600 and removed, env set, import from the file, no value printed, negative control")
    sys.exit(1 if fails else 0)
