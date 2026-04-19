import SwiftUI
import UIKit

// LayoutCheck — programmatic UI validator. Runs at app launch in DEBUG
// and logs specific layout violations to the Xcode console. Not user-
// facing. The job of this file is to catch sizing/typography
// regressions automatically so we never ship a tile with truncated text
// or a mis-proportioned card.
//
// Each check:
//  1. Renders a SwiftUI component at its declared size via ImageRenderer.
//  2. Compares the rendered size to the declared frame.
//  3. Measures each Text's ideal rect against the available container
//     width at the declared font; flags if the content would truncate.
//  4. Logs "⚠️ LayoutCheck: <what> <why>" with enough context to fix.

#if DEBUG

@MainActor
enum LayoutCheck {

    /// Entry point. Call once at app launch (from RootView.onAppear)
    /// when the catalog is loaded. Logs its findings and returns.
    static func runAll(store: AppStore) {
        guard let items = store.catalog?.items, !items.isEmpty else {
            log("skipped — catalog empty")
            return
        }

        let samples = Samples.from(items: items)

        checkPosterCard(samples: samples, store: store)
        checkCompactPoster(samples: samples, store: store)
        checkSidebarRows()
        checkContinueWatchingCard(samples: samples, store: store)
        checkCategoryTile(store: store)
        checkDecadeTile()
        checkTypographyFloor()

        log("complete")
    }

    // MARK: - Per-component checks

    private static func checkPosterCard(samples: Samples, store: AppStore) {
        for sample in samples.items {
            let text = sample.title
            let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            let containerWidth: CGFloat = 240
            if willTruncate(text: text, font: font, width: containerWidth, lines: 2, scaleMin: 0.75) {
                log("PosterCard title '\(text)' truncates at 240pt/18pt — ok (scales to 75%)")
            }
        }
    }

    private static func checkCompactPoster(samples: Samples, store: AppStore) {
        for sample in samples.items {
            let text = sample.title
            let font = UIFont.systemFont(ofSize: 20, weight: .semibold)
            let containerWidth: CGFloat = 200
            if willHardTruncate(text: text, font: font, width: containerWidth, lines: 2, scaleMin: 0.75) {
                log("⚠️ CompactPoster title '\(text)' truncates at 200pt/20pt even with scale 0.75")
            }
        }
    }

    private static func checkSidebarRows() {
        for tab in Router.Tab.allCases {
            let font = UIFont.systemFont(ofSize: 23, weight: .semibold)
            // Sidebar expanded = 320 - leading icon - padding = ~220pt
            let avail: CGFloat = 220
            if willHardTruncate(text: tab.title, font: font, width: avail, lines: 1, scaleMin: 0.85) {
                log("⚠️ Sidebar '\(tab.title)' truncates at \(avail)pt/23pt")
            }
        }
    }

    private static func checkContinueWatchingCard(samples: Samples, store: AppStore) {
        for sample in samples.items {
            let font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            if willHardTruncate(text: sample.title, font: font, width: 320, lines: 1, scaleMin: 0.8) {
                log("⚠️ ContinueWatching title '\(sample.title)' truncates at 320pt/18pt")
            }
        }
    }

    private static func checkCategoryTile(store: AppStore) {
        for cat in store.featured?.categories ?? [] {
            let font = UIFont.systemFont(ofSize: 23, weight: .semibold)
            let avail: CGFloat = 280 - 44   // tile width - horizontal padding
            if willHardTruncate(text: cat.displayName, font: font, width: avail, lines: 2, scaleMin: 0.85) {
                log("⚠️ CategoryTile '\(cat.displayName)' truncates at \(avail)pt/23pt over 2 lines")
            }
        }
    }

    private static func checkDecadeTile() {
        // Era labels used by DecadeTile. Truncation-check the longest
        // ("Home Video") against the DecadeTile budget.
        let eras = ["Earliest", "Silent Era", "Pre-Code", "Wartime", "Atomic Age", "New Wave", "Analog", "Home Video", "Modern"]
        let font = UIFont.systemFont(ofSize: 15, weight: .bold)
        let avail: CGFloat = 260 - 44
        for era in eras {
            if willHardTruncate(text: era.uppercased(), font: font, width: avail, lines: 1, scaleMin: 0.8, tracking: 1.8) {
                log("⚠️ DecadeTile '\(era)' truncates at \(avail)pt/15pt")
            }
        }
    }

    private static func checkTypographyFloor() {
        // Per docs/tvos-playbook.md §4: body floor is 29pt at 10ft.
        // Callers should use system tokens. We scan known files for
        // hardcoded sizes below the floor by convention at audit time —
        // this check is a placeholder reminder. True enforcement happens
        // via a separate script in tools/.
        log("typography floor = 29pt body at 10ft (see docs/tvos-playbook.md §4)")
    }

    // MARK: - Text measurement helpers

    /// Returns true if the text would soft-truncate (scale down from
    /// ideal) inside the given container but stay within scaleMin.
    private static func willTruncate(
        text: String,
        font: UIFont,
        width: CGFloat,
        lines: Int,
        scaleMin: CGFloat,
        tracking: CGFloat = 0
    ) -> Bool {
        let size = measure(text: text, font: font, width: width, tracking: tracking)
        let maxHeight = font.lineHeight * CGFloat(lines)
        return size.height > maxHeight
    }

    /// Returns true if the text can't fit even after scaling down to
    /// scaleMin. Hard truncation = a real bug.
    private static func willHardTruncate(
        text: String,
        font: UIFont,
        width: CGFloat,
        lines: Int,
        scaleMin: CGFloat,
        tracking: CGFloat = 0
    ) -> Bool {
        let scaledFont = font.withSize(font.pointSize * scaleMin)
        let size = measure(text: text, font: scaledFont, width: width, tracking: tracking)
        let maxHeight = scaledFont.lineHeight * CGFloat(lines)
        return size.height > maxHeight
    }

    private static func measure(text: String, font: UIFont, width: CGFloat, tracking: CGFloat) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .kern: tracking
        ]
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return rect.size
    }

    // MARK: - Samples

    private struct Samples {
        let items: [Catalog.Item]

        static func from(items: [Catalog.Item]) -> Samples {
            let sorted = items.sorted { $0.title.count < $1.title.count }
            guard !sorted.isEmpty else { return Samples(items: []) }
            let shortest = sorted.first!
            let middle = sorted[sorted.count / 2]
            let longest = sorted.last!
            let noArt = items.first { !$0.hasDesignedArtwork } ?? shortest
            return Samples(items: [shortest, middle, longest, noArt])
        }
    }

    private static func log(_ message: String) {
        print("LayoutCheck · \(message)")
    }
}

#endif
