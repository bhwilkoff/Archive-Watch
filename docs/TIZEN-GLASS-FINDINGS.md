# What the TV actually shows — 2026-09-10

The owner tested the side-loaded build on a QN65S90CDFXZA and reported that a
lot of it is broken. They are right, and the reason it took a person to find it
is recorded here so it does not happen again.

## The methodology failure

Everything before this was measured in a desktop Chrome window **at 1456×770,
with a mouse**, and called TV testing. Two things were wrong with that:

* This Mac's display is 1512 CSS px wide at `devicePixelRatio` 2, so a true
  1920×1080 CSS viewport **cannot be opened on it at all**. Every layout reading
  all session was taken at three-quarters of TV width.
* A mouse can reach anything. A remote reaches only what the focus engine finds,
  in the order it finds it, by pressing a direction. That is why a hero with no
  focusable child and four dead filters both passed a "check" and failed on the
  owner's television.

`tools/tv_glass.mjs` replaces it: headless Chrome has no physical display, so it
renders a real 1920×1080, and input goes through `Input.dispatchKeyEvent` — a
genuine key event, not `el.focus()` and not a synthetic click, both of which lie
about reachability. It screenshots after every press and prints where focus went
and whether it was **on screen**.

## Reproduced and FIXED

**The page did not follow the highlight on Home.** `body` is a flex column with
`overflow:hidden`, so `<main>` scrolls and the footer is a sibling pinned below
it, permanently visible. Geometrically the footer is therefore the nearest thing
below *every* row, so Down from the category tiles jumped to "About &
attribution" and the page never scrolled. Not a Home bug — what a pinned element
does to a spatial engine on any surface. A move now prefers a target in the same
scroll container and only leaves it when that direction is genuinely exhausted.

Measured before: Down → footer at step 4, one press off screen. After: twelve
presses walk shelf to shelf, `scrollTop` 0 → 4182, focus held at a steady y=616,
every element visible.

## Reproduced and NOT fixed — the player needs rebuilding, not patching

Captured at 1920×1080 (`/tmp/aw-player2/05-Enter.png`):

* **`<video controls>` renders the BROWSER's control bar** — pause, `0:00`,
  volume, fullscreen, a ⋮ menu. That is the owner's "controls that only work for
  a desktop web browser", and it is literally true: those are Chrome's widgets.
  A TV needs its own transport, driven by the D-pad.
* **The player is a `<dialog>` with desktop chrome** — a title bar carrying a
  PiP button, "Cast" and an ✕. None of those belong on a television.
* **The synopsis is painted permanently over the top quarter of the picture.**
* **The video frame is not sized to the screen.**
* Pressing OK on Play focused the **PiP button**.

## Reproduced and NOT fixed — Detail

* **Down from the nav lands on Share, not Play.** The primary action must be
  where the remote arrives, not wherever geometry puts it.
* **The synopsis runs off the right edge** at 1920 — no max width.
* Poster, cast chips and body text are desktop-sized at ten feet.

## Cannot be investigated from here

**"Videos play for a few seconds and stop."** This is Tizen-specific: playback
is fine in Chrome. Retail Samsung TVs close `sdb shell` entirely — no console,
no screenshot, no dlog (see `docs/tizen-signing.md`) — so there is no way to
observe the failure on the device. Options, in order of cost: an on-screen debug
overlay built into the app itself (the shape `FunctionalAudit.swift` uses on
tvOS); a developer/UD unit, which does expose the Web Inspector; or Samsung's
own remote-test service.

## The conclusion the owner already reached

This is a web page shown on a television, not a television interface. The web
app was the right way to REACH the platform and is the wrong thing to ship
unchanged. What is needed is a TV-first pass over the player and the Detail
surface, not more patches to a browser layout.
