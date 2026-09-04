#!/usr/bin/env python3
"""Package the Roku channel into a signed .pkg for submission.

Roku has NO submission API — every step after this one happens by hand in the
Developer Dashboard (see docs/ROKU-SUBMISSION.md). What IS scriptable is the
part that produces the artifact, and that is what this does:

    showkey   -> is the device keyed at all?
    deploy    -> sideload the current source
    package   -> ask the device to encrypt and sign it
    download  -> pull the .pkg

The signing key lives ON THE DEVICE, not in this repo, and it is minted once by
`genkey` on the dev console (port 8080). That is deliberately NOT automated
here: genkey REPLACES any existing key, and every package ever signed with the
old one becomes un-updatable — the only recovery is Rekey, which needs a copy
of an old package and its password. A tool that can silently orphan a shipped
channel is not a tool worth having.

  python3 tools/roku_package.py --check     # key status only
  python3 tools/roku_package.py --password 'xxx' --version 1.0.0
"""
import argparse, os, re, socket, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import roku  # noqa: E402


def devconsole(cmd, wait=3.0):
    """Run one command on the developer console (port 8080) and return output."""
    s = socket.create_connection((roku.HOST, 8080), timeout=8)
    s.settimeout(4)

    def drain():
        b = b""
        try:
            while True:
                c = s.recv(4096)
                if not c:
                    break
                b += c
        except socket.timeout:
            pass
        return b.decode(errors="replace")

    drain()
    s.sendall((cmd + "\n").encode())
    time.sleep(wait)
    out = drain()
    s.close()
    return out


def key_status():
    out = devconsole("showkey")
    m = re.search(r"Dev ID:\s*(\S+)", out)
    return m.group(1) if m else "?"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="report the key status and stop")
    ap.add_argument("--password", help="the genkey password for this device")
    ap.add_argument("--version", default=None, help="package version, e.g. 1.0.0")
    ap.add_argument("--no-deploy", action="store_true", help="package what is already sideloaded")
    args = ap.parse_args()

    dev = key_status()
    print(f"device {roku.HOST}  dev id: {dev}")
    if dev == "<unkeyed>":
        print("\nThis device has NO signing key, so nothing can be packaged yet.")
        print("Mint one ONCE, on the dev console, and store the password somewhere")
        print("outside this repo — losing it means you can never update the")
        print("published channel except by Rekey from an old package:\n")
        print(f"    telnet {roku.HOST} 8080")
        print("    genkey\n")
        print("Then re-run with --password.")
        return 1
    if args.check:
        return 0
    if not args.password:
        print("--password is required to package (the genkey password for this device)")
        return 1

    version = args.version
    if not version:
        # The version the channel already declares, so the package and the
        # manifest can never disagree.
        man = open(os.path.join(roku.REPO, "roku", "manifest")).read()
        maj = re.search(r"major_version=(\d+)", man)
        mnr = re.search(r"minor_version=(\d+)", man)
        bld = re.search(r"build_version=(\d+)", man)
        version = f"{maj.group(1)}.{mnr.group(1)}.{bld.group(1)}" if maj and mnr and bld else "1.0.0"
    print(f"packaging version {version}")

    if not args.no_deploy:
        blob = roku.zip_channel("roku")
        tmp = "/tmp/aw-roku.zip"
        open(tmp, "wb").write(blob)
        print(f"  sideloading {len(blob)/1024:.0f} KB")
        out = roku.post_install("Replace", tmp)
        msgs = roku.installer_messages(out)
        if any(k == "error" for k, _ in msgs):
            for _, t in msgs:
                print("   ", t)
            return 1

    html = roku.dev_curl("-F", f"mysubmit=Package", "-F", f"app_name=ArchiveWatch/{version}",
                         "-F", f"passwd={args.password}", "-F", "pkg_time=" + str(int(time.time())),
                         f"{roku.DEV}/plugin_package", timeout=300)
    msgs = roku.installer_messages(html)
    for kind, t in msgs:
        print("   ", t)
    m = re.search(r'href="pkgs//?([^"]+\.pkg)"', html)
    if not m:
        print("no .pkg link in the response — the password is the usual cause")
        return 1
    name = m.group(1)
    out_dir = os.path.join(roku.REPO, "build", "roku")
    os.makedirs(out_dir, exist_ok=True)
    dest = os.path.join(out_dir, name)
    roku.dev_curl("-o", dest, f"{roku.DEV}/pkgs/{name}", timeout=300, binary=True)
    size = os.path.getsize(dest)
    print(f"\nwrote {dest}  ({size/1024:.0f} KB)")
    # Roku refuses a channel over 4 MB at certification.
    if size > 4 * 1024 * 1024:
        print("WARNING: over the 4 MB certification limit")
        return 1
    print("Upload this .pkg in the Developer Dashboard — there is no submission API.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
