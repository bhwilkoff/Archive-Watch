#if canImport(UIKit)
import UIKit
#endif
import MediaAccessibility

// Draw captions the way the VIEWER has asked for them.
//
// Apple already ships the control for this — Settings › Accessibility ›
// Subtitles & Captioning › Style — and `MediaAccessibility` publishes those
// choices to any app that cares to read them. So the app does NOT invent its own
// caption-appearance settings screen: it honours the one the person has already
// set, which is also the one their other video apps obey.
//
// Reading it costs nothing and covers font, size, colours and background opacity
// including the accessibility presets (Large Text, Classic, Outline). Hard-coding
// white-on-black would quietly ignore someone who needs 200% text.
enum SystemCaptionStyle {

    #if canImport(UIKit)
    /// Apply the viewer's caption style to a label used for live captions.
    static func apply(to label: UILabel, baseSize: CGFloat = 17) {
        let domain = MACaptionAppearanceDomain.user

        // Font: the user's chosen family, scaled by their text-size preference.
        let scale = CGFloat(MACaptionAppearanceGetRelativeCharacterSize(domain, nil))
        let descriptor = MACaptionAppearanceCopyFontDescriptorForStyle(
            domain, nil, .default).takeRetainedValue()
        label.font = UIFont(descriptor: descriptor as UIFontDescriptor,
                            size: baseSize * max(scale, 0.5))

        label.textColor = UIColor(
            cgColor: MACaptionAppearanceCopyForegroundColor(domain, nil).takeRetainedValue())
        let opacity = CGFloat(MACaptionAppearanceGetForegroundOpacity(domain, nil))
        if opacity > 0, opacity < 1 { label.textColor = label.textColor.withAlphaComponent(opacity) }

        let bg = UIColor(
            cgColor: MACaptionAppearanceCopyBackgroundColor(domain, nil).takeRetainedValue())
        let bgOpacity = CGFloat(MACaptionAppearanceGetBackgroundOpacity(domain, nil))
        // A fully transparent background is a legitimate preference, but live
        // captions sit over arbitrary footage — keep a floor so they stay legible
        // on a bright frame.
        label.backgroundColor = bg.withAlphaComponent(max(bgOpacity, 0.55))
        label.layer.cornerRadius = 6
        label.clipsToBounds = true
    }
    #endif

    /// Whether the viewer has asked that captions be shown at all.
    ///
    /// `.automatic` is the default and means "follow the app"; only an explicit
    /// `.forcedOnly` is a request NOT to see generated captions.
    static var viewerWantsCaptions: Bool {
        MACaptionAppearanceGetDisplayType(.user) != .forcedOnly
    }
}
