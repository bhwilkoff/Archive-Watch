# Xcode Project Setup — Step by Step

One-time setup. ~15 minutes. Two steps are where people stumble; they're
flagged as ⚠️ below.

Do not deviate from naming — every place that says `ArchiveWatch` needs
to say exactly that (no spaces, no dashes). Xcode Cloud, bundle IDs, and
the file references throughout our scaffold all assume this name.

---

## 0. Prerequisites

- Xcode 15 or newer, with tvOS SDK
- Apple Developer account (free tier is fine for Simulator; paid tier needed for real hardware / TestFlight)
- A TMDb v4 "API Read Access Token" — get one at
  [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api)
  (free, non-commercial, no approval needed for most purposes)

---

## 1. Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Select the **tvOS** tab → **App** → Next
3. Fill in:
   - **Product Name**: `ArchiveWatch` *(exactly; no space, no dash)*
   - **Team**: your team, or None for now
   - **Organization Identifier**: `com.bhwilkoff`
     → bundle ID becomes `com.bhwilkoff.ArchiveWatch`
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Storage**: `None` *(we configure SwiftData ourselves via `ContentItem`)*
   - **Include Tests**: your call
4. Next. When the file picker appears:
   - **Navigate to the `Archive-Watch` repo root** (the folder that
     already contains `CLAUDE.md`, `SCRATCHPAD.md`, `ios/`, etc.)
   - ⚠️ **Uncheck "Create Git repository on my Mac"** — we already have one.
5. Click **Create**.

After Xcode finishes, the root directory should contain:

```
Archive-Watch/
├── ArchiveWatch.xcodeproj/      ← NEW
├── ArchiveWatch/                ← NEW (Xcode's starter folder)
│   ├── ArchiveWatchApp.swift    ← auto-generated @main
│   ├── ContentView.swift        ← auto-generated placeholder
│   ├── Assets.xcassets/
│   └── (maybe Info.plist)
├── ios/                         ← our scaffold (we'll move files out)
├── AppVersion.xcconfig
├── catalog.json
├── collections.json? No — it's under docs/taxonomy/
├── featured.json
└── … (all the existing files)
```

## 2. Set deployment target to tvOS 17

1. Click the project (the blue icon at the top of the navigator).
2. Select the **ArchiveWatch** target in the right pane.
3. **General** tab → **Minimum Deployments** → tvOS **17.0**.
4. Under **PROJECT** (not TARGETS), **Info** tab → scroll to **Deployment Target** and set tvOS 17.0 there too.

---

## 3. Relocate our Swift files into the new project folder

Move the scaffold we built into the `ArchiveWatch/` group Xcode created.

### In Finder (not Xcode yet):

1. Open the `ios/` folder and the `ArchiveWatch/` folder side by side.
2. Move everything from `ios/` into `ArchiveWatch/`:
   - `App/` → `ArchiveWatch/App/`
   - `Models/` → `ArchiveWatch/Models/`
   - `Networking/` → `ArchiveWatch/Networking/`
   - `Services/` → `ArchiveWatch/Services/`
   - `Store/` → `ArchiveWatch/Store/`
   - `ContentView.swift` → **overwrites** the Xcode-generated `ContentView.swift` (that's fine; delete the Xcode one first, or just allow the overwrite)
3. Merge `ios/Assets.xcassets/` with `ArchiveWatch/Assets.xcassets/`. Contents of both are just app-icon + accent-color stubs; keep whichever is newer or merge contents.
4. Delete the now-empty `ios/` directory.

### Delete the duplicated entry point:

Our scaffold has `App/AppNameApp.swift` with `struct AppNameApp: App`.
Xcode generated its own `ArchiveWatchApp.swift`. **Keep ours, rename it,
delete the generated one:**

1. Delete `ArchiveWatch/ArchiveWatchApp.swift` (the Xcode-generated one).
2. Rename `ArchiveWatch/App/AppNameApp.swift` → `ArchiveWatch/App/ArchiveWatchApp.swift`.
3. Open that file and rename `struct AppNameApp: App` → `struct ArchiveWatchApp: App`.

### Register everything with Xcode:

1. In Xcode, right-click the **ArchiveWatch** group → **Add Files to "ArchiveWatch"…**
2. Select the `App`, `Models`, `Networking`, `Services`, `Store` folders.
3. Options:
   - **Copy items if needed**: UNCHECKED *(they're already inside ArchiveWatch/)*
   - **Create groups**: CHECKED
   - **Add to targets**: ArchiveWatch ✓
4. Click Add.

After this, Xcode's navigator should mirror the filesystem. The Swift
files should compile — try **Cmd+B** now. If you see errors, read the
section at the bottom.

---

## 4. Add the JSON resources to the bundle ⚠️

`catalog.json`, `featured.json`, and `collections.json` need to be in
the app bundle so Swift can read them via `Bundle.main`.

The first two live at the repo root; `collections.json` lives under
`docs/taxonomy/`. We add all three as **file references** (not copies)
so editing them in one place updates the app.

1. In Xcode, right-click the **ArchiveWatch** group → **Add Files…**
2. Navigate up one level (out of `ArchiveWatch/`) to the repo root.
3. Shift-select:
   - `catalog.json`
   - `featured.json`
4. Navigate into `docs/taxonomy/` and Cmd-click `collections.json` to
   add it to the selection (you'll need to do this as a second
   invocation if Xcode's picker doesn't allow cross-folder multi-select).
5. Options:
   - **Copy items if needed**: UNCHECKED *(critical — we want references)*
   - **Create folder references**: UNCHECKED
   - **Add to targets**: ArchiveWatch ✓
6. Click Add.

After this, the `ArchiveWatch` group in Xcode shows blue-ish (reference)
file names. Build the project — `catalog.json`, `featured.json`, and
`collections.json` should now appear in `ArchiveWatch.app/` when you
peek inside the build product.

Verify in Swift by running the app and watching the console:
```
SeedCatalog: 0 items (catalog.json is empty placeholder — this is expected until you run build-catalog.html)
```
No "Failed to decode catalog.json" assertion = success.

---

## 5. Wire AppVersion.xcconfig

1. In Xcode, drag `AppVersion.xcconfig` from Finder into the project
   navigator (drop on the project itself, at the very top, NOT on a target).
2. "Add to targets: ArchiveWatch" = **UNCHECKED** (xcconfig files don't
   go in the app bundle).
3. Click the project (top of navigator) → **Info** tab → expand
   **Configurations**.
4. For each row (Debug, Release):
   - Click the value column for the **project** row (not target).
   - Select **AppVersion** from the dropdown.
5. Confirm: Build Settings → search "MARKETING_VERSION" → shows `1.0`
   (the value from `AppVersion.xcconfig`).

---

## 6. Create Secrets.xcconfig (TMDb token) ⚠️

This is the one file that **must not** be committed. `.gitignore` already
excludes it.

1. In Finder, create a new file at the repo root: `Secrets.xcconfig`
2. Contents (single line):
   ```
   TMDB_BEARER_TOKEN = eyJhbGciOiJIUzI1NiJ9…(your actual v4 read token)
   ```
   No quotes, no trailing semicolon. Just `KEY = value`.
3. Verify it's gitignored:
   ```
   grep Secrets.xcconfig .gitignore
   # should print: Secrets.xcconfig
   ```
   (If it doesn't, add `Secrets.xcconfig` to `.gitignore` before going further.)

### Wire it in:

We want `TMDB_BEARER_TOKEN` available to Swift at runtime. The pattern
is: xcconfig → Info.plist custom key → `Bundle.main.object(forInfoDictionaryKey:)`.

The Swift client (`TMDbClient.swift`) already reads
`Bundle.main.object(forInfoDictionaryKey: "TMDB_BEARER_TOKEN")`. We
just need to bridge the xcconfig value into Info.plist.

1. Drag `Secrets.xcconfig` into Xcode like we did AppVersion.
2. The trick: you can only assign ONE xcconfig per configuration slot.
   So instead of pointing configurations at `Secrets.xcconfig`, make
   `AppVersion.xcconfig` include it:
   ```
   // AppVersion.xcconfig (edit this file, root of repo)
   MARKETING_VERSION = 1.0
   CURRENT_PROJECT_VERSION = 1

   #include? "Secrets.xcconfig"
   ```
   The `#include?` (with the question mark) makes it optional —
   builds still work on CI machines or pristine clones where
   `Secrets.xcconfig` is absent; the `TMDB_BEARER_TOKEN` build
   setting just evaluates to `$(TMDB_BEARER_TOKEN)` literally.
3. Now the token is available as a build setting. Bridge to
   Info.plist: **target ArchiveWatch → Info tab → Custom tvOS Target
   Properties → + button →**
   - Key: `TMDB_BEARER_TOKEN`
   - Type: String
   - Value: `$(TMDB_BEARER_TOKEN)`

### Verify:

Build + run. In the Xcode console:
```swift
// Somewhere in a view, temporarily:
print("token present:", TMDbClient.shared.hasCredentials)
```
(Add `hasCredentials` as a computed property on TMDbClient if you want
this test point; or just trust it'll work — our TMDbClient throws a
clear `missingCredentials` error if the key is absent.)

---

## 7. First build + run

1. Pick the scheme: **ArchiveWatch** (should be auto-selected).
2. Pick a destination: any **Apple TV** simulator from the device menu.
3. Cmd+R.

What you should see:
- App launches in the simulator.
- A `NavigationStack` with the template "Home View" text appears.
- Xcode console shows no red errors. SeedCatalog runs silently.

This is the M0 finish line. Next up: start building the real Home,
Detail, and Player views for M1.

---

## 8. Now generate the real seed catalog

Once GitHub Pages is live:

1. Open `https://bhwilkoff.github.io/Archive-Watch/build-catalog.html`
   on any device.
2. Paste the same TMDb bearer token you used in `Secrets.xcconfig`.
3. Click **Build catalog**. Wait 3–8 minutes depending on network.
4. When complete, click **Download catalog.json**.
5. Replace the empty `catalog.json` at the repo root with the downloaded
   file. Commit it.
6. Back in Xcode: Cmd+R. Now `SeedCatalog.prime(into:)` should insert
   the catalog entries into SwiftData on first launch.

---

## Troubleshooting

### "Cannot find type 'ContentItem' in scope" (or similar cross-file lookups)

The Swift files weren't added to the target. Right-click each file →
File Inspector (right panel) → Target Membership → ArchiveWatch ✓.
Do this for every file we moved from `ios/`.

### Build Phase: Compile Sources shows duplicates

Means some files got added twice. Target → Build Phases → Compile Sources
→ remove duplicates (keep the ones whose path points inside
`ArchiveWatch/`).

### "Redefinition of 'ArchiveWatchApp'" or two @main structs

The Xcode-generated `ArchiveWatchApp.swift` is still present alongside
our renamed one. Delete the duplicate.

### Swift 6 strict-concurrency errors

Our scaffold compiles cleanly under Swift 5 mode. If you're on Xcode 16
and hit concurrency errors:
- Target → Build Settings → search "Strict Concurrency"
- Set **Strict Concurrency Checking** = `Minimal` for now
- We can tighten to `Complete` later as an explicit tracked task

### catalog.json / featured.json / collections.json not found at runtime

The bundle resources weren't added to the target.
- Click each file in the navigator → File Inspector → Target Membership → ArchiveWatch ✓
- Build → Product → Show Build Folder in Finder → open `ArchiveWatch.app`
  → verify the JSON files are inside.

### TMDB_BEARER_TOKEN is empty at runtime

Walk through Step 6 again; the most common miss is the Info.plist key:
you need a custom key named exactly `TMDB_BEARER_TOKEN` with value
`$(TMDB_BEARER_TOKEN)`. The dollar-paren syntax tells Xcode to
substitute the value at build time from the build settings.

---

## What M0 looks like done

Six boxes in `SCRATCHPAD.md` under M0 all checked:

- [x] Xcode tvOS project created at repo root as `ArchiveWatch`
- [x] Swift files moved from `ios/` into Xcode group, `ios/` deleted
- [x] `AppVersion.xcconfig` wired to tvOS target (Debug + Release)
- [x] `Secrets.xcconfig` created (gitignored) with `TMDB_BEARER_TOKEN`
- [x] Empty tvOS shell runs on Simulator
- [x] GitHub Pages enabled (so the dashboard goes live) ← *(you already did this)*

When all six are green, we move to M1. First task: replace the template
ContentView with tvOS-native `TabView` + the Home shelves screen.
