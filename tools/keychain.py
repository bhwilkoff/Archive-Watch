"""Read a credential kept in the login Keychain (docs/SECRETS-PLAN.md). No value is ever printed here.

Items are written by tools/secrets.sh as account `archivewatch`, service `archivewatch:<NAME>`, holding the
base64 of a file or a value. CI never reaches this: its credentials arrive as environment variables from
GitHub Actions secrets, and `security` does not exist on the Linux runners.

    python3 tools/keychain.py has NAME      exit 0 when the item exists (prints nothing)
"""
import base64
import json
import os
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


def get(name):
    """The item's decoded text, or None when there is no Keychain or no such item.

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
        return base64.b64decode("".join(parts)).decode()
    except (ValueError, UnicodeDecodeError):
        return None


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
