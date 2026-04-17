# The 20 Design Crimes of Vibe Coding

Every vibe-coded app commits at least 5 of these. Fix them and you're ahead of 90%
of indie apps.

---

## Crime 1: No Visual Hierarchy
**What it looks like:** Everything is the same size, weight, and color. Nothing pops.
**Why it happens:** Developers add elements without thinking about importance.
**The fix:** Pick ONE thing per screen that matters most. Make it big, bold, high contrast. Make everything else progressively smaller and lighter.

## Crime 2: Random Spacing
**What it looks like:** 13px here, 17px there, 22px somewhere else. Nothing aligns.
**Why it happens:** Padding values entered by feel instead of system.
**The fix:** Use an 8px base scale: 4, 8, 12, 16, 24, 32, 48, 64. Nothing else.

## Crime 3: Too Many Colors
**What it looks like:** Rainbow soup. Every element a different color.
**Why it happens:** "More color = more interesting" (wrong).
**The fix:** One brand color. One semantic set (green/yellow/red/blue). One neutral scale. That's it. 90% of your UI should be neutrals.

## Crime 4: No Type Scale
**What it looks like:** Font sizes pulled from thin air. 14px, 16px, 18px, 15px, 13px all on one screen.
**Why it happens:** Each element sized independently without a system.
**The fix:** Define 8-10 type levels and ONLY use those. Display, Title 1, Title 2, Headline, Body, Callout, Subheadline, Footnote, Caption.

## Crime 5: Dark Mode as Afterthought
**What it looks like:** White text on slightly-less-white background. Invisible buttons. Broken contrast.
**Why it happens:** Built for light mode, then "just add a dark theme."
**The fix:** Design BOTH modes simultaneously. Every color needs a light/dark pair. Contrast elements need hardcoded values.

## Crime 6: No Loading States
**What it looks like:** Blank screen for 2 seconds, then content appears.
**Why it happens:** Developer tests with fast connection and cached data.
**The fix:** Skeleton screens. Show the layout with placeholder bones while data loads. Never show nothing.

## Crime 7: No Empty States
**What it looks like:** New user opens the app and sees a completely blank screen.
**Why it happens:** Developer always tests with existing data.
**The fix:** Design a friendly empty state with: illustration or icon + message explaining what will be here + CTA to add the first item.

## Crime 8: Mystery Meat Navigation
**What it looks like:** Icon-only buttons with no labels. Users tap randomly hoping to find features.
**Why it happens:** "Icons save space" and "users will figure it out."
**The fix:** Labels on everything. Icons + text. If you must use icon-only, add a tooltip.

## Crime 9: Invisible Tap Targets
**What it looks like:** Text that's tappable but looks like regular text. No button styling.
**Why it happens:** `onPress` was added to a `<Text>` instead of making a proper button.
**The fix:** If it's tappable, it needs to LOOK tappable. Background, border, or underline. Minimum 44×44pt.

## Crime 10: Wall of Text
**What it looks like:** Paragraphs of unbroken text. No headings, no spacing, no structure.
**Why it happens:** Content dumped onto the screen without formatting.
**The fix:** Break into sections with headings. Bullet points. Short paragraphs (2-3 lines). Adequate line spacing.

## Crime 11: Inconsistent Patterns
**What it looks like:** Settings screen uses radio buttons, another screen uses a dropdown for the same pattern.
**Why it happens:** Different screens built at different times without a component library.
**The fix:** Build a component library. Same problem = same component. Always.

## Crime 12: No Error Handling
**What it looks like:** Network fails silently. Form submits with invalid data. User has no idea what happened.
**Why it happens:** Happy path development. Only test when everything works.
**The fix:** Every action that can fail needs: error message (what happened), suggestion (what to do), retry action (try again button).

## Crime 13: Too Much On Screen
**What it looks like:** Settings page with 30 fields. Dashboard with 15 metrics. Feature overload.
**Why it happens:** "Users want options" (they want clarity).
**The fix:** Progressive disclosure. Show the essential. Hide the advanced. Use sections, expandable areas, and separate screens.

## Crime 14: Font Weight Sameness
**What it looks like:** Everything is regular weight or everything is bold. No differentiation.
**Why it happens:** Only using fontWeight 400 or 600 across the entire app.
**The fix:** Use the full range. 900 for display numbers. 800 for titles. 700 for section headers. 600 for button labels. 400 for body text.

## Crime 15: No Breathing Room
**What it looks like:** Elements crammed together. Text touching borders. Cards stacked with no gaps.
**Why it happens:** Trying to fit everything "above the fold."
**The fix:** White space is not wasted space. It creates visual grouping and reduces cognitive load. Embrace the scroll.

## Crime 16: Color Without Meaning
**What it looks like:** Blue button here, green button there, purple card, orange badge — no pattern.
**Why it happens:** Colors chosen for aesthetics, not communication.
**The fix:** Every color should MEAN something. Brand color = primary actions. Green = positive/money. Red = negative/error. Blue = information. Gray = disabled/secondary.

## Crime 17: Misaligned Elements
**What it looks like:** Labels don't align with inputs. Cards have different widths. Grid is off.
**Why it happens:** No layout grid, elements positioned by eye.
**The fix:** Use a grid system. Align to columns. Consistent horizontal padding (16px on mobile).

## Crime 18: Tiny Text for Style
**What it looks like:** 8px text because "it looks clean." Users squinting.
**Why it happens:** Confusing "minimal" with "illegible."
**The fix:** Body text minimum 15-17px on mobile. Footnote minimum 13px. Caption minimum 10px. Nothing smaller.

## Crime 19: No Feedback on Actions
**What it looks like:** User taps a button. Nothing happens. Did it work? They tap again.
**Why it happens:** No loading state, no success confirmation, no haptic feedback.
**The fix:** Every action needs feedback: loading spinner during processing, success message when done, haptic tap on press.

## Crime 20: Ignoring Platform Conventions
**What it looks like:** Android-style navigation on iOS. Custom tab bar that breaks gesture navigation.
**Why it happens:** Building a "unique" UI instead of a native-feeling one.
**The fix:** Follow platform conventions. iOS tab bar at bottom. Android material patterns. Users shouldn't have to learn your custom navigation.
