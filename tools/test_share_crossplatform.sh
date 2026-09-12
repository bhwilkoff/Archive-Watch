#!/usr/bin/env bash
# A link made on an Apple TV is opened in somebody else's BROWSER. That hop is
# the whole contract, and nothing else in the test suite covers it: the Swift
# encoder and the JS decoder are different languages, different compressors and
# different base64 implementations, and they agree or the feature is broken for
# every person who receives a link.
#
# So: encode with the SHIPPED Swift, decode with the SHIPPED JavaScript.
#
#   bash tools/test_share_crossplatform.sh
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/main.swift" <<'SWIFT'
@main
struct Harness {
    static func main() {
        let ids = ["the-grapes-of-wrath-1940", "hog-wild_1930", "TheGeneral720p1926",
                   "los-tallos-amargos-1956", "1912GeorgesMeliesALaConqueteDuPole"]
        if let b = PlaylistShare.blob(name: "Fordy Things", archiveIDs: ids) { print(b) }
    }
}
SWIFT

DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer} \
  xcrun swiftc -O -parse-as-library \
    ArchiveWatch/ArchiveWatch/Services/PlaylistShare.swift "$TMP/main.swift" \
    -o "$TMP/awshare"

BLOB="$("$TMP/awshare")"
[ -n "$BLOB" ] || { echo "FAIL  the Swift encoder produced nothing"; exit 1; }
echo "  Swift produced ${#BLOB} chars"

node -e '
const fs = require("fs");
const src = fs.readFileSync("watch.js", "utf8");
const body = src.slice(src.indexOf("const ShareList = {"));
const ShareList = eval("(" + body.slice(0, body.indexOf("\n  };") + 4)
  .replace(/^const ShareList = /, "") + ")");
const want = ["the-grapes-of-wrath-1940","hog-wild_1930","TheGeneral720p1926",
              "los-tallos-amargos-1956","1912GeorgesMeliesALaConqueteDuPole"];
ShareList.decode(process.argv[1]).then(pl => {
  const ok = pl.name === "Fordy Things" && JSON.stringify(pl.ids) === JSON.stringify(want);
  console.log(ok ? "  PASS  a Swift-made link decodes in the browser, exactly"
                 : "  FAIL  decoded, but the contents differ: " + JSON.stringify(pl));
  process.exit(ok ? 0 : 1);
}).catch(e => { console.log("  FAIL  the browser refused it: " + e.message); process.exit(1); });
' "$BLOB"
