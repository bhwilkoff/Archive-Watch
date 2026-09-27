# macOS design loop (2026-09-27)

Owner: *"can you conduct a similar audit and design iteration loop on the MacOS
version, investigating every surface and interface element. Please pay close
attention to every single feature within the Creation Studio, which may need
significant polish. Additionally, make sure that all features that should have
menu items (macOS specific need), that they are well represented in the menu
structure."* Owner, same day: *"You can quit the running copy as much as you
want. I'm not at my computer."*

Method: the Debug build launched with the DEBUG doors (`AW_START_TAB`,
`AW_START_ITEM`, `AW_CS_TEST=editor|markclip`, the `AW_STUDIO_*` family);
window-only screenshots (`screencapture -l<CGWindowID>`); the menu bar read
through Accessibility and its items pressed there (never pointer clicks).

## Findings (first pass)

- Menu bar: only New Project, Surprise Me and Broadcast were custom. No Go, no
  Film, no Controls; the Creation Studio has NO menu items — split, markers,
  zoom, export, add text/music, supercut exist as toolbar buttons or as bare keys
  that work only while the timeline is first responder.
- "Theatre row" (Broadcast ▸ Placement) broke the US English rule; the test's
  word list lacked "theatre".
- Mark as Watched does not exist on the Mac. `SpeedMenu` is written and unused.
- Channels grid draws short programs as letter slivers ("1: 0…"), as the iPhone
  did before §2.5c.
- Search leads with Episodes, as the iPhone did before §4.2b.
- Help ▸ Archive Watch Help leads nowhere.
- Creation Studio (from the code map): three fixed panes rather than
  `.inspector`; bare `B` for split where §7c says ⌘B; J does not play backward;
  zoom and play buttons without help tags; MarkClipView at hard-coded 720×405 /
  720×700; Supercut icon-only buttons and empty Picker labels; Export failure
  has no Retry; timeline has no accessibility.

## Queue

1. ✅ Go and Film menus (macOS-DESIGN §B14), v1.42.781.
2. ✅ (v1.42.782) Controls menu for the player: Play/Pause, skip ±10 s, next/previous episode,
   subtitles, speed (use `SpeedMenu`'s choices), Picture in Picture, full screen;
   Mark as Watched on the Mac (Film menu + Detail).
3. ✅ (v1.42.783) Creation Studio menus: Clip (Split ⌘B, Add Clip… ⌘I, Add Text, Add Music,
   Record Voiceover, Supercut…, Duplicate, Delete, Mute Audio, Clear Fades),
   Mark (Add Marker, Previous/Next Marker, Previous/Next Edit, Go to Start/End),
   View (Zoom In/Out/Fit, Show Inspector ⌥⌘I), File ▸ Export… ⌘E, Publish…
4. Creation Studio polish, surface by surface. ✅ v1.42.784: every toolbar
   button and the transport's play/zoom have help tags (with their keys) and
   VoiceOver labels; Supercut's icon is quote.bubble; Aspect presets are short
   ("16:9 Landscape") so the inspector never truncates them; selection and
   the multi-selection set stay in step (Delete and Duplicate agree); Clip ▸
   Deselect All ⇧⌘A; the inspector's two explanatory captions cut to facts.
   Seen before the fix: nine icon-only
   toolbar buttons (Supercut's `text.magnifyingglass` reads as Search); the
   inspector's "Landscape · 16:…" truncates; Delete is disabled while
   Duplicate is enabled for the same selection (selectedIDs vs selection).
5. Channels grid slivers; Search order; Help menu destination.

## Log
- v1.42.785: the mark-in/out sheet names its film (title and year) — it named
  it nowhere but the clip name's placeholder; a frame strip that comes back
  empty moves to "Loading the film…" and, if the film cannot load either, to
  "This film's frames could not be loaded" rather than spinning forever; the
  play button and Set In / Set Out have help tags; `AW_CS_TEST=browser` opens
  the Add-a-Clip browser for the sweep.
- 2026-09-27 14:30 MT: archive.org REFUSES connections from this network
  (`connect to 207.241.224.2 port 443 … Connection refused`; archivewatch.org
  and apple.com answer). Known behavior: archive.org blocks an address after a
  burst (memory creation_studio_connection_discipline). The loop stopped
  launching anything that fetches films until it lifts.

