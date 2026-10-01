// A show's whole setup, saved and loaded before Go Live (macOS-DESIGN §D41).
//
// Owner, 2026-09-30: "Is there any way to get everything set up for a future
// show, including cameras, audio, etc. and then be able to load it into the
// studio again before pressing 'go live'?"
//
// Foundation only, so §8.75 compiles it without the app. The scene set is
// carried as the scenes store's OWN encoding (macOS-only types), so a scene
// saved by any version reads back through the same decoder that already keeps
// old scenes alive.

import Foundation

public struct StudioSetup: Codable, Equatable, Sendable {

    /// A camera by its device, or a call SLOT by its app. A call's window is
    /// never stored: the system picker gives no lasting handle (§D23b).
    public struct Source: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable { case camera, call }
        public var id: String
        public var kind: Kind
        /// `AVCaptureDevice.uniqueID`; nil is the system default. Nil for a call.
        public var deviceID: String?
        /// The device's name, or the call's app. Display only: two setups that
        /// differ only here are the same setup.
        public var name: String?

        public init(id: String, kind: Kind, deviceID: String? = nil, name: String? = nil) {
            self.id = id; self.kind = kind; self.deviceID = deviceID; self.name = name
        }
    }

    /// The levels and the film's mute are the scenes' (§D31); the mic and call
    /// MUTES are the host's and are never here.
    public struct Mix: Codable, Equatable, Sendable {
        public var microphoneID: String?
        public var micGateEnabled = false
        public var micGateThreshold = 0.02
        public init(microphoneID: String? = nil, micGateEnabled: Bool = false,
                    micGateThreshold: Double = 0.02) {
            self.microphoneID = microphoneID; self.micGateEnabled = micGateEnabled
            self.micGateThreshold = micGateThreshold
        }
    }

    public struct CardLine: Codable, Equatable, Sendable {
        public var text: String
        public var rank: String
        public init(text: String, rank: String) { self.text = text; self.rank = rank }
    }

    public struct OnScreen: Codable, Equatable, Sendable {
        public var customCard: [CardLine] = []
        public var chatHideCommands = true
        public var chatHideLinks = true
        public var chatBlocked = ""
        public init(customCard: [CardLine] = [], chatHideCommands: Bool = true,
                    chatHideLinks: Bool = true, chatBlocked: String = "") {
            self.customCard = customCard; self.chatHideCommands = chatHideCommands
            self.chatHideLinks = chatHideLinks; self.chatBlocked = chatBlocked
        }
    }

    public struct Output: Codable, Equatable, Sendable {
        public var width: Int, height: Int, frameRate: Int, bitrateKbps: Int
        public init(width: Int, height: Int, frameRate: Int, bitrateKbps: Int) {
            self.width = width; self.height = height
            self.frameRate = frameRate; self.bitrateKbps = bitrateKbps
        }
    }

    public var archiveID: String?
    /// `<item>/<file>` (Decision 143).
    public var copy: String?
    /// The scenes store's own encoding, canonical (sorted keys).
    public var scenes: Data
    public var sources: [Source]
    public var mix: Mix
    public var onScreen: OnScreen
    public var output: Output

    public init(archiveID: String?, copy: String?, scenes: Data, sources: [Source],
                mix: Mix, onScreen: OnScreen, output: Output) {
        self.archiveID = archiveID; self.copy = copy; self.scenes = scenes
        self.sources = sources; self.mix = mix; self.onScreen = onScreen; self.output = output
    }

    // MARK: Comparing

    /// Which parts differ, by name — what the DEBUG door logs and §8.75 reads.
    public static func differences(_ a: StudioSetup, _ b: StudioSetup) -> [String] {
        var out: [String] = []
        if a.archiveID != b.archiveID { out.append("film") }
        if a.copy != b.copy { out.append("copy") }
        if a.scenes != b.scenes { out.append("scenes") }
        if a.sources.map(\.unnamed) != b.sources.map(\.unnamed) { out.append("sources") }
        if a.mix != b.mix { out.append("mix") }
        if a.onScreen != b.onScreen { out.append("onScreen") }
        if a.output != b.output { out.append("output") }
        return out
    }

    /// THE WORK A HOST COULD LOSE, as one string: the "Replace the Studio's
    /// current setup?" question is asked only when this differs from the setup
    /// last loaded or saved. The film and the copy are not work (they are one
    /// choice away), and names are display only. The caller passes the scenes
    /// with the selection normalized for the same reason.
    public static func fingerprint(_ s: StudioSetup) -> String {
        var w = s
        w.archiveID = nil
        w.copy = nil
        w.sources = s.sources.map(\.unnamed)
        let data = canonical(w) ?? Data()
        // FNV-1a 64: stable across launches, which `Hasher` is not.
        var h: UInt64 = 0xcbf29ce484222325
        for b in data { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16) + "-" + String(data.count)
    }

    public static func canonical<T: Encodable>(_ v: T) -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try? e.encode(v)
    }

    // MARK: The copy, as the versions store keeps it

    /// The versions store's key for `<item>/<file>` on title `archiveID`: the
    /// bare file name for the title's own item, `@item:name` for a merged
    /// upload's (the same rule as `ArchiveVersions.Version.choiceKey`).
    public static func choiceKey(forCopy path: String, archiveID: String) -> String? {
        guard let slash = path.firstIndex(of: "/") else { return nil }
        let item = String(path[..<slash])
        let name = String(path[path.index(after: slash)...])
        guard !item.isEmpty, !name.isEmpty else { return nil }
        return item == archiveID ? name : "@\(item):\(name)"
    }

    /// The inverse, mirroring `ArchiveVersions.location(of:title:)`.
    public static func copyPath(choiceKey key: String, archiveID: String) -> String {
        if key.hasPrefix("@"), let colon = key.firstIndex(of: ":") {
            let item = String(key[key.index(after: key.startIndex)..<colon])
            let name = String(key[key.index(after: colon)...])
            if !item.isEmpty, !name.isEmpty { return "\(item)/\(name)" }
        }
        return "\(archiveID)/\(key)"
    }

    // MARK: Capture and apply, through a target

    public struct Parts: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let film = Parts(rawValue: 1)
        public static let sources = Parts(rawValue: 2)
        public static let scenes = Parts(rawValue: 4)
        public static let mix = Parts(rawValue: 8)
        public static let onScreen = Parts(rawValue: 16)
        public static let output = Parts(rawValue: 32)
        public static let all: Parts = [.film, .sources, .scenes, .mix, .onScreen, .output]
    }

    @MainActor
    public static func capture(from t: some StudioSetupTarget) -> StudioSetup {
        StudioSetup(archiveID: t.setupFilm, copy: t.setupCopy(), scenes: t.setupScenes(),
                    sources: t.setupSources(), mix: t.setupMix, onScreen: t.setupOnScreen,
                    output: t.setupOutput)
    }

    /// THE ORDER IS THE RULE. The copy is chosen before the film is taken, so
    /// the player built for it plays that file. Sources go before scenes:
    /// a scene names its tiles by source id, and the composition drops an id
    /// the Sources list does not hold. The custom card's words go after the
    /// scenes, which decide whether the custom card is the one chosen.
    /// `parts` exists for §8.75's control, which drops one.
    @MainActor
    public static func apply(_ s: StudioSetup, to t: some StudioSetupTarget, parts: Parts = .all) {
        if parts.contains(.film) { t.applyFilm(s.archiveID, copy: s.copy) }
        if parts.contains(.sources) { t.applySources(s.sources) }
        if parts.contains(.scenes) { t.applyScenes(s.scenes) }
        if parts.contains(.mix) { t.applyMix(s.mix) }
        if parts.contains(.onScreen) { t.applyOnScreen(s.onScreen) }
        if parts.contains(.output) { t.applyOutput(s.output) }
    }
}

extension StudioSetup.Source {
    var unnamed: StudioSetup.Source { var c = self; c.name = nil; return c }
}

/// What a setup is captured from and applied to: the Mac's real stores in the
/// app, an in-memory model in §8.75.
@MainActor
public protocol StudioSetupTarget {
    var setupFilm: String? { get }
    func setupCopy() -> String?
    func setupScenes() -> Data
    func setupSources() -> [StudioSetup.Source]
    var setupMix: StudioSetup.Mix { get }
    var setupOnScreen: StudioSetup.OnScreen { get }
    var setupOutput: StudioSetup.Output { get }

    func applyFilm(_ archiveID: String?, copy: String?)
    func applySources(_ sources: [StudioSetup.Source])
    func applyScenes(_ data: Data)
    func applyMix(_ mix: StudioSetup.Mix)
    func applyOnScreen(_ onScreen: StudioSetup.OnScreen)
    func applyOutput(_ output: StudioSetup.Output)
}

/// A setup the host named, with no schedule.
public struct StudioNamedSetup: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var saved: Date
    public var setup: StudioSetup
    public init(id: UUID = UUID(), name: String, saved: Date = Date(), setup: StudioSetup) {
        self.id = id; self.name = name; self.saved = saved; self.setup = setup
    }
}

/// The named setups, in `UserDefaults` beside the schedule (a few rows).
public enum StudioSetupStore {
    public static let defaultsKey = "studio.savedSetups"

    public static func load(from defaults: UserDefaults = .standard) -> [StudioNamedSetup] {
        guard let data = defaults.data(forKey: defaultsKey),
              let all = try? JSONDecoder().decode([StudioNamedSetup].self, from: data)
        else { return [] }
        return all
    }

    public static func save(_ all: [StudioNamedSetup], to defaults: UserDefaults = .standard) {
        let sorted = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(sorted) { defaults.set(data, forKey: defaultsKey) }
    }

    /// Saving under a name already used replaces that setup.
    @discardableResult
    public static func save(name: String, setup: StudioSetup, now: Date = Date(),
                            defaults: UserDefaults = .standard) -> StudioNamedSetup {
        var all = load(from: defaults)
        let same = all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let entry = StudioNamedSetup(id: same?.id ?? UUID(), name: name, saved: now, setup: setup)
        all.removeAll { $0.id == entry.id }
        all.append(entry)
        save(all, to: defaults)
        return entry
    }

    public static func remove(id: UUID, defaults: UserDefaults = .standard) {
        save(load(from: defaults).filter { $0.id != id }, to: defaults)
    }
}
