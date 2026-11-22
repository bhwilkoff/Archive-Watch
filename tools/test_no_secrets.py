#!/usr/bin/env python3
"""No secret in git (AGENTS.md hard rule: "Secrets never in git, and never in cleartext on disk";
docs/SECRETS-PLAN.md).

    python3 tools/test_no_secrets.py            every tracked file (CI, and by hand)
    python3 tools/test_no_secrets.py --staged   the staged blobs only (.githooks/pre-commit)

Fails on a tracked key or keystore file (.p8, .p12, .jks, .env, a service-account JSON...) and on
content shaped like a secret: a PEM private key with its body, a Google service-account key, AWS,
GitHub, Slack and Google API keys, a signed JWT, an archive.org S3 key pair, and a long high-entropy
value assigned to a *_KEY, *_SECRET, *_TOKEN or *_PASSWORD name. Placeholders (`${{ secrets.X }}`,
`$VAR`, `<...>`, `REPLACE_WITH`) are not values. A test fixture that must look like a secret is
listed in tools/no_secrets_allowlist.txt with its reason.

It proves itself first: every pattern is planted in a sample and must be caught, and a clean sample
must pass (a check is not a check until it has been seen to fail). The planted values are built at
run time, so this file does not match itself. Prints the file, line and rule, never the value.
"""
import fnmatch
import math
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALLOWLIST = os.path.join(ROOT, "tools", "no_secrets_allowlist.txt")

FORBIDDEN_FILES = ["*.p8", "*.p12", "*.pfx", "*.jks", "*.keystore", ".env", ".env.*", "*.env", ".dev.vars",
                   ".dev.vars.*", "*service-account*.json", "*service_account*.json", "takedown.env",
                   "*.password", "id_rsa", "id_ed25519", "*.mobileprovision"]
# A template of an env file that names variables without values is fine.
FORBIDDEN_EXCEPT = [".env.example", "*.env.example", ".dev.vars.example"]

PLACEHOLDER = re.compile(r"\$\{|\$\(|\$[A-Z_]|secrets\.|env\.|<[^>]*>|REPLACE|example|dummy|fake|placeholder|"
                         r"changeme|xxxx|test|\*\*\*|\.\.\.", re.I)
# Rules whose match is a value an example or fixture often spells out (AKIAIOSFODNN7EXAMPLE).
SKIP_PLACEHOLDERS = {"aws-access-key", "aws-secret-key", "google-api-key", "archive-org-s3"}

RULES = [
    ("pem-private-key", re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----(?:\\n|\s)*[A-Za-z0-9+/=]{64}")),
    ("service-account-json", re.compile(r'"private_key"\s*:\s*"-----BEGIN')),
    ("aws-access-key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("aws-secret-key", re.compile(r"aws_secret_access_key\s*[=:]\s*[\"']?[A-Za-z0-9/+=]{40}", re.I)),
    ("github-token", re.compile(r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36}\b|\bgithub_pat_[A-Za-z0-9_]{60,}")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{20,}")),
    ("archive-org-s3", re.compile(r"\bLOW [A-Za-z0-9]{16}:[A-Za-z0-9]{16}\b|"
                                  r"\b(?:IA_?S3_(?:ACCESS|SECRET)_KEY|s3_?(?:access|secret)_?key)\b[\"']?\s*[=:]\s*[\"']?[A-Za-z0-9]{16}\b",
                                  re.I)),
]
ASSIGN = re.compile(r"\b([A-Za-z0-9_]*(?:_KEY|_SECRET|_TOKEN|_PASSWORD|SECRET|PASSWORD|PASSWD|APIKEY))\b[\"']?\s*[:=]\s*"
                    r"[\"']([^\"'\s]{20,})[\"']", re.I)


def entropy(s):
    n = len(s)
    return -sum(c / n * math.log2(c / n) for c in (s.count(ch) for ch in set(s)))


def findings_in(text):
    """[(line, rule)] for one file's text. Never returns the matched value."""
    out = []
    for rule, rx in RULES:
        for m in rx.finditer(text):
            if rule in SKIP_PLACEHOLDERS and PLACEHOLDER.search(m.group(0)):
                continue
            out.append((text.count("\n", 0, m.start()) + 1, rule))
    for m in ASSIGN.finditer(text):
        v = m.group(2)
        # A colon-separated name (`app:project:v1`) is a storage key, not a credential.
        if PLACEHOLDER.search(v) or ":" in v or entropy(v) < 3.5:
            continue
        out.append((text.count("\n", 0, m.start()) + 1, "secret-assignment"))
    return sorted(set(out))


def forbidden_name(path):
    base = os.path.basename(path)
    if any(fnmatch.fnmatch(base, p) for p in FORBIDDEN_EXCEPT):
        return False
    return any(fnmatch.fnmatch(base, p) for p in FORBIDDEN_FILES)


def load_allowlist():
    """{path: {rule, ...}}; '*' allows every rule for that path. Lines: `path [rule] # reason`."""
    allowed = {}
    if os.path.exists(ALLOWLIST):
        for line in open(ALLOWLIST):
            line = line.split("#", 1)[0].strip()
            if line:
                parts = line.split()
                allowed.setdefault(parts[0], set()).add(parts[1] if len(parts) > 1 else "*")
    return allowed


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True).stdout


def scan(files, read, allowed):
    """[(path, line, rule)] over `files` (sorted), reading each with `read(path) -> bytes`."""
    problems = []
    for path in sorted(files):
        ok = allowed.get(path, set())
        if forbidden_name(path) and not ({"*", "forbidden-file"} & ok):
            problems.append((path, 0, "forbidden-file"))
        try:
            data = read(path)
        except (OSError, subprocess.CalledProcessError):
            continue
        if b"\0" in data[:8192]:
            continue
        for line, rule in findings_in(data.decode("utf-8", "replace")):
            if not ({"*", rule} & ok):
                problems.append((path, line, rule))
    return problems


def self_test():
    """Every rule catches its planted sample; a clean sample passes. Returns failures."""
    a = "A"
    body = "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7" + "x9Qz" * 8
    pem = "-----BEGIN " + "PRIVATE KEY-----\n" + body + "\n-----END " + "PRIVATE KEY-----\n"
    planted = {
        "pem-private-key": pem,
        "pem-private-key (RSA, JSON-escaped)": '"' + pem.replace("PRIVATE", "RSA PRIVATE").replace("\n", "\\n") + '"',
        "service-account-json": '{"type": "service_account", "private_' + 'key": "-----BEGIN' + ' PRIVATE KEY-----\\nMII"}',
        "aws-access-key": "key = " + a + "KIA" + "Q7RZ4MPLW2XK9TBN",
        "aws-secret-key": "aws_secret_access_key = " + "wJalrXUtnFEMIK7MDENGbPxRfiCYq3Lm9Nd2Kz8V",
        "github-token": "token: gh" + "p_" + "R7xK2mQ9vL4nW8pZ3cT6yB1dF5gH0jS2aE4u",
        "slack-token": "xo" + "xb-" + "1234567890-abcdefghij",
        "google-api-key": "AI" + "za" + "SyB3x9K2mQ7vL4nW8pZ3cT6yB1dF5gH0jSa",
        "jwt": "ey" + "JhbGciOiJSUzI1NiJ9.ey" + "JzdWIiOiJ4In0.c2lnbmF0dXJlLWxvb2tpbmctYnl0ZXMtaGVyZQ",
        "archive-org-s3 (header)": "authorization: LO" + "W Ab3dE5gH7jK9mN1p:Qr2sT4uV6wX8yZ0b",
        "archive-org-s3 (assignment)": "IA_S3_ACCESS" + "_KEY=Ab3dE5gH7jK9mN1p",
        "secret-assignment": 'SESSION_SEC' + 'RET = "q7Rz4MpLw2Xk9TbNv3Hc8YdF1sJ6uE0a"',
        "secret-assignment (JSON)": '{"UPLOAD_KEY_PASS' + 'WORD": "Zk3Lq9Vt2Wm7Np4Xr8Yc1Bd6"}',
    }
    fails = []
    for name, sample in planted.items():
        rule = name.split(" (")[0]
        got = {r for _, r in findings_in(sample)}
        if rule not in got:
            fails.append(f"CONTROL: a planted {name} was not caught")
    clean = "\n".join([
        "SESSION_SECRET: ${{ secrets.SESSION_SECRET }}",
        'APPLE_P12_PASSWORD="$P12PW"',
        'SESSION_SECRET: "test-only-session-secret-0123456789abcdef"',
        "pkcs8Pem.replace(/-----BEGIN [A-Z ]+-----/g, '')",
        "-----BEGIN PUBLIC KEY-----",
        'GOOGLE_AUDIENCES = "1083349339355-hmed22o33qemdc3dfhbqhkt0vho782ak.apps.googleusercontent.com"',
        "ASC_KEY_ID=<KEYID>",
    ])
    if findings_in(clean):
        fails.append(f"CONTROL: a clean sample was flagged: {findings_in(clean)}")
    # The same samples as files on disk, through the reader the scan uses.
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        names = []
        for i, sample in enumerate(planted.values()):
            names.append(f"planted{i}.txt")
            open(os.path.join(d, names[-1]), "w").write("ok = 1\n" + sample + "\n")
        names.append("AuthKey_PLANTED01.p8")
        open(os.path.join(d, names[-1]), "w").write("not even a key\n")
        found = {p for p, _, _ in scan(names, lambda p: open(os.path.join(d, p), "rb").read(), {})}
        if found != set(names):
            fails.append(f"CONTROL: planted files not caught: {sorted(set(names) - found)}")
        if scan(names, lambda p: open(os.path.join(d, p), "rb").read(), {n: {"*"} for n in names}):
            fails.append("CONTROL: the allowlist did not allow")
    for name, want in [("secrets/AuthKey_ABC.p8", True), ("x/upload.jks", True), ("worker/.dev.vars", True),
                       ("play-service-account.json", True), (".env.example", False), ("worker/src/jwt.js", False)]:
        if forbidden_name(name) != want:
            fails.append(f"CONTROL: forbidden file {name}: got {not want}")
    return fails


def main():
    fails = self_test()
    for f in fails:
        print(f)
    if fails:
        print("the scanner failed its own controls, so its scan proves nothing")
        sys.exit(1)
    allowed = load_allowlist()
    if "--staged" in sys.argv:
        files = [p for p in git("diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR").decode().split("\0") if p]
        problems = scan(files, lambda p: git("show", ":" + p), allowed)
    else:
        files = [p for p in git("ls-files", "-z").decode().split("\0") if p]
        problems = scan(files, lambda p: open(os.path.join(ROOT, p), "rb").read(), allowed)
    for path, line, rule in problems:
        print(f"SECRET? {path}:{line} {rule}")
    stale = [p for p in allowed if "--staged" not in sys.argv and p not in files]
    for p in stale:
        print(f"allowlist names a file that is not tracked: {p}")
    if problems or stale:
        print(f"{len(problems)} finding(s). Move the value to its one home (docs/SECRETS-PLAN.md),"
              " or, for a test fixture, add it to tools/no_secrets_allowlist.txt with the reason.")
        sys.exit(1)
    print(f"no secrets in {len(files)} {'staged' if '--staged' in sys.argv else 'tracked'} file(s); "
          f"{len(RULES) + 1} content rules and the forbidden-file list proved on planted samples")


if __name__ == "__main__":
    main()
