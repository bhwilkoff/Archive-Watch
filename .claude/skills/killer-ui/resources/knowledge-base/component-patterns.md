# Component Design Patterns

## Universal Component Rules

1. **Every component supports theming** — takes colors from a hook, never hardcodes
2. **Every component has ALL states** — default, hover, active, disabled, loading, error
3. **Every component is accessible** — labels, roles, focus, contrast
4. **Every component works in dark mode** — tested in both modes

## Component Catalog

### Buttons

**Hierarchy (one primary per screen):**

| Variant | Background | Text | Border | Shadow | Use |
|---------|-----------|------|--------|--------|-----|
| Primary | Brand color | White | None | Brand glow | Main CTA — ONE per screen |
| Secondary | Surface | Primary text | 1px border | Subtle | Supporting actions |
| Ghost | Brand soft | Brand color | 1px brand border | None | Tertiary actions |
| Destructive | Red | White | None | Red glow | Delete, remove, cancel |

**Sizing:**

| Size | Height | Padding | Font | Use |
|------|--------|---------|------|-----|
| Small | 32px | 6px / 12px | 13px, 600 | Inline actions, compact UI |
| Medium | 44px | 14px / 24px | 17px, 600 | Standard buttons |
| Large | 52px | 18px / 32px | 17px, 700 | Primary CTAs, wide layout |

**States:**
- **Default:** Normal appearance
- **Hover:** Slightly darkened (web only)
- **Active/Pressed:** opacity 0.85 (activeOpacity on RN)
- **Disabled:** Muted background (paper2), no shadow, text at 35% opacity
- **Loading:** Spinner replaces text, button disabled

### Cards

**Anatomy:**
```
┌─ accent border (optional, 4px left) ───────────┐
│                                                  │
│  [Section Label]              [Action Button]    │
│  [Title Text]                                    │
│  [Body Content]                                  │
│  ─────────── divider ───────────                │
│  [Info Row: label          value]                │
│  ─────────── divider ───────────                │
│  [Info Row: label          value]                │
│                                                  │
└──────────────────────────────────────────────────┘
```

**Specs:**
- Background: Surface color (white/dark surface)
- Border: 1px, subtle border color
- Border radius: 16px (lg)
- Shadow: sm (subtle elevation)
- Padding: 16px (base)
- Accent border: Optional 4px left border in brand or semantic color

**Variants:**
- **Default:** Standard card
- **Accent:** Left border highlight (categorization, status)
- **Interactive:** Tap handler + slight scale on press
- **Flat:** No shadow (for nested/grouped cards)

### Inputs

**Anatomy:**
```
LABEL (caption style, uppercase, 35% opacity)
┌──────────────────────────────────────┐
│ Placeholder or value text            │
└──────────────────────────────────────┘
Helper text or error message
```

**Specs:**
- Background: Page background color (not surface)
- Border: 1px, subtle border color
- Border radius: 4px (xs)
- Padding: 12px vertical, 16px horizontal
- Font: 16px, regular weight
- Placeholder: 35% opacity text

**States:**
- **Default:** Subtle border
- **Focused:** Brand color border (2px)
- **Error:** Red border + red error message below
- **Disabled:** Reduced opacity (50%), no interaction
- **Filled:** Normal appearance with value text

### Badges

**Anatomy:** Pill shape with text

**Variants:**

| Variant | Background | Border | Text | Use |
|---------|-----------|--------|------|-----|
| ok | Green soft | Green border | Green | Positive status |
| low | Gold soft | Gold border | Gold | Warning status |
| critical | Red soft | Red border | Red | Error/urgent |
| amber | Brand soft | Brand border | Brand | Highlight |
| info | Blue soft | Blue border | Blue | Informational |
| neutral | Paper2 | Paper3 | ink55 | Default/inactive |

**Specs:**
- Border radius: full (999px) — always pill shape
- Padding: 3px vertical, 8px horizontal
- Font: 10px, 700 weight
- Self-aligning: `alignSelf: 'flex-start'`

### Section Labels

**The glue between sections.**

```
LABEL TEXT (caption style)
```

**Specs:**
- Font: Caption level (10px, 700 weight, 0.8px letter spacing)
- Color: 35% opacity text
- Text: ALWAYS UPPERCASE
- Margin: 24px top (creates section break), 8px bottom
- Left margin: 2px (subtle offset from card edges)

### Alerts / Alert Strips

**Anatomy:**
```
┌─────────────────────────────────────────┐
│ 🔔  Title text              [CTA Link] │
│     Subtitle / detail text              │
└─────────────────────────────────────────┘
```

**Variants:** ok (green), warn (gold), error (red), info (blue)

Each variant uses:
- Background: Semantic soft color (10-15% opacity)
- Border: 1px semantic border (20-30% opacity)
- Title: Semantic base color, 12px, 700 weight
- Subtitle: ink55, 11px
- CTA: Brand color, 11px, 700 weight

### Progress Bars

**Anatomy:**
```
Label                              Value
[████████████░░░░░░░░░░░░░░░░░░░]
```

**Specs:**
- Track height: 5px
- Track background: Border color (paper3)
- Track radius: full (99px)
- Fill: Semantic color (brand, green, etc.)
- Label: Footnote style (13px, 500 weight)
- Value: Footnote style, secondary color

### Stat Cards

**Anatomy:**
```
┌──────────────────────┐
│ LABEL (caption)      │
│ $12,450 (display)    │
│ ↑ 12% vs last month  │
└──────────────────────┘
```

**Specs:**
- Label: Caption style (10px, uppercase, 35% opacity)
- Value: 28px, 900 weight, -1px letter spacing
- Change indicator: Footnote style, green (positive) or red (negative)
- Card padding: 16px (base)

### Dividers

**The simplest component, most commonly screwed up.**

```
────────────────────────────
```

**Specs:**
- Height: 1px
- Color: Border color (paper3)
- Horizontal margin: 16px (base) — indent from card edges
- Never full-width within a card
- Used between related items in a list/card
