# Spacing System

## The 8px Grid

Every spacing value in your app should be a multiple of 4 or 8. Period.

### The Scale

| Token | Value | Use |
|-------|-------|-----|
| `xs` | 4px | Tight gaps between icon and label, compact list items |
| `sm` | 8px | Between related items, chip gaps, small padding |
| `md` | 12px | Default component internal padding, form field spacing |
| `base` | 16px | Standard spacing unit, screen horizontal padding |
| `lg` | 24px | Between sections, after section labels |
| `xl` | 32px | Major section separation, before/after hero elements |
| `xxl` | 48px | Page-level vertical spacing, large gaps |
| `xxxl` | 64px | Hero sections, onboarding step spacing |

### Why These Numbers

- **4px** is the smallest unit the eye can reliably distinguish on mobile
- **8px** is the fundamental unit — most grid systems are 8px-based
- **12px** (8 + 4) fills the gap for component padding that 8 is too tight for
- **16px** (2 × 8) is the universal mobile padding (Apple and Material both use it)
- **24px** (3 × 8) creates clear section breaks
- The pattern: each step is roughly 1.5× the previous

### Magic Number Jail

These numbers are BANNED:
- 5px, 7px, 9px, 11px, 13px, 15px, 17px, 19px, 20px, 22px

If you find yourself reaching for a non-scale value, you're solving the
wrong problem. Adjust your layout, not your spacing.

**Exception:** 120px for bottom scroll padding (tab bar safe area) is fine
as a fixed value, not a spacing token.

## Layout Rules

### Screen Padding
```
Horizontal padding: 16px (base) on both sides
Top padding: 8px (sm) above header
Bottom scroll padding: 120px (safe area for tab bar + gesture)
```

### Section Spacing
```
Section label: 24px (lg) margin-top, 8px (sm) margin-bottom
Between cards in a section: 8px (sm)
Between sections: 24px (lg) — the section label handles this
```

### Component Internal Padding
```
Card: 16px (base) all sides
Button: 14px vertical, 24px (lg) horizontal
Input: 12px (md) vertical, 16px (base) horizontal
Badge/Pill: 3-4px vertical, 8px horizontal
Section label: 2px left margin (subtle offset)
```

### Form Spacing
```
Between label and input: 8px (sm)
Between input fields: 16px (base)
Between form sections: 24px (lg) with section label
Error message below input: 4px (xs) gap
```

## Spacing and Visual Grouping

The **Law of Proximity:** Items closer together are perceived as related.
Items farther apart are perceived as separate groups.

```
┌─────────────────────────┐
│ SECTION A               │  ← Section label
│ ┌─────────────────────┐ │
│ │ Item 1              │ │  ← 8px gap (related)
│ │ Item 2              │ │  ← 8px gap (related)
│ │ Item 3              │ │
│ └─────────────────────┘ │
│                         │  ← 24px gap (new section)
│ SECTION B               │  ← Section label
│ ┌─────────────────────┐ │
│ │ Item 4              │ │
│ │ Item 5              │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

Use spacing to create hierarchy:
- 4-8px: These things are part of the same element
- 12-16px: These things are related but distinct
- 24-32px: These are different sections
- 48-64px: These are different zones of the page

## Border Radius Scale

| Token | Value | Use |
|-------|-------|-----|
| `xs` | 4px | Inputs, small tags, inline code |
| `sm` | 8px | Buttons, chips, notifications |
| `md` | 12px | Dropdown menus, small cards |
| `lg` | 16px | Cards, modals, large containers |
| `xl` | 22px | Feature cards, hero elements |
| `xxl` | 32px | Large decorative elements |
| `full` | 999px | Pills, avatars, round buttons |

### Radius Rules
- **Nested elements:** Inner radius should be smaller than outer
  - Card (16px) > Inner card element (8px) > Input inside card (4px)
- **Consistency:** All cards same radius. All buttons same radius. All inputs same radius.
- **Never mix:** A 12px card next to a 16px card looks wrong. Pick one.
