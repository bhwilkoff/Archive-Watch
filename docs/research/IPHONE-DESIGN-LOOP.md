# iPhone design loop (2026-09-27)

Owner, starting the loop: *"I'd like you to do a design iteration on every
surface of the iPhone app. There are many that struggle on a smaller screen
size. I'd like to figure out if there are better design patterns for Browse and
Library (many different tabs with different, sometimes competing, purposes). I'd
also love to figure out better ways to display the channels interface to allow
understanding of each item on smaller screens and allowing users to navigate
easily around the channels). Further research for the best ways to display
detailed information without overwhelming the user is likely warranted."*
Test device: **the iPhone 12** (390pt, notch) — owner: "Use the iPhone 12 as the
testing device for rapid iteration." Sweep: `tools/ios_scenario.py`.

## What the research says (sources in the session record)

- **Tabs** are navigation only; don't duplicate a job across tabs (WWDC22
  "Explore navigation design"). Segmented controls: about five segments at
  most on iPhone, noun labels. Sort belongs in a pull-down menu.
- **Library as a list of places** (Apple Music, the Apple TV app): rows that
  each open one place, with the most-used on top. Netflix folded Downloads, My
  List, history into one personal tab (2023).
- **Browse**: a grid with the active facets VISIBLE (chips) and a Sort pull-down;
  Criterion's All Films is one list with facets.
- **Phone TV guides**: Samsung TV Plus defaults to a now list and makes the grid
  opt-in; YouTube TV's 2026 phone guide keeps names readable and a "jump to
  live"; Pluto's 2026 redesign lost channel surfing and next-up info and its
  rating fell from 3.15 to 2.32.
- **Detail**: one primary action; a handful of labeled secondary actions; the
  rest in a More menu of three or more items (HIG pull-down buttons); disclosure
  for what is not needed first; sheets with detents for pickers.

## Findings on the iPhone 12 (first sweep, 12:58-1:00 PM)

| Surface | Problem |
|---|---|
| Channels | 2.5pt/min grid: 5-min programs as 20pt slivers with titles broken into single letters; 9pt rail and time type |
| Browse | every filter and the sort hide behind one unlabeled icon; nothing on screen says what is filtered |
| Library | five competing segments (Offline, Favorites, History, Playlists, Clips); opens on an empty Favorites |
| Detail | eight or nine unlabeled icon buttons in a row that runs off the screen |

## Queue

1. ✅ **Channels** — On Now list + Guide grid (iOS-DESIGN §2.5c), v1.42.769, seen on the iPhone 12.
2. ✅ **Library** (v1.42.770, iOS-DESIGN §2.7, seen on the iPhone 12) — a list of places: Downloads, Favorites, Playlists, History, Clips, each a row with its count and an icon, opening one place; Join a Room stays a toolbar button. Empty places say what fills them.
3. ✅ **Browse** (v1.42.771, iOS-DESIGN §4.2a, seen on the iPhone 12 plain and filtered) — Films / TV / Collections stays (three segments); the filters become a visible chip row (Type, Decade, Length, Sort), each chip a menu showing its value; a Clear chip when any is set.
4. ✅ **Detail** (v1.42.772, iOS-DESIGN §3.5b, seen on the iPhone 12: The General, His Girl Friday) — Play; three labeled buttons (Favorite, Watch Together, Share); everything else in a More menu; synopsis clamped with More; the facts in a disclosure.
5. **Home, Search, Settings, Surprise, Series detail, Collections** — sweep each for the same faults.
