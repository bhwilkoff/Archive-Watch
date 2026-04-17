# Color Theory for Developers

## The Psychology of Color

| Color | Emotion | Use For | Avoid When |
|-------|---------|---------|------------|
| **Red** | Urgency, danger, passion | Errors, destructive actions, sales | Calm/trust contexts |
| **Orange/Amber** | Energy, warmth, attention | CTAs, highlights, brand warmth | Clinical/corporate |
| **Yellow/Gold** | Optimism, warning, premium | Warnings, premium indicators | Small text (low contrast) |
| **Green** | Growth, success, money | Positive states, financial gains | Errors, warnings |
| **Blue** | Trust, calm, professional | Links, info states, corporate | Urgency, warmth |
| **Purple** | Luxury, creativity, wisdom | Premium features, creative tools | Everyday/practical |
| **Pink** | Playful, feminine, bold | Youth brands, fashion, beauty | Finance, enterprise |
| **Black** | Sophistication, authority | Luxury, premium, typography | Approachable/casual |
| **White** | Clean, minimal, space | Backgrounds, breathing room | Warm/cozy brands |

## Building a Palette

### Step 1: Choose a Brand Color
One color that represents your brand. This is your hero.
- **Warm brands:** Amber, Orange, Red-Orange
- **Trust brands:** Blue, Teal
- **Growth brands:** Green, Emerald
- **Premium brands:** Deep Purple, Black, Gold
- **Playful brands:** Pink, Coral, Bright Blue

### Step 2: Generate Shades
Every brand color needs a scale:

| Shade | Use |
|-------|-----|
| 50 (lightest) | Soft backgrounds (10% opacity) |
| 100 | Hover states, subtle fills |
| 300 | Borders, light accents |
| 500 (base) | Primary brand color |
| 700 | Dark variant for text on light backgrounds |
| 900 (darkest) | Heavy emphasis, dark mode base |

### Step 3: Add Semantic Colors
These are universal — every app needs them:

| Semantic | Color Family | Light Mode | Dark Mode |
|----------|-------------|------------|-----------|
| Positive | Green | Deep green (#2C5F2E) | Bright green (#5CB85F) |
| Warning | Gold/Amber | Dark gold (#8B6914) | Bright gold (#E0B040) |
| Negative | Red | Dark red (#8B2020) | Bright red (#E05555) |
| Info | Blue | Deep blue (#2D4A6B) | Bright blue (#6BA3D6) |

Each semantic color needs:
- **Base** — for text and icons
- **Soft** — 10-15% opacity background
- **Border** — 20-30% opacity border

### Step 4: Build the Neutral Scale
Warm neutrals feel handmade. Cool neutrals feel corporate. Choose based on brand.

**Warm neutral scale (recommended for most apps):**

| Token | Light Mode | Dark Mode | Use |
|-------|-----------|-----------|-----|
| paper (bg) | #F8F7F5 | #1A1916 | Page background |
| paper2 | #F0EDE8 | #1F1E1B | Subtle background |
| paper3 | #E5E1DA | #2E2C28 | Borders, dividers |
| paper4 | #D4CFC7 | #3D3A34 | Disabled, heavy border |
| white (surface) | #FFFFFF | #242220 | Card backgrounds |

**Ink (text) scale:**

| Token | Light Mode | Dark Mode | Use |
|-------|-----------|-----------|-----|
| ink | #1A1916 | #F5F0EB | Primary text |
| ink80 | 80% opacity | 80% opacity | Emphasized secondary |
| ink55 | 55% opacity | 55% opacity | Secondary text |
| ink35 | 35% opacity | 35% opacity | Placeholder, disabled |
| ink15 | 15% opacity | 15% opacity | Subtle borders |
| ink08 | 8% opacity | 8% opacity | Hover backgrounds |

## Dark Mode Color Rules

### Rule 1: Don't Just Invert
Inverting makes everything look wrong. Instead:
- Backgrounds: Dark (not black — use dark warm gray)
- Text: Light (not white — use warm off-white)
- Brand colors: Brighten slightly for visibility on dark backgrounds
- Semantic colors: Brighten significantly (deep red → bright red)

### Rule 2: Reduce Contrast Slightly
Light mode: ink on paper = maximum contrast.
Dark mode: Reduce from pure white (#FFFFFF) to warm off-white (#F5F0EB).
Less eye strain, more comfortable reading.

### Rule 3: Elevate with Lightness, Not Shadow
In light mode, shadows create elevation (cards float above background).
In dark mode, shadows are nearly invisible. Instead, use slightly lighter
surface colors to indicate elevation.

| Level | Light Mode | Dark Mode |
|-------|-----------|-----------|
| Background | #F8F7F5 | #1A1916 |
| Surface (card) | #FFFFFF | #242220 |
| Elevated (modal) | #FFFFFF + shadow | #2E2C28 |

### Rule 4: Increase Shadow Opacity
When you do use shadows in dark mode:
- Light mode shadows: 5-12% opacity
- Dark mode shadows: 20-35% opacity
- Always use pure black (#000) for dark mode shadow color

## Contrast Ratio Quick Reference

| Ratio | Passes | Use For |
|-------|--------|---------|
| 7:1+ | AAA | Small text, maximum accessibility |
| 4.5:1+ | AA (required) | Normal text (under 18px) |
| 3:1+ | AA Large | Large text (18px+), UI components |
| Below 3:1 | FAILS | Nothing — fix it |

### Common Failing Pairs
- Light gray (#999) on white (#FFF) → 2.8:1 FAIL
- Medium gray (#777) on white (#FFF) → 4.5:1 PASS (barely)
- Amber (#D97706) on white (#FFF) → 3.1:1 — only OK for large text
- Light text on light background in dark mode — check every pair
