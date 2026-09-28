# iPad design loop (2026-09-28)

Owner, starting the loop: *"The last apple-based platform that needs a full
audit and design polish is the iPad. Please proceed with all updates that are
necessary for full functionality/parity with the other apple platforms and a
native-first iPad-centric version that works well for that platform."*
Test device: the owner's iPad Pro 12.9 (5th gen, iPadOS 27), landscape.
Binding rules: `docs/IPAD-DESIGN.md` (extends `docs/iOS-DESIGN.md`).

## First sweep (Home, Browse, Channels, Search, Library, Detail)

Already right and not to be "fixed": the sidebar shell, the width-capped hero,
Browse's 8 poster columns with visible filter chips, Detail's two columns
(art beside identity) with labeled actions and a 700pt synopsis, Library as a
list of places.

## Research (session scratchpad `ipad-research.md`, sources there)

iPadOS 26/27 expect what this build has none of: a **menu bar** (the same
`.commands` the Mac target already has builds it on iPad; WWDC25 208/256),
**windows** (`UIApplicationSupportsMultipleScenes` + `WindowGroup(for:)` +
`openWindow`), **keyboard shortcuts**, **pointer hover**, **drag and drop**
(`Transferable`), and sidebar-only **`TabSection`** children. Each needs a
rule in IPAD-DESIGN.md before it ships (binding-design-doc discipline).

## Done

- v1.42.867: **Channels guide** (iOS, seen on the iPad): a block under 84pt
  draws no title ("Moo / nbird", "Lun / ch…" broke mid-word between 44 and
  84pt) and names itself to a pointer (`.help`); the ruler marks the clock's
  own :00/:30 (it labeled window start + 30 min: "12:31, 1:01") and none in
  the last quarter hour (a "3:0…" was cut at the edge; tvOS given the same
  guard). **Search's** empty state drops its explanation line.

## Found, data (for the copyright/scrub work, not the iPad)

- `SelfCons1951` "Self-Conscious Guy" (Coronet, 10 min) leads Home's hero with
  a TMDb backdrop (tmdb 444546) that looks like a modern color film still.
- Browse shows Yojimbo (1961), The Pink Panther, Gentlemen Prefer Blondes; the
  Classic TV channel carries Monty Python's Flying Circus and Rumpole of the
  Bailey (1978-); the Documentary channel carries Triumph des Willens (the
  Decision 149 flag removes it from channels at the next publish).

## Queue

1. Menu bar + keyboard shortcuts (shared with the Mac's MenuCommands where possible)
2. Multiple windows: "Open in New Window" for a film
3. Sidebar `TabSection`s: Library places and Browse scopes in the sidebar
4. Pointer hover on cards; drag and drop of films into playlists
5. Parity table from the code audit (pending)
