// What reaches the program, out of what strangers type (§D22).
//
// A PURE FUNCTION over one line, in its own file, for §D21's reason: a rule
// written inside the pump can only be exercised by a live broadcast carrying
// the exact traffic it describes, so in practice it never is, and the first
// time anybody learns what it does is on air.
//
// It is NOT moderation and must never be presented as such. It cannot see
// what a platform's AutoMod already dropped, it does not judge language, and
// a host who needs a person gone needs them gone from the platform. This is
// about clutter, and about the fact that whatever we draw is burned into the
// H.264 and stays in the recording.

import Foundation

public struct StudioChatFilter: Sendable, Equatable {

    /// Bot traffic. On a busy Twitch channel most `!`-prefixed lines are
    /// commands aimed at other bots, and the replies are aimed at nobody in
    /// the room. Default ON: a watch-along audience is not there for them.
    public var hideCommands = true

    /// Links. Default ON, and the reason is the burn-in rather than taste:
    /// a URL composited into someone else's broadcast is an endorsement the
    /// host never made, and it survives in the recording.
    public var hideLinks = true

    /// People the host has named, lowercased on the way in. Small on purpose
    /// — a long list here is a sign the host needs the platform's own tools.
    public var blocked: Set<String> = []

    public init() {}

    /// Parses the host's free-text field. Commas, spaces or newlines, with or
    /// without a leading `@`, because a host pasting from chat will bring one.
    public init(hideCommands: Bool, hideLinks: Bool, blockedText: String) {
        self.hideCommands = hideCommands
        self.hideLinks = hideLinks
        self.blocked = Set(blockedText
            .split(whereSeparator: { $0 == "," || $0 == " " || $0.isNewline })
            .map { $0.drop(while: { $0 == "@" }).lowercased() }
            .filter { !$0.isEmpty })
    }

    /// LINKS ARE MATCHED WITHOUT A SCHEME. "archive.org/details/x" and
    /// "bit.ly/abc" carry no `http://` and are the shapes people actually
    /// paste; requiring a scheme would have let almost everything through
    /// while the toggle said otherwise.
    private static let linkish = try! NSRegularExpression(
        pattern: #"(?i)\b(?:[a-z][a-z0-9+.-]*://|www\.)\S+|\b[a-z0-9-]+\.(?:com|net|org|io|tv|gg|ly|co|me|xyz|link|app|dev)\b(?:/\S*)?"#)

    public func allows(author: String, text: String) -> Bool {
        let who = author.drop(while: { $0 == "@" }).lowercased()
        if blocked.contains(who) { return false }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return false }

        // A LEADING `!` ONLY. A message that merely CONTAINS one ("wait what
        // !!") is somebody talking, and dropping it would quietly eat a real
        // conversation — which is the failure mode a host would never trace
        // back to a checkbox.
        if hideCommands, body.hasPrefix("!"), body.count > 1,
           body.dropFirst().first?.isLetter == true {
            return false
        }

        if hideLinks {
            let r = NSRange(body.startIndex..<body.endIndex, in: body)
            if Self.linkish.firstMatch(in: body, range: r) != nil { return false }
        }
        return true
    }

    /// Applies to a whole batch, keeping order.
    public func apply(_ lines: [StudioOverlay.ChatLine]) -> [StudioOverlay.ChatLine] {
        lines.filter { allows(author: $0.author, text: $0.text) }
    }
}

/// Which side of the frame the column sits on (§D22). Not a free position:
/// `StudioLayout.chatRect` dodges the lower third and the camera tile per
/// preset, and a host moving the column by hand would re-open the sign error
/// that once ran it through the host's face.
public enum StudioChatSide: String, CaseIterable, Sendable {
    case left, right

    public var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// §D32 — the one line a host can post into YouTube chat about the film.
///
/// PURE, so the length rule is tested without a network. YouTube refuses a
/// message over 200 characters, and the link is the point of the message —
/// a latecomer learns what they walked into, and anyone can go and watch it
/// themselves — so the LINK IS NEVER CUT. Words give way first, then the
/// title is shortened with an ellipsis; a URL cut in half is a dead link
/// under the host's name.
enum StudioChatShare {
    static let limit = 200

    static func message(title: String, meta: String, archiveID: String) -> String {
        let link = "https://archive.org/details/\(archiveID)"
        let tail = " Public domain, free to watch: \(link)"
        let shortTail = " \(link)"
        let head = meta.isEmpty ? "Now watching: \(title)." : "Now watching: \(title) — \(meta)."
        if head.count + tail.count <= limit { return head + tail }
        let bare = "Now watching: \(title)."
        if bare.count + tail.count <= limit { return bare + tail }
        if bare.count + shortTail.count <= limit { return bare + shortTail }
        // The title itself is too long: shorten IT, never the link.
        let room = limit - shortTail.count - "Now watching: …".count
        let cut = room > 0 ? String(title.prefix(room)) : ""
        return "Now watching: \(cut)…" + shortTail
    }
}
