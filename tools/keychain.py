"""Read a credential kept in the login Keychain (docs/SECRETS-PLAN.md). No value is ever printed here.

Items are written by tools/secrets.sh as account `archivewatch`, service `archivewatch:<NAME>`, holding the
base64 of a file or a value. CI never reaches this: its credentials arrive as environment variables from
GitHub Actions secrets, and `security` does not exist on the Linux runners.

    python3 tools/keychain.py has NAME      exit 0 when the item exists (prints nothing)

Binary items (UPLOAD_KEYSTORE, TIZEN_*_P12, ROKU_GENKEY_RAW) are read with get_bytes(); a tool that needs a
file takes private_file(NAME), a 0600 file in a 0700 temporary directory that is deleted when it closes.
"""
import atexit
import base64
import json
import os
import shutil
import tempfile
import re
import subprocess
import sys

ACCOUNT = "archivewatch"
PREFIX = "archivewatch:"
LEGACY_PLAY = os.path.expanduser("~/.config/play/archivewatch-play.json")


def _item(name):
    try:
        out = subprocess.run(["security", "find-generic-password", "-a", ACCOUNT, "-s", PREFIX + name, "-w"],
                             capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else None


def get_bytes(name):
    """The item's decoded bytes (binary safe), or None when there is no Keychain or no such item.

    tools/secrets.sh stores a value as chunks (a `security -i` line is short): NAME holds the count,
    NAME.0 ... NAME.n-1 the base64 pieces.
    """
    count = _item(name)
    if not count or not count.isdigit():
        return None
    parts = [_item(f"{name}.{i}") for i in range(int(count))]
    if any(p is None for p in parts):
        return None
    try:
        return base64.b64decode("".join(parts), validate=True)
    except ValueError:
        return None


def get(name):
    """The item's decoded UTF-8 text, or None (also None for a binary item: use get_bytes)."""
    data = get_bytes(name)
    if data is None:
        return None
    try:
        return data.decode()
    except UnicodeDecodeError:
        return None


class PrivateFile:
    """A Keychain item written to a 0600 file in a 0700 temporary directory, removed on close(), on leaving
    the `with` block, and at interpreter exit. `.path` is the file."""

    def __init__(self, name, suffix=""):
        data = get_bytes(name)
        if data is None:
            raise LookupError(f"no Keychain item {PREFIX}{name}")
        self._dir = tempfile.mkdtemp(prefix="aw-kc-")
        os.chmod(self._dir, 0o700)
        self.path = os.path.join(self._dir, name + suffix)
        fd = os.open(self.path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        atexit.register(self.close)

    def close(self):
        shutil.rmtree(self._dir, ignore_errors=True)

    def __enter__(self):
        return self.path

    def __exit__(self, *exc):
        self.close()


def private_file(name, suffix=""):
    """`with keychain.private_file("UPLOAD_KEYSTORE", ".jks") as path:` ; or keep the object and close() it."""
    return PrivateFile(name, suffix)


def asc_value(name):
    """ASC_KEY_ID or ASC_ISSUER_ID: the environment (CI), then the Keychain."""
    return os.environ.get(name) or get(name)


def asc_key_pem(kid):
    """The App Store Connect .p8 as text: ASC_KEY_PATH, ASC_KEY_P8 (base64, CI), the Keychain, then the runner's file."""
    path = os.environ.get("ASC_KEY_PATH")
    if path:
        return open(path).read()
    b64 = os.environ.get("ASC_KEY_P8")
    if b64:
        return base64.b64decode(b64).decode()
    pem = get("ASC_KEY_P8")
    if pem:
        return pem
    return open(os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{kid}.p8")).read()


def play_key():
    """The Play service account as JSON text, or a path: the environment (CI), then the Keychain, then the old file."""
    env = os.environ.get("PLAY_SERVICE_ACCOUNT_JSON")
    if env:
        return env
    return get("PLAY_SERVICE_ACCOUNT_JSON") or LEGACY_PLAY


def play_credentials(scopes):
    """Google credentials for the Play service account, from play_key() (JSON text or a file path)."""
    from google.oauth2 import service_account
    key = play_key()
    if key.strip().startswith("{"):
        return service_account.Credentials.from_service_account_info(json.loads(key), scopes=scopes)
    return service_account.Credentials.from_service_account_file(key, scopes=scopes)


def env_file(name):
    """KEY=VALUE lines of a Keychain-held env file, as a dict (`export ` and quotes stripped)."""
    out = {}
    for line in (get(name) or "").splitlines():
        m = re.match(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("'\"")
    return out


def load_env(name):
    """Put a Keychain-held env file into os.environ without overriding what is already set."""
    for k, v in env_file(name).items():
        os.environ.setdefault(k, v)


def json_item(name):
    text = get(name)
    return json.loads(text) if text else None


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "has":
        sys.exit(0 if get(sys.argv[2]) is not None else 1)
    sys.exit(__doc__)
