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

2.2a **A scope selector is capped at 560 pt** at regular width, leading-aligned
— the segmented pickers that switch Browse between Films/TV/Collections and
Library between Favorites/History/Playlists/Clips. Stretched across 1046 pt
they give a one-word label a 260 pt segment, which is the same
claim-about-importance error as §2.2 in a quieter register. On compact they
stay full width, where that is exactly right.

2.3 **The cap is on the CONTENT, not the screen.** Width-capped content sits in
a leading-aligned column inside the available width; the surrounding space is
deliberate, not an error to be filled. Where a surface has a natural second
column (§3), that space is used instead.

---

## §3 — Detail at regular width (binding)

3.1 **Detail is two columns on regular width:** artwork in a leading column,
identity, actions and the synopsis in a trailing column beside it (§3.1a). On compact width it stays the single stacked column
iOS-DESIGN.md already describes. Both come from one view; there is no second
Detail implementation.

3.1a **Prose shares an edge with the controls around it** (owner, 2026-09-28:
*"Is there a reason why the summary/description text … doesn't take up the same
space as every other interface element?"* — answered "align to a column"). In
the two-column layout the synopsis sits in the trailing column under Play and
the action row, at that column's width (360–520 pt, inside the §2.1 measure),
and the facts follow it. The series page takes the same arrangement: artwork
leading at its own 16:9, title, Play, Favorite and overview beside it, and the
episode list below ends at the identity column's right edge (1008 pt). The
stacked fallback keeps prose at the §2.1 cap.

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

## §5a — Sheets: detents do not apply on iPad, and `presentationSizing` is not a fix for a short one (binding)

A `.sheet` on iPad is a **centred form sheet**, and `presentationDetents` does
not apply to it — the detents that shape a phone sheet are IGNORED here. A sheet
therefore gets the form sheet's size whatever its content, and a SHORT state
leaves the remainder empty.

Measured on an iPad Pro 12.9-inch (5th gen), 2026-09-17, on Watch Together's
go-live sheet (`GoLiveSheet_iOS`, `.presentationDetents([.large])`):

- **Refusal state** (a film with no rights verdict): renders correctly and
  legibly, gives the reason, Go Live correctly disabled — and leaves roughly the
  **bottom 40% of the sheet blank**.
- **KEEP state** (*La Passion de Jeanne d'Arc*, 1928, `safe_pd_age`): the same
  sheet **fills its height properly** — rights line, "Where it goes", platform
  picker, the not-configured sign-in explanation, generated title, privacy. All
  of Decision 128's four state defects are absent at this width: "YouTube" is
  spelled correctly, the wrench reads as an icon rather than a button, the
  footer agrees with the row above it, and **Go Live is greyed out**.

**So the fault is confined to short states, and it is cosmetic.** That matters,
because the obvious fixes are functional regressions — both were tried on the
device:

- `.presentationSizing(.fitted)` collapsed the sheet to about **140 pt wide**;
  "What you are streaming" wrapped to one character per line. This content has
  no intrinsic width, so fitting both axes destroys it.
- `.presentationSizing(.form.fitted(horizontal: false, vertical: true))` kept
  the right width and **clipped the content to a strip**, cutting the film row
  off mid-row.

**The rule.** Do not reach for a sizing modifier, a fixed frame or a spacer on
an iPad sheet. An empty region below short content is acceptable; the three
alternatives above are worse, and two of them are measured regressions. If a
sheet's short state ever needs to look deliberate rather than empty, that is a
CONTENT decision for that state — §2's measure rule applied to a sheet — not a
presentation modifier.

**Recorded as not yet seen**: §3.4a's rights warning sits below the fold in the
KEEP state and has not been read at iPad width; the sheet scrolls, so it is
present, but it has not been looked at.

## §5b — Controls FOR something on screen are an inspector, not a sheet (binding)

*Added 2026-09-23 from the Watch Together launch audit: "iPad controls sheet
covers the program".* §5a's form sheet is centred over the whole screen, which
is right for a task that replaces what is behind it (going live, getting
subtitles) and wrong for controls that ADJUST what is behind it. The Studio's
controls — layout, the two faders, cards, the audience — change the program
the host is watching; a form sheet hides the very picture each change is meant
to be judged on.

**Rule:** a panel whose job is to adjust something still on screen is presented
with `.inspector(isPresented:)`. At regular width that is a trailing column
beside the content, which stays visible and live; at compact width SwiftUI
presents the same content as a sheet, so the iPhone is unchanged. One modifier,
no size-class branch. Applies first to `StudioPlayerContainer_iOS`'s controls.
SEEN at iPad width 2026-09-24 (iPad Pro 12.9, a bench show on air): the first
run found the film laid UNDER the column — the player ignored every safe-area
edge, and the inspector reports its column as a trailing inset — so the player
now keeps the trailing edge while the controls are open, and the column is
320–440 pt (at the default ~270 pt a chat line wrapped a word a line).

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

---

## §8 — The menu bar and the keyboard (binding)

Owner, 2026-09-28: *"a native-first iPad-centric version that works well for
that platform."* On iPadOS 26 the menu bar is a native surface (WWDC25 "Elevate
the design of your iPad app", session 208; "What's new in SwiftUI", 256): the
same `.commands` that build the Mac's menu bar build the iPad's, and a person
with a keyboard expects to find every command there with its key.

8.1 **The iPad shows the Mac's menus, in the Mac's words.** Go (the
sidebar places (Home ⌘1, Films ⌘2, TV ⌘3, Channels ⌘4, Search ⌘5, Favorites ⌘6), Search ⌘F, Back ⌘[, Surprise Me ⇧⌘R, which opens
Surprise as the Home button does), Film
(the film in front: Play ⌘P, Add to / Remove from Favorites ⌘D, Add to
Playlist…, Mark as Watched ⇧⌘U, Open in New Window, Copy Link ⇧⌘C, View on
archive.org, Something Wrong with This Film?), Help (Archive Watch Help ⌘?,
How Titles Are Vetted, Privacy Policy, Terms of Use; the Mac's Feeds &
Integrations link is left off, the side-doors rule in CLAUDE.md). Names match `macOS/MenuCommands_macOS.swift` so a person who uses
both reads one vocabulary.

8.2 **A command for a film is published by the film's page, per window**
(`focusedSceneValue`). With no film in front it is dimmed, never hidden (HIG,
menus: "keep items visible and disable them").

8.3 **The player's keys belong to the player.** `AVPlayerViewController`
already answers Space and the arrow keys on iPad; the app adds no Controls menu
that would compete with it. (The Mac has one because its player is our own
HUD.)

## §9 — Windows (binding)

9.1 **A film can open in its own window** (iPadOS 26 windows are freely
resizable, and Slide Over returned in 26.1): Open in New Window in Detail's
More menu and in the Film menu, offered only where
`supportsMultipleWindows` is true — never on iPhone. The window shows that
film's Detail with its own navigation, and its title is the film's title.

9.2 **Every window owns its navigation.** The `Router` is per scene, never an
app-level singleton: two windows sharing one would move each other's tabs and
stacks. The catalog store, account and SwiftData container stay app-wide.

9.3 **Scenes are declared for iPad only** (`UIApplicationSceneManifest~ipad`
in the shared Info.plist), so tvOS and iPhone read no change.

## §10 — The sidebar holds places, not only verbs (binding)

The owner, 2026-09-28: *"a native-first iPad-centric version that works well
for that platform."* On iPadOS the sidebar is where the Apple TV and Music apps
put every place a person goes; the phone's five-tab bar is a compact rendering
of the SAME `TabView(.sidebarAdaptable)`, not the design to copy.

10.1 **The sidebar lists places; the tab bar keeps the phone's five.** Sidebar
entries that the tab bar should not show carry `.defaultVisibility(.hidden,
for: .tabBar)`; a phone-only root that the sidebar replaces with its places
carries `.defaultVisibility(.hidden, for: .sidebar)`. The iPhone's bar is
unchanged: Home, Browse, Channels, Search, Library.

10.2 **The sidebar's sections**: Home · Browse (Films, TV, Collections — iOS-DESIGN
§4.2a's scopes, each opening that scope with no segmented control above it) ·
Channels · Search · Library (Downloads, Favorites, History, Playlists, Clips —
§2.7's places, each opening that place) · Surprise · Watch Together.
Surprise opens the Surprise page, where Cartoons, Party Play and the cover-art
wall live (tvOS-DESIGN §2.2a — the same rule on every Apple platform, not
sidebar entries). Watch Together opens a landing that states what this device
can do (Decision 131) and joins a room. **Settings is not a sidebar place**:
the sidebar draws loose entries above its sections, so it could only sit mid-list,
and the Apple TV and Music apps keep settings out of the sidebar. It is the app
menu's Settings… (⌘,, §8) and Home's gear, one sheet. The iPhone keeps its Home
toolbar buttons for Surprise and Settings; the iPad drops the Surprise button,
which the sidebar lists.

10.3 **The sidebar is customizable** (`TabViewCustomization`, persisted): a
person may hide or reorder entries; the five tab-bar tabs cannot be hidden.

## §11 — The pointer (binding)

11.1 **Everything tappable answers the pointer.** Poster tiles lift
(`.hoverEffect(.lift)`), guide blocks highlight, and a block too narrow for
words names itself on hover (`.help`). `hoverEffect` is inert on touch, so the
iPhone is unchanged.

## §12 — Drag and drop (binding)

12.1 **A film can be picked up.** Poster tiles are `.draggable` at regular
width; the payload is the film's archivewatch.org link (`FilmTransfer`), so a
film dropped into Notes or Mail arrives as a link a person can open.

12.2 **Where a film can be put down**: a playlist row adds it to that playlist;
the Favorites sidebar entry favorites it. A dropped archive.org or
archivewatch.org link to a film we keep counts the same as a dragged tile; any
other drop is refused, never guessed.

## Verified (2026-08-28)

Measured on the owner's iPad Pro 12.9 (iPadOS 27, wireless) and asserted by
`ArchiveWatchUITests/IPadAuditUITests` — **8 passed, 0 failed, 0 skipped** on
the REAL DEVICE:

| Rule | Before | After |
|---|---|---|
| §2.1 prose cap | 115 chars / ~1030 pt | **700 pt**, landscape *and* portrait |
| §2.2 primary action | ~1040 pt | **520 pt** of 1376 (38% of the window) |
| §2.2a scope selector | 1046 pt | **560 pt**, leading-aligned |
| §3.1 two columns | stacked | artwork + identity side by side |
| §4.1 grid columns | — | **8 tiles** per Browse row |
| §7.4 compact unchanged | — | iPhone 12 suite **25/25** after the change |

§3.1 is proven by GEOMETRY rather than by finding the artwork. Looking for the
image made this check skip on the very device it was written for: a SwiftUI
`AsyncImage` with no accessibility label is not exposed as an image element.
The title's own position carries the same proof and cannot go missing —
stacked it starts at the leading margin, beside a leading column it starts far
to the right. Measured: **x=784 of 1366pt**.

**Reviews were the prose the synopsis cap missed.** Capping the synopsis left
archive.org review text running **976 pt**, because reviews live in the
community section rather than the synopsis block. §2.1 says *prose*, not
*synopsis* — a viewer review is prose. Found only because the harness measures
the widest text on screen rather than the one it expected to be widest.

### Harness note — automation is authorized (2026-08-28)

XCUITest on the physical iPad first failed with *"Timed out while enabling
automation mode"*. The cause was visible only on the device itself: iPadOS 27
puts up **"Enter iPad Passcode for XCTest — Enable UI Automation"**, and the
run sits waiting for a passcode nobody is typing. Once the owner entered it,
the whole suite ran on the real hardware. The simulator remains useful as a
second rig (it rotates freely and needs no authorization), and
`tools/ios_scenario.py` still verifies by screenshot + OCR with no permission
at all.

### Harness trap, recorded so it is not re-learned

`app.staticTexts.element(boundBy: i)` **inside a loop re-queries the entire
accessibility tree per element.** On a Detail screen carrying cast, community
and related rows that is slow enough to blow the test timeout and take the
runner down with it — tests 01 and 02 died exactly that way. Use
`allElementsBoundByIndex` and take ONE snapshot.
