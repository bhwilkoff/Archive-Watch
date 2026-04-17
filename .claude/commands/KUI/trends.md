---
name: KUI:trends
description: "Research and synthesize current design trends for any industry"
allowed-tools:
  - Read
  - Write
  - Glob
  - Grep
  - Task
  - AskUserQuestion
  - WebSearch
  - WebFetch
---

# KUI:trends — Design Trend Synthesizer

You are a Design Researcher analyzing trends for clients.
Research and synthesize current design trends.

## What This Phase Does

- Researches current design trends for the user's industry
- Maps competitive landscape
- Identifies opportunities and risks
- Produces actionable recommendations with mood board specs

## Arguments

```
/KUI:trends <industry>            # e.g., "fintech", "e-commerce", "craft marketplace"
/KUI:trends --platform ios|web    # Platform-specific trends
/KUI:trends --year 2026           # Specific year focus
```

## Step 1: Context

Ask the user:
1. What industry/sector?
2. Who are your top 3-5 competitors?
3. What's your current design style? (or "starting fresh")

## Step 2: Research Current Trends

Use WebSearch to research:
- "[industry] design trends 2026"
- "[industry] UI UX trends"
- "Apple WWDC design updates 2026"
- "Material Design updates 2026"
- "web design trends 2026"

## Step 3: Macro Trend Analysis

Identify and document 5 major trends:

For each trend:

```markdown
### Trend: {Name}

**Definition:** What it is in one sentence
**Visual Characteristics:** Colors, shapes, typography, imagery
**Origin:** Where it started, early adopters
**Adoption Phase:** Emerging | Growing | Mature | Declining
**Examples:** 3 brands using it well (with descriptions)
**Strategic Implications:**
- Opportunity: ...
- Risk: ...
```

Trend areas to cover:
- **Visual aesthetics** (glassmorphism, neo-brutalism, organic shapes, etc.)
- **Interaction patterns** (gesture-first, voice, AI-assisted, spatial)
- **Color trends** (dopamine palettes, muted earth tones, monochrome)
- **Typography trends** (variable fonts, oversized type, kinetic)
- **Technology influence** (spatial computing, generative UI, adaptive interfaces)

## Step 4: Competitive Landscape

Map 8-10 competitors on a 2×2 matrix:

```
         Innovative
             │
    ┌────────┼────────┐
    │   ●A   │   ●B   │
    │        │ ●C     │
Minimal──────┼──────Rich
    │     ●D │        │
    │        │   ●E   │
    └────────┼────────┘
             │
        Conservative
```

- Where are clusters? (overserved areas to avoid)
- Where's white space? (opportunity zones)
- Where should the user position?

## Step 5: Platform Evolution

Document current platform design languages:
- **iOS/visionOS:** Latest HIG updates, Liquid Glass, dynamic elements
- **Material Design:** Latest M3 updates, adaptive layouts, color system
- **Web:** CSS features enabling new patterns (container queries, view transitions, color-mix)

## Step 6: Strategic Recommendations

```markdown
## Adopt These Trends
1. {Trend} — How to adapt it for your brand. Implementation priority: High.
2. ...

## Watch These Trends
1. {Trend} — Not ready yet, but keep an eye on it. Revisit in 6 months.

## Avoid These Trends
1. {Trend} — Why it's wrong for your brand/audience.
```

## Step 7: Mood Board Specifications

Describe 15-20 visual references:

```markdown
### Reference 1: {Description}
- **Source:** App/website name
- **What to take from it:** Specific element or pattern
- **Color palette:** Extracted hex values
- **Typography:** Font style and usage
- **Mood:** Emotional quality
```

## Step 8: Write Output

Create `.design/trends/`:
- `trend-report.md` — Full analysis
- `competitive-map.md` — Landscape analysis
- `recommendations.md` — Action plan

Update `.design/STATE.json`.
