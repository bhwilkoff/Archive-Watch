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
5. ✅ (v1.42.786) Channels grid slivers (§B8a); Search leads with Films & Shows, episodes at five with Show All; Help ▸ real destinations.

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
- v1.42.787: Export — Cancel (⌘.) while it runs (the half-written file is
  removed), failures say in words which step failed ("A clip could not be
  downloaded from archive.org.") with the domain/code chain kept for the
  diagnostics log, Try Again repeats the last export, Dismiss clears a finished
  or failed bar (the Exported bar used to stay forever). Supercut — the clear
  button, the include checkmarks and the ‹ › take chevrons have help tags and
  VoiceOver labels; the Color/Type/Decade pickers and the clip browser's source
  picker have real labels (empty `Picker("")` announced nothing). Built, not
  driven: an export needs the Save panel (a click) and archive.org is still
  refusing this network.
- v1.42.788: Publish — the missing-keys refusal has "Open Settings…" beside it
  (it named Settings and gave no way there), a failure offers Try Again (back to
  the form, title kept) beside Close, Esc cancels the form. The Creation Studio
  landing no longer binds ⌘N/⌘O a second time (File owns them), its buttons sit
  centered under the centered title, and its copy says what it does ("Cut
  public-domain films into clips, montages and supercuts, then export them.";
  "No recent projects yet."). Library, Watch Together and Settings seen clean.

- v1.42.789: the timeline speaks. It is CALayers in one NSView, so VoiceOver
  heard "timeline" and nothing inside it. Now it is a group whose value is the
  playhead ("Playhead at 4 s of 15 s") and whose children are every clip
  ("Clip 1 of 2, Dick Tracy Movie Serial Chapter 6, 8 s"), title and music
  block, each framed where it is drawn; pressing one selects it. Measured
  through the AX API on the running editor: the dump lists both clips with
  the right selection, and an AXPress on clip 1 moved the selection to it.
- v1.42.790: the mark-in/out sheet gave up on nothing. With archive.org
  refusing this network it read "Loading the film…" for over two minutes,
  because `asset.load(.duration)` never returned and the 60 s give-up waited
  behind it. The length now loads beside the poll; after the give-up the sheet
  says "This film's frames could not be loaded — archive.org did not answer",
  the frame strip stops spinning, and Add to Timeline is disabled (the clip
  would only fail again in the editor). Seen on the Mac with archive.org
  unreachable. And J/L shuttle as in Final Cut: J plays backward (it had
  only paused), L forward, the same key again doubles to 8×; a preview that
  cannot reverse pauses as before. Built; not driven (needs a loaded film).
- v1.42.791: Settings. Captions that explained a control's own behavior are
  cut to the fact a viewer could not discover: Autoplay's footer is now only
  "TV episodes always continue to the next."; empty Downloads reads "Nothing
  downloaded yet."; Publishing says "Your keys stay in this Mac's Keychain."
  and "Get Your Keys on archive.org" (the link printed its own path). The
  OpenSubtitles field's title wrapped to two lines beside a Mac field; the
  "not your email" warning now rides in the empty field as its prompt (iOS
  unchanged, where the title IS the placeholder). The window titling itself
  after the selected tab is the system's Settings behavior and stays.
  Note: screenshots of Publishing show the owner's access key, and the
  username field raises Passwords autofill with their email; capture neither.
- v1.42.793: the whole menu bar dumped through AX and read top to bottom.
  Go now lists the sidebar in the sidebar's order (Surprise and Search in
  place; ⌘1–⌘8 unchanged), and "Surprise Me" beside "Surprise" read as one
  item twice — it PLAYS a random film, so it is "Play a Surprise Film"
  (⇧⌘R). View had two separators in a row (the editor group added its own).
  The Surprise page's title said "Surprise Me" under a sidebar saying
  "Surprise", over a sentence explaining itself; it is "Surprise" and the
  sentence is gone. Verified: Go's items read back in sidebar order, Go ›
  Surprise opens the page, View has one separator.
- v1.42.794: every poster card on the Mac (Home, Library, Browse, Search,
  Collections) opened on `onTapGesture`, which VoiceOver cannot see: the card
  read as loose text with nothing to press. It is now one button, "The
  General, 1926", whose press opens the page. Verified through AX on the
  running app: Library's cards list as AXButton with AXPress, and pressing
  "The General, 1926" put the window on The General.
  Also seen with archive.org briefly up: the mark-in/out sheet loaded a
  1:11:33 film (length, Play and Add live) while the frame strip came back
  empty — the metadata call lost the race to archive.org going away again.
- v1.42.795: the other tap-gesture-only controls. Home's hero dots were
  Capsules with `onTapGesture`: now buttons named for their film, valued
  "3 of 7", selected when showing. The Creation Studio's saved-clip rows
  selected on a tap gesture VoiceOver could not see; each is now one
  button — the film, then its line and length ("Welcome to the 2017 ASCAN
  class., 5.7 seconds") — whose press selects and whose named action is
  "Add to Timeline" (the ＋ is labeled too). Verified through AX: the dots
  list 1–7 with the showing one selected and a press on 3 moved the hero;
  the rows list as AXButton with AXPress plus "Add to Timeline", and a
  press selected the NASA row.
- v1.42.796: the Creation Studio's toolbar is a customizable one
  (`.toolbar(id:)`, an id per item) and the app declares `ToolbarCommands()`.
  It had been nine unlabeled icons with no way to see their names but a
  hover, and View had neither Show/Hide Toolbar nor Customize Toolbar…. Now
  View carries both, and the palette opens with every item named and a
  Show: Icon Only / Icon and Text choice — so a person who wants words gets
  them the native way. Seen: View's items read back through AX, and the
  palette photographed over the editor.
- v1.42.797: the inspector's slider rows (clip Audio / Fade in / Fade out /
  Transition, audio Volume / fades, text X / Y / Size). Each carried an icon
  repeating its label, which left a ~50 pt slider stub in the 280 pt
  inspector. The icon is gone, sliders take at least 90 pt (110 wrapped
  "Fade out" under its label), and each slider speaks its name and value
  ("Fade in, 1.5s") — they had announced nothing but a percentage. Text Size
  is a labeled row like the others. Seen in the inspector on the Mac.
- v1.42.798: Watch Together Studio, Output column. Idle, it listed nine
  engine rows of zeros ("0.0 ms per frame · 0 fps", "Encoder not started",
  "Dropped 0 frames", "Sent 0 B"…) under a Studio that had nothing running.
  They appear once there is an engine (preview or live), divider and all;
  idle, Output is the state, the three settings and the rights warning.
  The Mixer's "8.0" is the owner's chosen fader scale and stays. Seen in the
  Studio window (camera not started, nothing captured).
