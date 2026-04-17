#!/bin/bash
# Runs silently at every Claude Code session start.
# Injects project context without requiring manual orientation.

if [ ! -f "CLAUDE.md" ]; then
  echo "=== CLAUDE.md not found — fill it in to get started ==="
  exit 0
fi

echo "=== PROJECT CONTEXT ==="
cat CLAUDE.md
echo ""

if [ -f "SCRATCHPAD.md" ]; then
  echo "=== CURRENT STATE ==="
  awk '/^## Current State/,/^---/' SCRATCHPAD.md | head -n -1
  echo ""
fi

echo "=== END OF SESSION CONTEXT ==="
