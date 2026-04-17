# Dark Mode Implementation Guide

## The Golden Rule

Dark mode is NOT "invert all the colors." It's a parallel design system where
every color is intentionally chosen for dark backgrounds.

## The Architecture

### Two Color Schemes, One API

```typescript
// Define BOTH schemes
const LightColors = {
  paper: '#F8F7F5',      // Warm light background
  white: '#FFFFFF',       // Card surface
  ink: '#1A1916',         // Primary text
  ink55: 'rgba(26,25,22,0.55)',  // Secondary text
  amber: '#D97706',       // Brand
  forest: '#2C5F2E',      // Positive
  negative: '#8B2020',    // Errors
};

const DarkColors = {
  paper: '#1A1916',       // Dark background
  white: '#242220',       // Dark card surface
  ink: '#F5F0EB',         // Light primary text
  ink55: 'rgba(245,240,235,0.55)', // Light secondary text
  amber: '#F59E0B',       // Brighter brand (for visibility)
  forest: '#5CB85F',      // Brighter positive
  negative: '#E05555',    // Brighter negative
};

// One hook, automatic switching
function useColors() {
  const isDark = useColorScheme() === 'dark';
  return isDark ? DarkColors : LightColors;
}
```

### Every Component Uses the Hook

```typescript
function MyComponent() {
  const Colors = useColors();
  const styles = useMemo(() => createStyles(Colors), [Colors]);
  // ...
}
```

## The 7 Dark Mode Patterns

### Pattern 1: Background Inversion
Light backgrounds become dark. Dark text becomes light.

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Page background | #F8F7F5 (warm cream) | #1A1916 (warm charcoal) |
| Card surface | #FFFFFF | #242220 |
| Elevated surface | #FFFFFF + shadow | #2E2C28 (lighter = higher) |

**Key insight:** In dark mode, elevation is shown by LIGHTENING the surface,
not by adding shadows (which are invisible on dark backgrounds).

### Pattern 2: Text Inversion
Dark text becomes light. But NOT pure white — use warm off-white.

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Primary text | #1A1916 | #F5F0EB |
| Secondary text | rgba(dark, 0.55) | rgba(light, 0.55) |
| Disabled text | rgba(dark, 0.35) | rgba(light, 0.35) |

**Key insight:** Pure white (#FFFFFF) text on dark backgrounds causes eye
strain. Use warm off-white (#F5F0EB or similar).

### Pattern 3: Brand Color Brightening
Brand colors that work on light backgrounds are too dark for dark backgrounds.
Brighten them.

| Color | Light Mode | Dark Mode |
|-------|-----------|-----------|
| Brand (amber) | #D97706 | #F59E0B (+2 stops brighter) |
| Positive (green) | #2C5F2E | #5CB85F (+3 stops brighter) |
| Negative (red) | #8B2020 | #E05555 (+3 stops brighter) |
| Warning (gold) | #8B6914 | #E0B040 (+3 stops brighter) |
| Info (blue) | #2D4A6B | #6BA3D6 (+3 stops brighter) |

### Pattern 4: Soft/Transparent Color Adjustment
Semi-transparent backgrounds (for badges, alerts, highlights) need
opacity adjustment for dark mode.

| Element | Light Mode | Dark Mode |
|---------|-----------|-----------|
| Brand soft bg | rgba(brand, 0.10) | rgba(brand, 0.15) |
| Brand border | rgba(brand, 0.22) | rgba(brand, 0.30) |

Slightly increase opacity in dark mode because the base color is brighter
and the background is darker.

### Pattern 5: Shadow Adjustment
Shadows are barely visible on dark backgrounds. Increase opacity dramatically.

| Shadow | Light Mode | Dark Mode |
|--------|-----------|-----------|
| Small | color: #1A1916, opacity: 0.07 | color: #000000, opacity: 0.20 |
| Medium | color: #1A1916, opacity: 0.09 | color: #000000, opacity: 0.25 |
| Large | color: #1A1916, opacity: 0.12 | color: #000000, opacity: 0.30 |
| Brand glow | color: brand, opacity: 0.25 | color: brand, opacity: 0.30 |

### Pattern 6: Hardcoded Contrast Elements
Some elements are DESIGNED to be dark — promotional banners, pills, badges.
These should NOT use theme colors.

```typescript
// BAD: Uses theme colors that invert
aiBanner: {
  backgroundColor: Colors.ink,    // ← Becomes LIGHT in dark mode!
  color: Colors.white,            // ← Becomes DARK in dark mode!
}

// GOOD: Hardcoded dark values
aiBanner: {
  backgroundColor: '#1A1916',     // Always dark
  color: '#FFFFFF',               // Always light
}
```

When to hardcode:
- Promotional banners or hero cards designed to be dark
- Pills/badges with dark backgrounds (like "TAX COACH · 2026")
- Tooltip backgrounds
- Overlay/dimming layers
- Any element that should maintain its contrast relationship in both modes

### Pattern 7: Border Visibility
Subtle borders can disappear in dark mode when the border color is too
close to the background color.

```typescript
// Light mode: paper3 (#E5E1DA) on white (#FFFFFF) = visible
// Dark mode: paper3 (#2E2C28) on paper (#1A1916) = still visible (good)

// But if paper3 were #1F1E1B, it would be invisible on #1A1916
```

Always verify border colors have sufficient contrast against their background
in both modes.

## Testing Checklist

For every screen, in dark mode:

- [ ] All text is readable (check against its actual background)
- [ ] No invisible elements (borders, dividers, subtle UI)
- [ ] Brand elements are still vibrant and visible
- [ ] Semantic colors are readable (green, red, yellow, blue)
- [ ] Contrast elements (banners, pills) are still high-contrast
- [ ] Cards are distinguishable from background
- [ ] Shadows provide some depth (or surfaces use elevation colors)
- [ ] Images have appropriate contrast (consider adding dark overlay or border)
- [ ] Semi-transparent elements are visible
- [ ] Loading/skeleton states are visible

## Common Bugs and Fixes

### Bug: Text invisible on banner
**Cause:** Banner uses `Colors.ink` (dark in light, light in dark) as bg,
text uses `Colors.white` (white in light, dark in dark).
**Fix:** Hardcode banner bg to `'#1A1916'` and text to `'#FFFFFF'`.

### Bug: Badge text unreadable
**Cause:** Amber text on amber soft background — in dark mode, both brighten
but the contrast ratio drops.
**Fix:** Ensure amber text on amber-soft bg maintains 4.5:1 in both modes.

### Bug: Dividers disappear
**Cause:** Divider color too close to background in dark mode.
**Fix:** Use a color with more contrast (paper3 or paper4 instead of paper2).

### Bug: Status colors too dark
**Cause:** Using dark red (#8B2020) for errors in dark mode.
**Fix:** Brighten to #E05555 in dark mode.
