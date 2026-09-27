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
5. ✅ **The rest, swept on the iPhone 12** (v1.42.773): Home, Search, TV, Collections, Surprise fit 390pt cleanly. Fixed: Detail's meta line said "Tv Episode" (every raw type code now goes through `ContentType.label`, all four call sites); a series overview over 240 characters opens at four lines with More, so its episodes are on the first screen; Settings loses the captions that explained a control or justified a choice (owner's essential-information rule), keeping the mature-collections warning, "TV episodes always continue", the privacy line and the TMDb credit.
6. ✅ **Accessibility text sizes** (v1.42.774, iOS-DESIGN §3.5c): On Now, Detail and Library checked at accessibility2 on the iPhone 12 and fixed where they broke.
7. ✅ The shared Subtitles and Automatic Captions settings sections (also on tvOS/macOS) still carry an instruction row ("Open a film, then choose Subtitles.") and a long explanatory footer — a cross-platform copy pass, not an iPhone one. Done v1.42.774: the instruction row is gone, and both footers say only what a viewer cannot see (data, privacy, that a machine can be wrong).
8. ✅ **Channel surfing in the player** (v1.42.775, iOS-DESIGN §2.5d): ▲/▼ over the video, on tune-in and on a tap.
9. ✅ **In-app picture-in-picture** (v1.42.776, iOS-DESIGN §4.4a; seen playing over the app on the iPhone 12; restore not yet tapped) — owner, 2026-09-27: *"You can also make in-app picture-in-picture work well to allow for playing a movie while browsing for another movie to watch or add to playlists."* Today PiP starts but the full-screen player stays over the app, so there is nothing to browse. The AVKit pattern: the player screen steps aside when PiP starts (the AVPlayerViewController and its player are kept alive, not dismantled), and tapping the PiP window's restore button re-presents it.
10. ✅ **Search and the day schedule** (v1.42.777): Search leads with Films & Shows, episodes after at five with Show all, one filter row (iOS-DESIGN §4.2b); a channel's day opens on what is on now (§2.5c). Seen on the iPhone 12 ("keaton"; Cartoon Classics on "7 short films · On now").
11. ✅ **Collections, categories, long titles** (v1.42.779, iOS-DESIGN §4.5a): titles from data wrap in the page instead of truncating in the bar. Seen: "Japanese Jidaigeki (Period Dramas)", "Fantômas: In the Shadow of the Guillotine".
12. **Noted, not changed (archive.org's own data)**: the Film Noir collection holds The Grapes of Wrath and Sabrina because archive.org's Film_Noir collection does; its membership is archive.org's categorization, used as-is under the owner's rule.

