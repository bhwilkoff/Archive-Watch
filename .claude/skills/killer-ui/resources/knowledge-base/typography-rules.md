# Typography Rules for Developers

## The Type Scale

Every app needs exactly ONE type scale. Here's the proven scale based on
Apple HIG, Material Design, and production app patterns:

| Level | Size | Weight | Line Height | Letter Spacing | Use |
|-------|------|--------|-------------|----------------|-----|
| Display | 48-56px | 900 (Black) | 1.0× | -2.5px | Hero numbers, revenue totals |
| Large Title | 34px | 800 (ExtraBold) | 1.06× | -1.5px | Wordmarks, landing headers |
| Title 1 | 28px | 800 | 1.14× | -1.0px | Screen headers |
| Title 2 | 22px | 700 (Bold) | 1.18× | -0.5px | Section headers, card titles |
| Headline | 17px | 600 (SemiBold) | 1.29× | -0.2px | List titles, button labels |
| Body | 17px | 400 (Regular) | 1.41× | -0.2px | Standard readable text |
| Callout | 16px | 400 | 1.38× | -0.1px | Descriptions, helper text |
| Subheadline | 15px | 400 | 1.33× | 0 | Secondary text, metadata |
| Footnote | 13px | 400 | 1.38× | 0 | Timestamps, tertiary info |
| Caption | 10-11px | 700 | 1.27× | +0.8px | Section labels, ALWAYS UPPERCASE |
| Mono | 13px | 500 | 1.38× | 0 | Financial numbers, code |

## The Rules

### Rule 1: Use the Scale — Nothing Else
If you need 19px text, you don't need 19px text. You need to pick between
Headline (17px) or Title 2 (22px). The scale exists to create visual rhythm.
Breaking it creates visual noise.

### Rule 2: Weight Creates Hierarchy
Don't just size things differently. Weight is equally powerful:

```
900 — Display numbers (revenue, stats)
800 — Titles and headers
700 — Section labels, important callouts
600 — Button labels, list titles
500 — Emphasized body text
400 — Regular body text
```

Using only 400 and 600 is a waste. The full range creates rich hierarchy.

### Rule 3: Letter Spacing Rules

| Size Range | Letter Spacing | Why |
|-----------|---------------|-----|
| 28px+ (Display, Title) | -1 to -2.5px | Large text needs tightening to feel cohesive |
| 15-22px (Body, Headline) | -0.2 to 0px | Neutral — default rendering is fine |
| 10-13px (Caption, Footnote) | +0.5 to +0.8px | Small text needs tracking to stay legible |

Caption text: ALWAYS add positive letter spacing AND uppercase. This is the
universal convention for section labels.

### Rule 4: Line Length
- **Optimal:** 45-75 characters per line
- **Mobile:** Usually fine due to narrow screens (16px padding each side)
- **Tablet/Desktop:** Constrain text width (max-width: 640px for prose)
- **Never:** Full-width paragraphs on a wide screen

### Rule 5: Line Height
- **Body text:** 1.4-1.5× font size (comfortable reading)
- **Headings:** 1.0-1.2× font size (tight, impactful)
- **Captions:** 1.2-1.3× font size (compact but legible)

Too little: text feels cramped and hard to read.
Too much: text feels disconnected, lines float apart.

### Rule 6: Font Pairing
- **One font is enough** for most apps. Vary by weight and size instead.
- **Two fonts max.** One for headings (can be more expressive), one for body (must be highly readable).
- **Never three fonts.** That's a mess.

### Font Recommendations by Brand Type

| Brand Type | Primary Font | Why |
|-----------|-------------|-----|
| Clean/Modern | SF Pro, Inter, Geist | Neutral, excellent readability |
| Premium/Luxury | Playfair Display + Inter | Serif heading + clean body |
| Bold/Startup | Space Grotesk, Satoshi | Geometric, contemporary |
| Warm/Craft | Lora + Source Sans | Friendly serif + clean sans |
| Technical | JetBrains Mono + Inter | Mono heading + clean body |

### Rule 7: Minimum Sizes

| Platform | Body Minimum | Footnote Minimum | Caption Minimum |
|----------|-------------|-----------------|-----------------|
| Mobile | 15px | 13px | 10px |
| Tablet | 16px | 13px | 11px |
| Desktop | 16px | 14px | 12px |

Below 10px is illegible on any screen. Don't do it.

### Rule 8: Color and Typography

- **Primary text:** Full opacity ink color (100%)
- **Secondary text:** 55-80% opacity
- **Tertiary/disabled:** 35% opacity
- **Placeholder text:** 35% opacity (same as disabled)
- **Links/actions:** Brand color
- **Positive/negative:** Semantic colors (green/red)

Never use light gray text on a white background for important content.
It fails WCAG contrast and frustrates users.

## Common Typography Crimes

1. **All caps everywhere.** ALL CAPS is for labels (caption level) only. Body text in all caps is aggressive and hard to read.

2. **Underlines for emphasis.** Underlines mean links on the web. Use bold or color for emphasis instead.

3. **Center-aligned body text.** Center alignment is for headings and short text only. Body paragraphs must be left-aligned.

4. **Justified text on mobile.** Justification creates ugly word spacing on narrow screens. Always use left-align on mobile.

5. **Bold everything.** If everything is bold, nothing is bold. Reserve bold for actual emphasis.
