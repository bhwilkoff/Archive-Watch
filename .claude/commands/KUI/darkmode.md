---
name: KUI:darkmode
description: "Audit and fix dark mode issues — contrast, inverted colors, hardcoded values"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - AskUserQuestion
---

# KUI:darkmode — Dark Mode Specialist

You are a dark mode expert. Dark mode is not just "invert the colors."
Find and fix every dark mode issue in the codebase.

## What This Phase Does

- Scans all UI code for dark mode issues
- Identifies hardcoded colors, broken contrast, invisible elements
- Categorizes issues by severity
- Can auto-fix common problems

## Arguments

```
/KUI:darkmode                     # Full audit
/KUI:darkmode --fix               # Audit AND fix
/KUI:darkmode --file <path>       # Audit specific file
```

## The 7 Deadly Dark Mode Sins

These are what you're hunting for:

### Sin 1: Hardcoded Colors
Colors written as literal hex/rgb values instead of theme tokens.
```
BAD:  color: '#FFFFFF'          ← white in both modes
GOOD: color: Colors.ink          ← adapts per mode
```

### Sin 2: Inverted Contrast Elements
Elements designed as "dark on light" that use theme colors — when the theme
inverts, both the background and text become the same brightness range.
```
BAD:  bg: Colors.ink, text: Colors.white
      → Light: dark bg + white text ✓
      → Dark:  light bg + dark text... wait, Colors.white is now dark too ✗

GOOD: bg: '#1A1916', text: '#FFFFFF'    ← Hardcode contrast elements
```

### Sin 3: Semi-Transparent Colors on Inverted Backgrounds
`rgba(255,255,255,0.5)` looks great on dark backgrounds but invisible on light ones (and vice versa).

### Sin 4: Border Colors That Disappear
Subtle borders using theme colors that become invisible when the background flips to a similar shade.

### Sin 5: Shadow Opacity Too Low
Light mode shadows at 7% opacity are invisible on dark backgrounds. Dark mode needs 20-30% opacity.

### Sin 6: Image/Icon Contrast
Dark icons on dark backgrounds, light images with no background treatment.

### Sin 7: Status Colors Not Adjusted
Semantic colors (red, green, yellow) that work on light backgrounds but are too dark for dark backgrounds. These need to brighten in dark mode.

## Step 1: Find Theme System

Locate the theming approach:
- Theme files (Glob: `**/theme/**`, `**/colors.*`)
- CSS variables, Tailwind dark classes, or RN useColors hooks
- Understand how colors are defined for light vs dark

## Step 2: Scan for Hardcoded Colors

Use Grep to find literal color values in UI files:

Search patterns:
- `#[0-9A-Fa-f]{3,8}` — Hex colors
- `rgb\(` / `rgba\(` — RGB values
- `'white'` / `'black'` — Named colors
- `hsl\(` — HSL values

For each hit, check:
- Is it in a StyleSheet or inline style? → Likely a problem
- Is it in a theme definition file? → That's fine
- Is it intentionally hardcoded for a contrast element? → Document it

## Step 3: Check Contrast Element Pattern

Find elements that use `Colors.ink` as background with `Colors.white` as text (or similar dark-bg-light-text patterns). These are the #1 cause of dark mode bugs.

Check:
- Promotional banners
- Pills and badges with dark backgrounds
- Buttons with inverted color schemes
- Header bars, navigation elements
- Cards with accent backgrounds

For each one: does it break when theme colors invert?

## Step 4: Check Semi-Transparent Colors

Find `rgba(` and `opacity:` usage:
- Is the semi-transparent color hardcoded or from the theme?
- Does it assume a specific background brightness?
- Will it be visible on both light and dark backgrounds?

## Step 5: Check Shadows

Find shadow definitions:
- Are there separate light/dark shadow values?
- Light mode: 5-12% opacity is typical
- Dark mode: 20-35% opacity needed for visibility
- Shadow color: #000 for dark mode (not ink color)

## Step 6: Produce Report

Write `.design/audit/darkmode-report.md`:

```markdown
# Dark Mode Audit Report

**Date:** YYYY-MM-DD
**Files Scanned:** X
**Issues Found:** X

## Summary
- Sin 1 (Hardcoded): X issues
- Sin 2 (Inverted Contrast): X issues
- Sin 3 (Semi-Transparent): X issues
- Sin 4 (Borders): X issues
- Sin 5 (Shadows): X issues
- Sin 6 (Images/Icons): X issues
- Sin 7 (Status Colors): X issues

## Issues

### Critical (invisible/unreadable elements)
| File:Line | Issue | Light Mode | Dark Mode | Fix |
|-----------|-------|-----------|-----------|-----|
| ... | ... | ... | ... | ... |

### Moderate (poor contrast but readable)
...

### Minor (aesthetic issues)
...
```

## Step 7: Auto-Fix (if --fix)

For each issue, apply the fix:

- **Hardcoded colors → theme tokens:** Replace hex with Colors.xxx
- **Inverted contrast → hardcoded dark:** Replace `Colors.ink` bg with `'#1A1916'`
- **Missing dark shadows:** Add dark mode shadow variants
- **Status colors:** Ensure semantic colors brighten in dark mode

Always explain what was changed and why.

## Step 8: Update State

Update `.design/STATE.json`.
Suggest `/KUI:review` for a full design audit if not done yet.
