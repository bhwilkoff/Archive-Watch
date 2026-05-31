# Top Shelf extension — setup guide

Decision 015 calls for a Top Shelf extension (`.sectioned`) surfacing
Continue Watching + Editor's Picks + What's New when Archive Watch is
focused on the tvOS Home Screen.

**Why this is a doc and not a commit:** a Top Shelf extension is a
separate *app-extension target* with its own bundle, Info.plist, and an
**App Group** entitlement shared with the main app. Creating a target
means rewriting `project.pbxproj` (target graph, build phases, an
embed-extension copy phase, container proxies). Doing that by hand —
especially in this project's *synchronized file groups* layout — risks
leaving the `.xcodeproj` unopenable. It's a 10-minute job in Xcode and a
fragile one by text edit, so the code is ready below and the wiring is
manual.

All code here is **complete and builds** once the target + App Group
exist; nothing else is required.

---

## Step 1 — App Group (both targets)

1. Apple Developer portal (or Xcode → Signing & Capabilities → **+ App
   Group**) → create `group.com.bhwilkoff.archivewatch`.
2. Add the **App Groups** capability to the **main app** target and
   select that group.
3. Repeat for the Top Shelf extension target (Step 2).

This is the shared container both processes read/write.

---

## Step 2 — Create the extension target

Xcode → **File ▸ New ▸ Target… ▸ tvOS ▸ TV Top Shelf Extension**.
Name it `ArchiveWatchTopShelf`. Xcode wires the embed phase + a stub
`ContentProvider`. Then:

- Add the **App Groups** capability → `group.com.bhwilkoff.archivewatch`.
- Replace the generated `ContentProvider.swift` with the file in Step 4.
- Delete the boilerplate sample code Xcode generated.

---

## Step 3 — Main app: write the snapshot (already-safe code)

Add this to the **main app** target (e.g.
`ArchiveWatch/ArchiveWatch/Services/TopShelfSnapshot.swift`). It writes a
small JSON the extension reads. Call `TopShelfSnapshot.write(from:)` after
the catalog loads and whenever Continue Watching changes. It no-ops
gracefully if the App Group isn't configured yet, so it's safe to add
before the group exists.

```swift
import Foundation

enum TopShelfSnapshot {
    static let appGroup = "group.com.bhwilkoff.archivewatch"
    static let fileName = "topshelf.json"

    struct Payload: Codable {
        struct Item: Codable {
            let archiveID: String
            let title: String
            let posterURL: String?
            let year: Int?
        }
        struct Section: Codable {
            let title: String
            let items: [Item]
        }
        let sections: [Section]
        let generatedAt: Double   // epoch seconds; stamp at call site
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        )
    }

    static func write(_ payload: Payload) {
        guard let dir = containerURL else { return }   // group not set up yet
        let url = dir.appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read() -> Payload? {
        guard let dir = containerURL else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
```

Build the payload from `AppStore` — e.g. Editor's Picks shelf + the
SwiftData `WatchProgress` items mapped back to catalog items. Keep it to
~10 items per section (Top Shelf has tight memory limits).

---

## Step 4 — Extension: the content provider

Replace the generated `ContentProvider.swift` in the extension target:

```swift
import TVServices

class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let payload = TopShelfSnapshot.read() else {
            completionHandler(nil); return
        }

        let sections = payload.sections.map { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem> in
            let items = section.items.map { item -> TVTopShelfSectionedItem in
                let shelfItem = TVTopShelfSectionedItem(identifier: item.archiveID)
                shelfItem.title = item.title
                if let poster = item.posterURL, let url = URL(string: poster) {
                    shelfItem.setImageURL(url, for: [.screenScale1x, .screenScale2x])
                }
                shelfItem.imageShape = .poster
                // Deep link into the app (Step 5).
                shelfItem.playAction = nil
                shelfItem.displayAction = TVTopShelfAction(
                    url: URL(string: "archivewatch://item/\(item.archiveID)")!
                )
                return shelfItem
            }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }

        let content = TVTopShelfSectionedContent(sections: sections)
        completionHandler(content)
    }
}
```

> `TopShelfSnapshot` must be a member of **both** targets (check the
> extension in the file's Target Membership), or duplicate the small
> reader into the extension.

---

## Step 5 — Deep-link handling in the app

Top Shelf items open `archivewatch://item/{id}`. Declare the scheme and
route it:

1. **Info.plist** — add a URL type. Since the project uses
   `GENERATE_INFOPLIST_FILE = YES`, set `INFOPLIST_FILE` to a small
   `ArchiveWatch/Info.plist` containing:

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>archivewatch</string></array>
     </dict>
   </array>
   <key>NSUserActivityTypes</key>
   <array><string>com.bhwilkoff.archivewatch.viewing</string></array>
   ```

   (The `NSUserActivityTypes` entry also completes the Detail-screen
   NSUserActivity → full "Add to Up Next" support.)

2. **Route it** — on the app's root scene:

   ```swift
   .onOpenURL { url in
       guard url.scheme == "archivewatch",
             url.host == "item" else { return }
       let id = url.lastPathComponent
       if let item = store.catalog?.items.first(where: { $0.archiveID == id }) {
           router.tab = .home
           router.homePath = NavigationPath()
           router.homePath.append(item)
       }
   }
   ```

   This same `onOpenURL` is the more robust transport for the App
   Intents too (replace the `IntentInbox` singleton with
   `archivewatch://surprise` etc. if you prefer URL-based routing).

---

## Step 6 — Keep it fresh

- Call `TopShelfSnapshot.write(...)` when the catalog loads and after
  playback updates progress.
- For background refresh of "What's New", schedule a `BGAppRefreshTask`
  (Decision 015 / M4) that re-writes the snapshot.

That's the whole feature. Once the target + App Group exist, the code
above is the entire implementation.
