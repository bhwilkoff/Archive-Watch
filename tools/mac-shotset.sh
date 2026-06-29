#!/usr/bin/env bash
# Capture a FULL Mac App Store screenshot set for Archive Watch, driving the app to each screen via
# the AW_START_TAB / AW_START_ITEM / AW_CS_TEST launch hooks (RootView_macOS / CreationStudioTest).
# Each shot: relaunch the app on the target screen, size its window to 16:10, wait for art to load,
# capture the window, and frame it onto a 2880x1800 brand canvas (tools/mac-screenshots.sh logic).
#
# USAGE:  tools/mac-shotset.sh /path/to/ArchiveWatchMac.app
# Needs macOS Screen Recording permission for the terminal. Output: ~/Desktop/ArchiveWatch-Mac-Screenshots/
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: mac-shotset.sh /path/to/ArchiveWatchMac.app}"
BIN="$APP/Contents/MacOS/ArchiveWatchMac"
[ -x "$BIN" ] || { echo "no binary at $BIN"; exit 1; }
OUTDIR="$HOME/Desktop/ArchiveWatch-Mac-Screenshots"
mkdir -p "$OUTDIR"
SIZE="${SIZE:-2880x1800}"; W="${SIZE%x*}"; H="${SIZE#*x}"
BG="${BG:-#0A0A0A}"; MARGIN="${MARGIN:-0.04}"
WINW="${WINW:-1680}"; WINH="${WINH:-1050}"   # 16:10 window so the framed result is crisp + fills the canvas
ART_WAIT="${ART_WAIT:-24}"                    # seconds to let posters/backdrops load over the network
# Python with Pillow for the canvas framing (system python3 may lack PIL; the play venv has it).
PYBIN="tools/.play-venv/bin/python"; [ -x "$PYBIN" ] || PYBIN="python3"

quit() { pkill -f "ArchiveWatchMac" 2>/dev/null || true; sleep 1.5; }

size_window() {
  osascript >/dev/null 2>&1 <<OSA || true
tell application "System Events"
  set procs to (every process whose name contains "Archive" and visible is true)
  if procs is {} then return
  set p to item 1 of procs
  set frontmost of p to true
  try
    set position of front window of p to {100, 60}
    set size of front window of p to {$WINW, $WINH}
  end try
end tell
OSA
}

frame_capture() {  # $1 = output name
  local name="$1" raw out bounds bytes
  raw="$(mktemp -t awshot).png"; out="$OUTDIR/$name.png"
  osascript -e 'tell application "System Events" to set frontmost of (first process whose name contains "Archive") to true' >/dev/null 2>&1 || true
  sleep 0.6
  # SwiftUI exposes no AXWindowNumber, so capture by REGION from the window's AX bounds (each number
  # coerced `as text` — a bare list would serialize wrong). This is the recipe that actually works here.
  bounds="$(osascript 2>/dev/null <<'OSA' || true
tell application "System Events"
  set p to item 1 of (every process whose name contains "Archive" and visible is true)
  set w to front window of p
  set {x, y} to position of w
  set {ww, hh} to size of w
  return (x as text) & "," & (y as text) & "," & (ww as text) & "," & (hh as text)
end tell
OSA
)"
  if [[ "$bounds" =~ ^[0-9.,-]+$ ]]; then screencapture -o -x -R"$bounds" -t png "$raw"; else screencapture -o -x -t png "$raw"; fi
  bytes=$(stat -f%z "$raw" 2>/dev/null || echo 0)
  [ "$bytes" -lt 5000 ] && echo "WARNING: $name capture tiny ($bytes B) — grant Screen Recording permission." >&2
  "$PYBIN" - "$raw" "$out" "$W" "$H" "$BG" "$MARGIN" <<'PY'
import sys
from PIL import Image
raw,out,W,H,bg,margin=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4]),sys.argv[5],float(sys.argv[6])
def hx(s):s=s.lstrip('#');return tuple(int(s[i:i+2],16) for i in (0,2,4))
c=Image.new("RGB",(W,H),hx(bg)); s=Image.open(raw).convert("RGB")
m=int(min(W,H)*margin); mw,mh=W-2*m,H-2*m; sw,sh=s.size; sc=min(mw/sw,mh/sh)
nw,nh=max(1,int(sw*sc)),max(1,int(sh*sc)); s=s.resize((nw,nh),Image.LANCZOS)
c.paste(s,((W-nw)//2,(H-nh)//2)); c.save(out,"PNG"); print(f"  wrote {out} ({W}x{H})")
PY
  rm -f "$raw"
}

launch() {  # env assignments... ; launches BIN detached with those env vars
  quit
  env "$@" "$BIN" >/tmp/aw-shot-app.log 2>&1 &
  sleep 6                 # app start + window
  size_window
}

shot() {  # $1 name ; rest = env assignments
  local name="$1"; shift
  echo "→ $name  [$*]"
  launch "$@"
  size_window
  sleep "$ART_WAIT"       # let catalog art load
  size_window
  frame_capture "$name"
}

echo "== warm-up launch (download + cache the full catalog DB + art) =="
quit
"$BIN" >/tmp/aw-shot-app.log 2>&1 &
sleep "${WARM:-90}"
quit

# Pick two visually strong Detail items from the cached catalog DB (popular, designed art + backdrop).
DB="$(ls -t "$HOME/Library/Containers/app.archivewatch.tvos/Data/Library/Caches/"*.sqlite 2>/dev/null | head -1)"
ITEM1="${ITEM1:-}"; ITEM2="${ITEM2:-}"
if [ -z "$ITEM1" ] && [ -n "$DB" ] && command -v sqlite3 >/dev/null; then
  PICKS="$(sqlite3 "$DB" "SELECT archiveID FROM items WHERE posterURL IS NOT NULL AND posterURL!='' AND hasRealArtwork=1 AND artworkSource!='generated' AND contentType='feature-film' AND imdbVotes>=50000 ORDER BY popularityScore DESC LIMIT 2;" 2>/dev/null || true)"
  ITEM1="$(printf '%s\n' "$PICKS" | sed -n '1p')"
  ITEM2="$(printf '%s\n' "$PICKS" | sed -n '2p')"
fi
echo "Detail items: ITEM1=${ITEM1:-<none>}  ITEM2=${ITEM2:-<none>}  (DB=$DB)"

shot 01-home        AW_START_TAB=home
shot 02-movies      AW_START_TAB=movies
shot 03-tvshows     AW_START_TAB=tv
shot 04-collections AW_START_TAB=collections
shot 05-channels    AW_START_TAB=channels
[ -n "$ITEM1" ] && shot 06-detail AW_START_ITEM="$ITEM1"
[ -n "$ITEM2" ] && shot 07-detail-2 AW_START_ITEM="$ITEM2"
shot 08-studio-editor AW_CS_TEST=editor
shot 09-studio-clip   AW_CS_TEST=markclip
shot 10-surprise      AW_START_TAB=surprise
quit

echo "== done. Set in $OUTDIR =="
ls -la "$OUTDIR"
