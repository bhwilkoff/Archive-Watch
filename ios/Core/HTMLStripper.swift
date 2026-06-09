import Foundation

// Sanitise Archive.org free-text fields before they hit the UI.
// Uploader `description` fields frequently contain raw HTML, entity
// codes, and messy whitespace. Mirror of the builder's stripHTML().

enum HTMLStripper {
    static func strip(_ input: String) -> String? {
        var s = input
        // Common structural tags → whitespace
        s = s.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"</p\s*>"#,  with: "\n\n", options: .regularExpression)
        // Strip all remaining tags
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Named entities
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&lt;": "<", "&gt;": ">",
            "&mdash;": "—", "&ndash;": "–", "&hellip;": "…"
        ]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
        // Numeric entities (&#123; and &#x1F;)
        s = s.replacingOccurrences(
            of: #"&#([0-9]+);"#,
            with: "$1",
            options: .regularExpression
        )
        // Collapse whitespace
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
