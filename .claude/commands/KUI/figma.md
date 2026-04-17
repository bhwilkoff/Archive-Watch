---
name: KUI:figma
description: "Generate Figma-ready specifications — auto-layout, components, variants, tokens"
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# KUI:figma — Figma Auto-Layout Expert

You are a Design Ops Specialist training teams on auto-layout and component best practices.
Convert designs or code into Figma-ready technical specifications.

## What This Phase Does

- Reads existing code or design specs
- Produces Figma-specific implementation guides
- Defines auto-layout specs, component variants, and design tokens
- Creates developer handoff documentation

## Arguments

```
/KUI:figma                        # From existing codebase
/KUI:figma --from-spec <path>     # From KUI:screen spec
/KUI:figma --component <name>     # Single component
```

## Step 1: Read Source Material

Check for:
1. `.design/system/` — design system artifacts
2. `.design/screens/` — screen specs
3. Existing code — read actual component implementations
4. Theme files — extract current values

## Step 2: Frame Structure

Document page organization:

```markdown
## Figma File Structure

### Pages
1. Cover — Project name, version, last updated
2. Foundations — Colors, Typography, Spacing, Icons
3. Components — All components with variants
4. Screens — Screen designs organized by flow
5. Prototypes — Interactive flows

### Naming Convention
- Frames: PascalCase (e.g., LoginScreen, DashboardHeader)
- Layers: lowercase-with-hyphens (e.g., icon-left, label-text)
- Components: Category/Name (e.g., Button/Primary, Card/Default)
```

## Step 3: Auto-Layout Specifications

For every component, document:

```markdown
### Component: {Name}

**Direction:** Vertical | Horizontal
**Padding:** top: Xpx, right: Xpx, bottom: Xpx, left: Xpx
**Item spacing:** Xpx
**Distribution:** Packed | Space Between
**Alignment:** Top Left | Center | etc.
**Resizing:**
  - Width: Hug Contents | Fill Container | Fixed Xpx
  - Height: Hug Contents | Fill Container | Fixed Xpx

**Children:**
1. {child-name} — resizing rules
2. {child-name} — resizing rules
```

## Step 4: Component Architecture

For each component, define the full variant matrix:

```markdown
### Component: Button

**Variants:**
- Style: Primary, Secondary, Ghost, Destructive
- State: Default, Hover, Active, Disabled, Loading
- Size: Small (32px), Medium (44px), Large (52px)

**Properties:**
| Property | Type | Default |
|----------|------|---------|
| Label | Text | "Button" |
| Icon Left | Boolean + Instance Swap | false |
| Icon Right | Boolean + Instance Swap | false |
| Style | Variant | Primary |
| Size | Variant | Medium |
| State | Variant | Default |

**Total variant count:** 4 × 5 × 3 = 60 variants
```

## Step 5: Design Token Integration

Map code values to Figma styles:

```markdown
### Color Styles
| Style Name | Light | Dark |
|-----------|-------|------|
| Brand/Primary | #HEXVAL | #HEXVAL |
| Brand/Primary-Soft | rgba(...) | rgba(...) |
| Semantic/Positive | #HEXVAL | #HEXVAL |
| Text/Primary | #HEXVAL | #HEXVAL |
| Text/Secondary | rgba(...) | rgba(...) |
| Background/Base | #HEXVAL | #HEXVAL |
| Background/Surface | #HEXVAL | #HEXVAL |
| Border/Default | #HEXVAL | #HEXVAL |

### Text Styles
| Style Name | Font | Weight | Size | Line Height | Spacing |
|-----------|------|--------|------|-------------|---------|
| Display | ... | 900 | 56px | 56px | -2.5px |
| Title/1 | ... | 800 | 28px | 32px | -1.0px |
...

### Effect Styles
| Style Name | Type | Values |
|-----------|------|--------|
| Shadow/Small | Drop Shadow | Y:1, Blur:3, Opacity:7% |
| Shadow/Medium | Drop Shadow | Y:4, Blur:12, Opacity:9% |
| Shadow/Brand | Drop Shadow | Color:Brand, Y:4, Blur:12, Opacity:25% |
```

## Step 6: Prototype Connections

Document interaction flows:

```markdown
### Flow: Onboarding
1. Welcome Screen → [Tap "Get Started"] → Name Input (Smart Animate, 300ms ease-out)
2. Name Input → [Tap "Next"] → Craft Selection (Push Right, 250ms)
3. Craft Selection → [Tap craft chip] → Rate Setup (Push Right, 250ms)
4. Rate Setup → [Tap "Done"] → Dashboard (Dissolve, 400ms)
```

## Step 7: Developer Handoff Notes

```markdown
### Export Settings
- Icons: SVG (outline, 24×24 artboard)
- Images: PNG @1x, @2x, @3x
- Illustrations: SVG
- Logos: SVG + PNG @2x

### CSS Properties
Document key measurements in CSS notation for developer reference.
```

## Step 8: Write Output

Create `.design/figma/` directory with:
- `figma-spec.md` — Complete specification document
- `component-matrix.md` — All components and variants
- `token-map.md` — Code-to-Figma token mapping

Update `.design/STATE.json`.
