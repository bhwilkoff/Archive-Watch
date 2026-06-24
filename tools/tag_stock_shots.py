#!/usr/bin/env python3
"""tag_stock_shots.py — semantic SHOT tags for Creation Studio #6, WITHOUT Apple Vision.

Reuses the frame-extraction the stock pipeline already does: for each shot in clips.sqlite (built
by build_stock_index.py) it grabs the shot's mid-frame with ffmpeg and runs an OPEN-SOURCE CLIP
zero-shot classifier (open_clip, CPU) against a curated stock-footage vocabulary — so "find shots
of a sunset" works. CLIP runs on a plain Linux GitHub runner; no macOS, no in-app model, no
sqlite-vec. The tags are appended to the existing `tags` column, which `StockIndex` already
searches with LIKE — so the app needs NO change.

Resumable (a `tagged` flag), popularity-irrelevant (processes whatever's in the DB).

  pip install open-clip-torch
  python3 tools/tag_stock_shots.py --limit 4000
"""
from __future__ import annotations
import argparse
import io
import sqlite3
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Stock-footage vocabulary — scenes / settings / nature / weather / people / actions / objects.
VOCAB = [
    # landscape & nature
    "mountain", "forest", "ocean", "beach", "desert", "river", "waterfall", "lake", "valley",
    "cliff", "field", "meadow", "jungle", "glacier", "canyon", "island", "cave", "volcano",
    "farmland", "countryside", "garden", "park",
    # sky / weather / time of day
    "sunset", "sunrise", "night sky", "storm", "rain", "snow", "fog", "clouds", "lightning",
    "rainbow", "stars", "full moon", "blue sky", "dawn", "dusk", "wind",
    # urban / built
    "city skyline", "street", "building", "bridge", "highway", "traffic", "skyscraper", "alley",
    "factory", "train station", "airport", "harbor", "port", "tunnel", "construction site",
    "neon signs", "small town", "village",
    # interiors
    "office", "kitchen", "classroom", "laboratory", "hospital", "restaurant", "theater", "church",
    "courtroom", "library", "bedroom", "living room", "bar", "store", "warehouse",
    # people
    "crowd", "child", "soldier", "dancer", "worker", "family", "couple", "athlete", "musician",
    "public speaker", "audience", "police officer", "doctor", "nurse", "farmer", "scientist",
    "portrait of a person", "close-up of a face", "hands",
    # actions
    "running", "dancing", "fighting", "swimming", "driving", "flying", "walking", "working",
    "celebrating", "marching", "playing sports", "cooking", "reading", "writing", "singing",
    "protest", "parade", "wedding", "funeral", "race",
    # vehicles & transport
    "car", "vintage car", "train", "steam train", "airplane", "boat", "sailboat", "ship",
    "bicycle", "motorcycle", "tank", "helicopter", "rocket", "bus", "truck", "horse and carriage",
    # animals
    "dog", "cat", "bird", "horse", "cow", "fish", "lion", "elephant", "insect", "wildlife",
    # events / dramatic
    "explosion", "fire", "smoke", "ruins", "war", "battle", "machinery", "rocket launch",
    "fireworks", "flood", "earthquake damage",
    # film qualities
    "black and white footage", "aerial view", "underwater", "wide landscape shot",
    "extreme close-up", "silhouette", "animation", "cartoon", "map", "text on screen",
]


def extract_frame(url: str, t: float) -> bytes | None:
    """A single JPEG (downscaled) at time `t`, fast-seek over the stream."""
    cmd = ["ffmpeg", "-nostdin", "-ss", str(max(0, t)), "-i", url,
           "-frames:v", "1", "-vf", "scale=224:-1", "-f", "image2", "-vcodec", "mjpeg", "-"]
    try:
        r = subprocess.run(cmd, capture_output=True, timeout=60)
        return r.stdout or None
    except Exception:
        return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=4000, help="shots to tag this run")
    ap.add_argument("--db", default=str(REPO / "clips.sqlite"))
    ap.add_argument("--topk", type=int, default=5)
    ap.add_argument("--threshold", type=float, default=0.18, help="min CLIP probability to keep a tag")
    args = ap.parse_args()

    import torch
    import open_clip
    from PIL import Image

    db = sqlite3.connect(args.db)
    cols = {r[1] for r in db.execute("PRAGMA table_info(shots)")}
    if "tagged" not in cols:
        db.execute("ALTER TABLE shots ADD COLUMN tagged INTEGER DEFAULT 0")
        db.commit()

    model, _, preprocess = open_clip.create_model_and_transforms("ViT-B-32", pretrained="laion2b_s34b_b79k")
    model.eval()
    tokenizer = open_clip.get_tokenizer("ViT-B-32")
    with torch.no_grad():
        text = tokenizer([f"a photo of {v}" for v in VOCAB])
        text_feats = model.encode_text(text)
        text_feats /= text_feats.norm(dim=-1, keepdim=True)

    rows = db.execute(
        "SELECT id, sourceURL, startSeconds, endSeconds FROM shots WHERE COALESCE(tagged,0)=0 LIMIT ?",
        (args.limit,)).fetchall()
    done = 0
    for sid, url, s, e in rows:
        jpg = extract_frame(url, (s + e) / 2)
        if jpg:
            try:
                img = preprocess(Image.open(io.BytesIO(jpg)).convert("RGB")).unsqueeze(0)
                with torch.no_grad():
                    f = model.encode_image(img)
                    f /= f.norm(dim=-1, keepdim=True)
                    probs = (100.0 * f @ text_feats.T).softmax(dim=-1)[0]
                top = probs.topk(args.topk)
                tags = [VOCAB[i].replace(" ", "-") for i, p in zip(top.indices.tolist(), top.values.tolist())
                        if p >= args.threshold]
                if tags:
                    cur = db.execute("SELECT tags FROM shots WHERE id=?", (sid,)).fetchone()[0] or ""
                    merged = " ".join(dict.fromkeys((cur + " " + " ".join(tags)).split()))
                    db.execute("UPDATE shots SET tags=? WHERE id=?", (merged, sid))
            except Exception:
                pass
        db.execute("UPDATE shots SET tagged=1 WHERE id=?", (sid,))
        done += 1
        if done % 100 == 0:
            db.commit()
            print(f"[tag] {done}/{len(rows)}…", flush=True)
    db.commit()
    print(f"[tag] tagged {done} shots in {args.db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
