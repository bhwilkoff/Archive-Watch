import Foundation

/// The host's OUTPUT choices — macOS-DESIGN §D4.
///
/// Resolution, frame rate and bitrate were hardcoded at 1920x1080 / 30 / 6 Mbps
/// in `StudioEngine.Configuration`, chosen for the host with no way to see or
/// change them. Owner: "which inputs/outputs are being managed".
///
/// §D4 draws a hard line through these three: **only the bitrate may change
/// while live.** An RTMP ingest will not accept a resolution or frame-rate
/// change mid-publish — §6.5 already documents that its own first answer
/// (halve the resolution under thermal pressure) would have destroyed the
/// broadcast it was meant to save. So those two are disabled with that
/// sentence rather than hidden, and the bitrate stays live because the
/// encoder genuinely supports it (`VideoEncoder.setBitrate`).
public enum StudioOutputSettings {

    public struct Size: Identifiable, Hashable, Sendable {
        public let width: Int
        public let height: Int
        public var id: String { "\(width)x\(height)" }
        public var label: String { "\(width) x \(height)" }
    }

    /// 16:9 only, because the program frame is composed at 16:9 and a
    /// non-matching output would letterbox the whole show rather than fit it.
    public static let sizes: [Size] = [
        Size(width: 1920, height: 1080),
        Size(width: 1280, height: 720),
        Size(width: 854, height: 480),
    ]

    public static let frameRates = [30, 24]

    /// Measured on an Apple TV 4K (WATCH-TOGETHER §9): zero dropped frames at
    /// 4 and 6 Mbps, 13 dropped at 8, 552 at 10. There is nothing above 6
    /// worth offering on this hardware, so the list stops where the evidence
    /// does rather than at a round number.
    public static let bitratesKbps = [2000, 3000, 4000, 6000]

    private static let wKey = "AWStudioOutWidth"
    private static let hKey = "AWStudioOutHeight"
    private static let fKey = "AWStudioOutFrameRate"
    private static let bKey = "AWStudioOutBitrateKbps"

    public static var width: Int {
        get { read(wKey, default: 1920) }
        set { UserDefaults.standard.set(newValue, forKey: wKey) }
    }
    public static var height: Int {
        get { read(hKey, default: 1080) }
        set { UserDefaults.standard.set(newValue, forKey: hKey) }
    }
    public static var frameRate: Int {
        get { read(fKey, default: 30) }
        set { UserDefaults.standard.set(newValue, forKey: fKey) }
    }
    public static var bitrateKbps: Int {
        get { read(bKey, default: 6000) }
        set { UserDefaults.standard.set(newValue, forKey: bKey) }
    }

    /// A stored 0 is "never set", not "zero bits per second". Reading it as
    /// the latter would configure an encoder with no bitrate at all, which
    /// fails in a way that looks like a network fault.
    private static func read(_ key: String, default d: Int) -> Int {
        let v = UserDefaults.standard.integer(forKey: key)
        return v > 0 ? v : d
    }

    public static var selectedSize: Size {
        sizes.first { $0.width == width && $0.height == height }
            ?? Size(width: width, height: height)
    }

}

// The bridge to the engine lives in `StudioEngine.swift`, not here, so this
// type compiles on its own and the §8 suite can test it without building
// VideoToolbox, AVFoundation and the publisher alongside it.

