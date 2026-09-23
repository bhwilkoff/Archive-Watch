#if os(macOS)
import SwiftUI

// SCENES (macOS-DESIGN §D31).
//
// Owner, 2026-09-23: "Each scene should be fully customizable and you should
// be able to say (with a setting/toggle) whether to keep the default
// audio/tiles or build new ones for the scene."
//
// HOW IT WORKS: `StudioControls` stays the ONE editing surface — every control
// already writes to it and every write already reaches the engine. A scene is
// a snapshot: leaving one CAPTURES the controls into it, arriving APPLIES the
// next one to them. So no control had to learn about scenes, and the toggle
// decides only where the captured tiles/audio go — into the scene's own copy,
// or into the show-wide value every inheriting scene shares.

extension StudioLayout: Codable {}
extension StudioChatSide: Codable {}
extension MacCardChoice: Codable {}

struct StudioSceneTiles: Codable, Equatable {
    var camera = StudioCameraFraming()
    var guests = StudioCameraFraming()
}

struct StudioSceneAudio: Codable, Equatable {
    var filmGain = 1.0, micGain = 1.0, callGain = 1.0
    var filmMuted = false, micMuted = false, callMuted = false
    var duck = true
}

struct StudioScene: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    // ALWAYS the scene's own — they are what makes one scene another.
    var layout: StudioLayout = .corner
    var card: MacCardChoice = .none
    var lowerThird = true, lowerTitle = true, lowerMeta = true, lowerProvenance = true
    var chat = true
    var chatSide: StudioChatSide = .left
    // §D31's two toggles. On = follow the show-wide value.
    var useShowTiles = true
    var useShowAudio = true
    var tiles: StudioSceneTiles?
    var audio: StudioSceneAudio?
}

@MainActor
@Observable
final class StudioScenes {
    static let shared = StudioScenes()

    private(set) var scenes: [StudioScene]
    private(set) var selectedID: UUID
    /// The show-wide tiles and audio every inheriting scene shares.
    private var showTiles: StudioSceneTiles
    private var showAudio: StudioSceneAudio

    private static let key = "StudioScenes.v1"

    private struct Saved: Codable {
        var scenes: [StudioScene]
        var selectedID: UUID
        var showTiles: StudioSceneTiles
        var showAudio: StudioSceneAudio
    }

    static let starters: [StudioScene] = [
        StudioScene(name: "Starting soon", layout: .host, card: .startingSoon, chat: true),
        StudioScene(name: "Film", layout: .corner),
        StudioScene(name: "Intermission", layout: .host, card: .intermission),
        StudioScene(name: "Discussion", layout: .side),
        StudioScene(name: "Thanks", layout: .host, card: .ending),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Saved.self, from: data), !s.scenes.isEmpty {
            scenes = s.scenes
            selectedID = s.scenes.contains { $0.id == s.selectedID } ? s.selectedID : s.scenes[0].id
            showTiles = s.showTiles
            showAudio = s.showAudio
        } else {
            scenes = Self.starters
            selectedID = Self.starters[1].id      // "Film": what a Studio opened on a film shows
            showTiles = StudioSceneTiles()
            showAudio = StudioSceneAudio()
        }
    }

    var selected: StudioScene { scenes.first { $0.id == selectedID } ?? scenes[0] }
    private var selectedIndex: Int { scenes.firstIndex { $0.id == selectedID } ?? 0 }

    // MARK: Switching

    func select(_ id: UUID) {
        guard id != selectedID, scenes.contains(where: { $0.id == id }) else { return }
        capture()
        selectedID = id
        apply()
        save()
        awdiag("AWSCENE now %@ layout=%@ card=%@", selected.name,
               selected.layout.rawValue, selected.card.rawValue)
        // A switch is a chapter on the replay (§D30), named for the scene.
        if StudioSession.shared.isOnAir {
            let name = selected.name
            Task { await StudioSession.shared.markMoment(name) }
        }
    }

    /// Puts the selected scene on the controls — used on open, so the Studio
    /// starts in the scene it was left in rather than in whatever the controls
    /// defaulted to.
    func applySelected() {
        apply()
        #if DEBUG
        // `AW_STUDIO_SCENE="3@25"` — switch to the 3rd scene 25 s after the
        // Studio opens, through the SAME `select` the button calls. A door
        // instead of a synthesized click: pointer automation on the owner's
        // machine landed on their main display on 2026-09-23 when the Studio
        // sat on a second one.
        if let v = ProcessInfo.processInfo.environment["AW_STUDIO_SCENE"] {
            let parts = v.split(separator: "@")
            if let n = Int(parts.first ?? ""), n >= 1,
               let after = parts.count > 1 ? Double(parts[1]) : 0 {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(after * 1_000_000_000))
                    guard n <= self.scenes.count else { return }
                    awdiag("AWSCENE door selecting %d (%@)", n, self.scenes[n - 1].name)
                    self.select(self.scenes[n - 1].id)
                }
            }
        }
        #endif
    }

    /// The controls → the selected scene (and the show-wide values it
    /// inherits). Also the SAVE path: a host who edits and quits keeps it.
    func capture() {
        let c = StudioControls.shared
        var s = scenes[selectedIndex]
        s.layout = c.layout
        s.card = c.cardChoice
        s.lowerThird = c.showLowerThird; s.lowerTitle = c.showFilmTitle
        s.lowerMeta = c.showFilmMeta; s.lowerProvenance = c.showProvenance
        s.chat = c.showChat; s.chatSide = c.chatSide
        let tiles = StudioSceneTiles(camera: c.framing, guests: c.guestFraming)
        let audio = StudioSceneAudio(filmGain: c.filmGain, micGain: c.micGain, callGain: c.callGain,
                                     filmMuted: c.filmMuted, micMuted: c.micMuted,
                                     callMuted: c.callMuted, duck: c.duckEnabled)
        if s.useShowTiles { showTiles = tiles } else { s.tiles = tiles }
        if s.useShowAudio { showAudio = audio } else { s.audio = audio }
        scenes[selectedIndex] = s
    }

    private func apply() {
        let c = StudioControls.shared
        let s = selected
        // LAYOUT FIRST: its didSet clears a custom tile rect (§D14a), so the
        // tiles must land after it or a scene's own box is thrown away.
        c.layout = s.layout
        let t = s.useShowTiles ? showTiles : (s.tiles ?? showTiles)
        c.framing = t.camera
        c.guestFraming = t.guests
        let a = s.useShowAudio ? showAudio : (s.audio ?? showAudio)
        c.filmGain = a.filmGain; c.micGain = a.micGain; c.callGain = a.callGain
        c.filmMuted = a.filmMuted; c.micMuted = a.micMuted; c.callMuted = a.callMuted
        c.duckEnabled = a.duck
        c.showLowerThird = s.lowerThird; c.showFilmTitle = s.lowerTitle
        c.showFilmMeta = s.lowerMeta; c.showProvenance = s.lowerProvenance
        c.showChat = s.chat; c.chatSide = s.chatSide
        // The card last: it is the most visible thing a switch changes, and
        // an empty custom card is refused by the controls themselves (§D10).
        c.cardChoice = s.card
    }

    // MARK: §D31's toggles

    func setUseShowTiles(_ on: Bool) {
        capture()
        var s = scenes[selectedIndex]
        guard s.useShowTiles != on else { return }
        s.useShowTiles = on
        // OFF seeds the scene's copy from what is on screen now; ON returns
        // the controls to the show-wide value.
        if !on { s.tiles = showTiles }
        scenes[selectedIndex] = s
        if on { apply() }
        save()
    }

    func setUseShowAudio(_ on: Bool) {
        capture()
        var s = scenes[selectedIndex]
        guard s.useShowAudio != on else { return }
        s.useShowAudio = on
        if !on { s.audio = showAudio }
        scenes[selectedIndex] = s
        if on { apply() }
        save()
    }

    // MARK: Editing the list

    func add() {
        capture()
        var s = selected
        s.id = UUID()
        s.name = uniqueName("Scene")
        scenes.insert(s, at: selectedIndex + 1)
        selectedID = s.id
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, let i = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[i].name = n
        save()
    }

    func delete(_ id: UUID) {
        guard scenes.count > 1, let i = scenes.firstIndex(where: { $0.id == id }) else { return }
        if id == selectedID {
            let next = scenes[i == 0 ? 1 : i - 1].id
            selectedID = next
            scenes.remove(at: i)
            apply()
        } else {
            scenes.remove(at: i)
        }
        save()
    }

    private func uniqueName(_ base: String) -> String {
        var n = scenes.count + 1
        while scenes.contains(where: { $0.name == "\(base) \(n)" }) { n += 1 }
        return "\(base) \(n)"
    }

    func save() {
        let s = Saved(scenes: scenes, selectedID: selectedID, showTiles: showTiles, showAudio: showAudio)
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - The scene bar

/// The row above STREAM: one button per scene, the selected one filled. The
/// scene's settings live in a menu at the end — renaming, the two §D31
/// toggles, deleting — because they are decided once and a switch is pressed
/// mid-sentence, so the switch gets the room.
struct StudioSceneBar: View {
    @Bindable private var store = StudioScenes.shared
    @State private var renaming: UUID?
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(store.scenes.enumerated()), id: \.element.id) { i, scene in
                        sceneButton(scene, index: i)
                    }
                }
            }
            Button { store.add() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New scene from this one")
            settingsMenu
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.bar)
        .popover(isPresented: Binding(get: { renaming != nil },
                                      set: { if !$0 { renaming = nil } })) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scene name").font(.headline)
                TextField("Name", text: $draft)
                    .frame(width: 220)
                    .onSubmit(commitRename)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }
                    Button("Rename", action: commitRename).keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
    }

    private func sceneButton(_ scene: StudioScene, index: Int) -> some View {
        let on = scene.id == store.selectedID
        return Button { store.select(scene.id) } label: {
            HStack(spacing: 6) {
                if index < 9 {
                    Text("\(index + 1)").font(.caption2.weight(.bold)).monospacedDigit()
                        .foregroundStyle(on ? .white.opacity(0.8) : .secondary)
                }
                Text(scene.name).font(.callout.weight(on ? .semibold : .regular))
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(on ? Color.accentColor : Color.secondary.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(on ? .white : .primary)
            .fixedSize()
        }
        .buttonStyle(.borderless)
        .contextMenu {
            Button("Rename…") { draft = scene.name; renaming = scene.id }
            Button("Delete", role: .destructive) { store.delete(scene.id) }
                .disabled(store.scenes.count < 2)
        }
    }

    private var settingsMenu: some View {
        let s = store.selected
        return Menu {
            Toggle("Use the show's tiles", isOn: Binding(get: { s.useShowTiles },
                                                          set: { store.setUseShowTiles($0) }))
            Toggle("Use the show's audio", isOn: Binding(get: { s.useShowAudio },
                                                          set: { store.setUseShowAudio($0) }))
            Divider()
            Button("Rename “\(s.name)”…") { draft = s.name; renaming = s.id }
            Button("Delete “\(s.name)”", role: .destructive) { store.delete(s.id) }
                .disabled(store.scenes.count < 2)
        } label: {
            Label("Scene settings", systemImage: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func commitRename() {
        if let id = renaming { store.rename(id, to: draft) }
        renaming = nil
    }
}

/// ⌘1…⌘9 — OBS's scene hotkeys (§D31).
struct SceneCommand: View {
    let index: Int
    @Bindable private var store = StudioScenes.shared
    var body: some View {
        if index < store.scenes.count {
            let scene = store.scenes[index]
            Button {
                store.select(scene.id)
            } label: {
                if scene.id == store.selectedID { Label(scene.name, systemImage: "checkmark") }
                else { Text(scene.name) }
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
    }
}
#endif
