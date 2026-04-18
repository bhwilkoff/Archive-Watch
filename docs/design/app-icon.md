# App Icon — Direction & Spec

> "A film frame that looks realistic with a bold color background."

---

## Concept

A single, beautifully composed 35mm film frame floats in the center of
a saturated, flat color field. The frame is **photographic** — a real
still from a public-domain film, not an illustration of a frame — with
its sprocket holes (perforations) visible top and bottom in true black,
crisp against the colored background.

The icon reads instantly:
- **Film** (the perforated strip is universally legible)
- **Curated** (the framing implies someone *chose* this still)
- **Premium** (saturated flat color + photographic still ≠ cheap stock app)

It does not try to be:
- A play button (every video app has one)
- A reel (literal, dated, hard to render small)
- A TV set (we are not a TV; we play TV)

---

## Layout (1024×1024 master)

```
+--------------------------------------------------+
|                                                  |
|   [BG: bold flat color, full bleed]              |
|                                                  |
|       ┌─■──■──■──■──■──■──■──■──■──■──┐          |
|       │                                │          |
|       │                                │          |
|       │     [PHOTOGRAPHIC FILM         │          |
|       │      STILL — 1.85:1 OR         │          |
|       │      1.37:1 ACADEMY]           │          |
|       │                                │          |
|       │                                │          |
|       └─■──■──■──■──■──■──■──■──■──■──┘          |
|                                                  |
|                                                  |
+--------------------------------------------------+
```

- **Bleed:** Full background color out to the rounded square edge.
  tvOS app icons are layered (front + middle + back PNGs); the
  background is the back layer.
- **Frame size:** ~720px wide, centered. Leave ≥ 140px breathing
  room on all sides so it survives Top Shelf cropping.
- **Aspect ratio of the still:** Use **Academy 1.37:1** for early /
  silent / classic TV stills (matches their native aspect). Use
  **1.85:1** for modern features. Pick per icon variant — see
  rotation below.
- **Sprocket holes:** 10–12 perforations across, true black with a
  1px inner highlight (mimics film stock). They sit in the gutters
  above and below the still, not overlapping the image.
- **Frame border:** A thin (~3px) charcoal line around the still
  separates it from the black sprocket strip. Adds intentionality.

---

## Color (the bold background)

The background color is **not** drawn from the still — it is a
deliberate counterpoint. Use one of the eight category accent colors
declared in `featured.json`. For the launch icon, pick the marquee
orange:

| Layer       | Token         | Hex       |
|-------------|---------------|-----------|
| Background  | `--color-accent` | `#FF5C35` |
| Sprocket    | true black    | `#000000` |
| Inner sprocket highlight | hairline white | `rgba(255,255,255,0.18)` |
| Frame border | charcoal     | `#1A1A1A` |

Optional: subtle vignette (radial darkening, 6–8% at corners) to focus
the eye on the still without flattening the bold field.

---

## Typography in the icon

**None.** No "AW" monogram, no wordmark, no tagline. The film frame
*is* the brand. Apple TV's own icon, Plex's, Apple TV+ — none use type.
Type at icon scale becomes a smudge.

---

## Variants

tvOS icons are layered (App Icon + Top Shelf Image + Top Shelf Wide).
Each gets its own composition:

| Asset              | Size            | Composition                          |
|--------------------|-----------------|--------------------------------------|
| App Icon front     | 400 × 240       | Sprocketed frame, no background      |
| App Icon middle    | 400 × 240       | Empty (transparent) — used for parallax depth |
| App Icon back      | 1280 × 768      | Solid bold color field, slight vignette |
| Top Shelf Image    | 1920 × 720      | Wide field, frame off-center, room for text |
| Top Shelf Wide     | 2320 × 720      | Same as above, wider crop             |
| App Store Icon     | 1024 × 1024     | All layers composited, no parallax    |

Apple's parallax tool (`Parallax Previewer`) renders the layered icon
on the actual Apple TV device for verification. **Do not skip this
step** — sprocket holes especially need to land cleanly on the
boundary.

---

## Selecting the still

The still inside the frame is **the** design decision. Criteria:

1. **Public domain**, with no attribution constraint (so we can use it
   on the App Store).
2. **High-resolution scan** — 2K minimum at the master 1024×1024
   icon size; the still is ~720px tall in the icon.
3. **Compositionally simple** — one face, one strong shape, or one
   recognizable silhouette. Busy stills become noise at icon scale.
4. **Not too obscure, not too iconic.** Don't use *Casablanca* (we'd
   look like we own it); don't use a random Prelinger industrial film
   (no one will recognize it).
5. **Black and white preferred for v1.** Reads cleaner against
   saturated color and signals archival without dating the brand.

### Candidate stills (suggestions for the curator to evaluate)

Strong contenders from confirmed-public-domain American cinema:

- *A Trip to the Moon* (Méliès, 1902) — moon-with-rocket still. Iconic
  silhouette, immediately legible.
- *Nosferatu* (Murnau, 1922) — Count Orlok's shadow on the staircase.
  Vertical composition fits the frame well.
- *The General* (Keaton, 1926) — Buster on the locomotive cowcatcher.
- *Night of the Living Dead* (Romero, 1968) — Karen at the basement
  door. Risky — recognizable as horror, may put off cozier viewers.
- *Charade* (Donen, 1963) — Hepburn's silhouette in title sequence.

**Recommendation:** Start with the Méliès moon for v1 — it's the most
recognizable image in cinema history that's safely public-domain, it
photographs beautifully, and it telegraphs "archive" without feeling
dusty.

---

## Production checklist

- [ ] Source still at ≥ 2K resolution from `archive.org/details/...`
      or LoC's National Film Registry collection
- [ ] Crop and color-correct to neutral, slight contrast boost
- [ ] Composite in Figma / Sketch using the layout grid above
- [ ] Generate all 6 tvOS icon variants via `Assets.xcassets`
- [ ] Verify in Apple's Parallax Previewer
- [ ] Generate App Store 1024×1024 (no parallax, all layers flattened)
- [ ] Verify icon at 64×64 (Top Shelf small) — sprocket holes must
      still be visible, not muddy
- [ ] File license note for the chosen still in the
      Attribution screen

---

## Why this works

- **The bold flat color** is the brand handle — it's what you'll see
  in the Apple TV launcher next to Netflix's red and Disney+'s blue.
  We borrow Netflix's "single bold field" lesson without mimicking
  their wordmark approach.
- **The film frame** does the storytelling. Photographic stills carry
  emotional weight that vector illustrations cannot.
- **The sprockets** are the smallest detail that makes the icon feel
  earned. Skipping them or simplifying them flattens the metaphor;
  exaggerating them turns it into a logo cliché. The thin black gutter
  with subtle perf highlights is the right amount of craft.

The end state: **an icon that earns a second look** even from people
who don't yet know what the app does. That second look is the
download.