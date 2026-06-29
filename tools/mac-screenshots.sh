#!/usr/bin/env bash
# Mac App Store screenshot helper for Archive Watch.
#
# App Store requires Mac screenshots at EXACTLY one 16:10 size: 1280x800, 1440x900,
# 2560x1600, or 2880x1800 (PNG/JPEG, 1-10 shots). A raw window grab is never exactly that
# size (title bar, rounded corners, shadow), so this captures the frontmost Archive Watch
# window and FRAMES it — scaled to fit, centered on a solid brand canvas — at the exact size.
#
# USAGE (run once per screen, with the app already showing that screen):
#   1. Launch the RELEASE build of Archive Watch and navigate to the screen you want
#      (Home, a Detail page, Channels, the Creation Studio editor, the Supercut sheet, …).
#      Do NOT set any AW_CS_* / AW_START_* env vars — the store build must look like the real app.
#   2. Run:  tools/mac-screenshots.sh 01-home
#      It brings Archive Watch to the front, grabs its frontmost window, and writes
#      ~/Desktop/ArchiveWatch-Mac-Screenshots/01-home.png at the target size.
#   3. Repeat for each screen (02-detail, 03-channels, 04-studio, 05-supercut, 06-export).
#
# REQUIREMENT: the terminal/app you run this from needs macOS **Screen Recording** permission
# (System Settings ▸ Privacy & Security ▸ Screen Recording) or the grab is blank. The script
# checks and tells you if it looks empty.
#
# Tunables via env: SIZE=2880x1800 (default) | 2560x1600 | 1440x900 | 1280x800
#                   BG=#0A0A0A (canvas) ; MARGIN=0.06 (fraction of the long edge)
set -euo pipefail

NAME="${1:?usage: mac-screenshots.sh <output-name-without-extension>}"
SIZE="${SIZE:-2880x1800}"
BG="${BG:-#0A0A0A}"
MARGIN="${MARGIN:-0.06}"
APP="Archive Watch"
OUTDIR="$HOME/Desktop/ArchiveWatch-Mac-Screenshots"
mkdir -p "$OUTDIR"
RAW="$(mktemp -t awshot).png"
OUT="$OUTDIR/$NAME.png"

W="${SIZE%x*}"; H="${SIZE#*x}"

# Bring the app forward so its window is frontmost, then capture that window only (-o = no shadow).
osascript -e "tell application \"$APP\" to activate" 2>/dev/null || \
  osascript -e 'tell application "System Events" to set frontmost of (first process whose name contains "Archive") to true' 2>/dev/null || true
sleep 0.8

# Frontmost on-screen window id of the app (CGWindowList via Swift one-liner is overkill; use
# AppleScript-free `screencapture -W` interactive fallback if we can't resolve an id).
WIN_ID="$(osascript <<'OSA' 2>/dev/null || true
tell application "System Events"
  set procs to (every process whose name contains "Archive" and visible is true)
  if procs is {} then return ""
  set p to item 1 of procs
  try
    set w to first window of p
    return (value of attribute "AXWindowNumber" of w) as text
  on error
    return ""
  end try
end tell
OSA
)"

if [[ -n "$WIN_ID" && "$WIN_ID" =~ ^[0-9]+$ ]]; then
  screencapture -o -x -l"$WIN_ID" -t png "$RAW"
else
  echo "Could not resolve the window id automatically — click the Archive Watch window when the cursor changes."
  screencapture -o -W -t png "$RAW"
fi

# Sanity: a blank/black grab usually means Screen Recording permission is missing.
BYTES=$(stat -f%z "$RAW" 2>/dev/null || echo 0)
if [[ "$BYTES" -lt 5000 ]]; then
  echo "WARNING: the capture is tiny ($BYTES bytes) — grant Screen Recording permission to your terminal/Xcode and retry." >&2
fi

# Frame onto an exact-size brand canvas (Pillow — already used by the cover pipeline).
python3 - "$RAW" "$OUT" "$W" "$H" "$BG" "$MARGIN" <<'PY'
import sys
from PIL import Image
raw, out, W, H, bg, margin = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], float(sys.argv[6])
def hex2rgb(s):
    s = s.lstrip('#')
    return tuple(int(s[i:i+2], 16) for i in (0, 2, 4))
canvas = Image.new("RGB", (W, H), hex2rgb(bg))
shot = Image.open(raw).convert("RGB")
m = int(min(W, H) * margin)
maxw, maxh = W - 2*m, H - 2*m
sw, sh = shot.size
scale = min(maxw / sw, maxh / sh)
nw, nh = max(1, int(sw*scale)), max(1, int(sh*scale))
shot = shot.resize((nw, nh), Image.LANCZOS)
canvas.paste(shot, ((W - nw)//2, (H - nh)//2))
canvas.save(out, "PNG")
print(f"wrote {out} ({W}x{H})")
PY
rm -f "$RAW"
