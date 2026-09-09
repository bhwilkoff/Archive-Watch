#!/usr/bin/env python3
"""
ffmpeg_limits.py — one place that decides how much of the machine ffmpeg gets.

ffmpeg takes every core it can find. That is right on a CI runner, whose only
job is this, and wrong on the owner's laptop, which is also being used to read
email while a film is transcoded. On 2026-09-09 the owner asked why the machine
had slowed to a crawl; the answer that day was a spinning Python loop and a
Gradle release build, but a full-core ffmpeg is the same shape of problem and
was one bad afternoon away from being the next one.

So: `FFMPEG` is the command prefix every tool starts from, and it leaves the
machine usable by default and gets out of the way in CI.

  * On CI (`CI=true`) it is bare `ffmpeg` — take the whole runner.
  * Anywhere else it is `nice -n 10 ffmpeg -threads <half the cores>`, so a
    transcode yields to whatever the person is actually doing.

`AW_FFMPEG_THREADS` and `AW_FFMPEG_NICE` override both, for the times when a
local run genuinely should have the machine.
"""
from __future__ import annotations

import os
import shutil

__all__ = ["FFMPEG", "FFPROBE", "ffmpeg_cmd", "threads", "on_ci"]


def on_ci() -> bool:
    return os.environ.get("CI", "").lower() in ("1", "true", "yes")


def threads() -> int:
    """Half the cores, at least one, unless told otherwise. Half rather than
    `cores - 1`: the point is to leave the machine RESPONSIVE, and a single
    spare core does not do that once memory bandwidth is saturated too."""
    override = os.environ.get("AW_FFMPEG_THREADS", "").strip()
    if override.isdigit():
        return max(1, int(override))
    if on_ci():
        return 0                                     # 0 = ffmpeg's own default
    return max(1, (os.cpu_count() or 4) // 2)


def _nice() -> int:
    override = os.environ.get("AW_FFMPEG_NICE", "").strip()
    if override.lstrip("-").isdigit():
        return int(override)
    return 0 if on_ci() else 10


def ffmpeg_cmd(binary: str = "ffmpeg") -> list[str]:
    """The prefix a tool should start its argument list with."""
    cmd: list[str] = []
    n = _nice()
    # `nice` is not on every PATH (it is on macOS and every Linux runner, but a
    # missing one must not break the encode).
    if n and shutil.which("nice"):
        cmd += ["nice", "-n", str(n)]
    cmd.append(binary)
    t = threads()
    # ffprobe has no -threads worth setting; only the encoder does.
    if t and binary == "ffmpeg":
        cmd += ["-threads", str(t)]
    return cmd


FFMPEG = ffmpeg_cmd("ffmpeg")
FFPROBE = ffmpeg_cmd("ffprobe")

if __name__ == "__main__":
    print("ffmpeg :", " ".join(FFMPEG))
    print("ffprobe:", " ".join(FFPROBE))
    print(f"(CI={on_ci()}, cores={os.cpu_count()}, threads={threads()})")
