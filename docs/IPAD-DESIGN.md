# Archive Watch — iPad Design (BINDING)

**Binding.** Every surface the iPad shows at **regular width** must trace to a
rule here or in `docs/iOS-DESIGN.md`. This document does not replace that one —
it **extends** it. Where the two could be read as disagreeing, iOS-DESIGN.md
wins on shell and taxonomy; this document wins on composition and measure at
regular width.

**The thesis, and the reason this file exists.** The owner's brief: *"The iPad
should not just be a blown up version of the phone, but rather a distinct and
first class experience."* The failure mode is not ugliness — the iPad build
looks clean and has **zero clipped text** (measured, 2026-08-28). The failure
mode is that a layout designed for 390 points, stretched to 1366, produces
controls and text measures no designer would choose: a Play button over a
thousand points wide, and body copy at 115 characters a line.

**What is already right, and must not be "fixed".** The shell is shared by
design — iOS-DESIGN.md §2.2: *"One shell, both form factors… bottom tab bar on
iPhone, sidebar on iPad/regular width. Do not add a parallel
`NavigationSplitView` code path; adaptivity comes from the one control."* That
is working: the iPad draws a real sidebar with the five content verbs. Home's
hero is already correct too — §5.6 mandates a *"width-capped centered card
(~760 pt) on iPad/regular so a wide screen never stretches the strip into an
extreme crop"*, and it does exactly that. **Browse already adapts** to eight
poster columns. None of that is the gap.

---

## §1 — Principles

1.1 **The iPad is a different composition of the same parts, not a different
app.** One shell, one destination registry, one data plane. What changes at
regular width is how much sits side by side, and how wide a line of text is
allowed to get — never which features exist.

1.2 **Adaptivity is by size class, never by device.** `@Environment(\.horizontalSizeClass)`,
matching iOS-DESIGN.md §2.2's explicit ban on `UIDevice` checks. This is what
makes an iPhone in landscape, an iPad in Split View, and a Mac window all
correct for free — and it is why "iPad rules" in this file are really
*regular-width* rules.

1.3 **Density comes from more content, not from bigger content.** The CLAUDE.md
density rule ("density comes from removing chrome, not adding decoration")
applies with a large screen's twist: a wide screen earns MORE items per row and
MORE rows in view, never larger versions of the same items.

1.4 **A control's width is a claim about its importance.** A button that spans
a 12.9-inch screen claims to be the most important thing in the app. Primary
actions get a comfortable, deliberate size at regular width — not the whole
window.

---

## §2 — Measure (binding; the core rule this file adds)

2.1 **Reading content is capped at 700 pt.** Any run of prose — synopsis,
tagline, footer explanation, the body of a settings section — is constrained to
a maximum width of **700 points** at regular width, leading-aligned within its
column. Below that width nothing changes, so the iPhone is untouched.

> **Why 700.** Measured on the device: iPad Detail body copy ran **107–115
> characters per line** across ~1030 pt. The long-standing typographic range is
> 45–75 characters, and the app's `.body` style lands near 65 characters at
> 700 pt. This is the same instinct §5.6 already applied to the Home hero,
> generalised from art to text.

2.2 **A primary action is capped at 480 pt** at regular width, leading-aligned
with its content column — never `maxWidth: .infinity` across the window. The
measured violation: "Resume · 88 min" rendered ~1040 pt wide.

2.3 **The cap is on the CONTENT, not the screen.** Width-capped content sits in
a leading-aligned column inside the available width; the surrounding space is
deliberate, not an error to be filled. Where a surface has a natural second
column (§3), that space is used instead.

---

## §3 — Detail at regular width (binding)

3.1 **Detail is two columns on regular width:** artwork in a leading column,
identity and actions in a trailing column beside it, with the prose below the
pair at the §2.1 measure. On compact width it stays the single stacked column
iOS-DESIGN.md already describes. Both come from one view; there is no second
Detail implementation.

3.2 **The action row never scrolls on regular width.** The `ViewThatFits`
introduced for the iPhone (seven buttons that no longer fit 390 pt) resolves to
the plain row here, because it fits — which is exactly what that construct is
for. Do not special-case it.

3.3 **Cast, More Like This and community rows keep their horizontal scroll**,
showing more members per screen at regular width. A wide screen means more
faces visible, not bigger faces.

---

## §4 — Grids and shelves at regular width (binding)

4.1 **Browse's adaptive grid is the sanctioned pattern** — a minimum tile width
with `LazyVGrid(.adaptive)`, which yields eight columns at 1366 pt and three on
a phone from one declaration. Verified correct on the device; do not convert it
to a fixed column count.

4.2 **Shelf rows show more tiles, at the same tile size.** A shelf on iPad
reveals more of its row; it does not enlarge its posters.

---

## §5 — Orientation (binding)

5.1 **Both orientations are first class.** The 12.9-inch iPad is 1366×1024
landscape and 1024×1366 portrait, and both are regular width — so §2 and §3
apply in both. Portrait is not a "big phone" state.

5.2 **No layout may depend on orientation directly.** Compose from size class
and available width; a rule keyed to `isLandscape` is a rule that breaks in
Split View and Stage Manager.

---

## §6 — Anti-patterns (never)

6.1 **Never `frame(maxWidth: .infinity)` on prose or on a primary button**
without a companion cap at regular width. This is the single defect class this
document exists to prevent.

6.2 **Never a parallel iPad view.** iOS-DESIGN.md §2.2 forbids a second shell;
this extends it to surfaces — no `DetailView_iPad`. One view, size-class
branches inside it.

6.3 **Never `UIDevice.current.userInterfaceIdiom`.** See §1.2.

6.4 **Never fill space merely because it exists.** Empty margin beside capped
content is correct. Adding a decorative panel to fill it is decoration, which
§1.3 rejects.

---

## §7 — The tests (run before any iPad surface ships)

7.1 **The measure test.** Screenshot the surface at 1366 pt and count
characters on the longest line of prose. Over ~80 and the surface violates
§2.1. `tools/ios_scenario.py measure` reports this per screenshot.

7.2 **The claim test.** Is any control wider than 480 pt? If so, does it
genuinely claim to be the most important thing on screen (§1.4)?

7.3 **The both-orientations test.** The same surface, rotated, still obeys
§2 and §3 — asserted by the harness, which rotates the device rather than
trusting that it would.

7.4 **The compact-unchanged test.** Every iPad change must leave the iPhone
byte-identical in behaviour: the audit suite in `docs/IPHONE-12-AUDIT.md` must
stay green on the iPhone 12 after any change made for this document.
