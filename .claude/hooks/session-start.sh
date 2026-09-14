#!/bin/bash
# Runs at every Claude Code session start. CLAUDE.md, SCRATCHPAD.md and
# DECISIONS.md are already loaded by Claude Code itself (CLAUDE.md imports
# the other two), so this hook must NOT print them again — it used to, and
# that doubled ~14 KB of context per session. It prints only what those
# files cannot know: the live git + version state, in one short block.
[ -f CLAUDE.md ] || { echo "=== CLAUDE.md not found ==="; exit 0; }
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
head=$(git log -1 --format='%h %s' 2>/dev/null | cut -c1-90)
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
ver=$(grep -E '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)' AppVersion.xcconfig 2>/dev/null | awk -F'= ' '{printf "%s ", $2}')
vc=$(grep -E '^\s*versionCode = ' android/app/build.gradle.kts 2>/dev/null | head -1 | awk -F'= ' '{print $2}')
echo "=== SESSION START === $(date '+%Y-%m-%d %H:%M') · branch $branch · HEAD $head · ${dirty} dirty file(s) · Apple ${ver}· Android vc${vc}"
