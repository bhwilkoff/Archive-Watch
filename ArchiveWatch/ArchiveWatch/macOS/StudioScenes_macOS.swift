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
    // §D31 (2026-09-30) — the scene's Camera and Call switches, ALWAYS the
    // scene's own like the placement. OPTIONAL in storage, or every scene set
    // saved before they existed would fail to decode and be replaced by the
    // starters; nil reads as the starters' rule.
    var cameraShown: Bool?
    var callShown: Bool?
    /// §D40 — the sources this scene shows, back to front, by source id.
    /// OPTIONAL in storage for the same reason as the switches above; a scene
    /// that has none is migrated from them when the scenes load, so what it
    /// showed before §D40 it shows after.
    var shown: [String]?

    var camera: Bool {
        get { cameraShown ?? true }
        set { cameraShown = newValue }
    }
    /// Off only on the two cards that open and pause a show: before it starts
    /// and during a break the guests are not yet, or not currently, on.
    var call: Bool {
        get { callShown ?? !(card == .startingSoon || card == .intermission) }
        set { callShown = newValue }
    }
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
    /// §D31: a short dissolve between scenes, or a cut.
    var crossfade = true { didSet { save() } }

    private static let key = "StudioScenes.v1"

    private struct Saved: Codable {
        var scenes: [StudioScene]
        var selectedID: UUID
        var showTiles: StudioSceneTiles
        var showAudio: StudioSceneAudio
        // OPTIONAL, or every scene set saved before this field existed would
        // fail to decode and be replaced by the starters.
        var crossfade: Bool?
    }

    static let starters: [StudioScene] = [
        StudioScene(name: "Starting soon", layout: .host, card: .startingSoon, chat: true,
                    cameraShown: true, callShown: false),
        StudioScene(name: "Film", layout: .corner, cameraShown: true, callShown: true),
        StudioScene(name: "Intermission", layout: .host, card: .intermission,
                    cameraShown: true, callShown: false),
        StudioScene(name: "Discussion", layout: .side, cameraShown: true, callShown: true),
        StudioScene(name: "Thanks", layout: .host, card: .ending,
                    cameraShown: true, callShown: true),
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let s = try? JSONDecoder().decode(Saved.self, from: data), !s.scenes.isEmpty {
            scenes = s.scenes
            var pick = s.scenes.contains { $0.id == s.selectedID } ? s.selectedID : s.scenes[0].id
            // A SHOW NEVER OPENS ON ITS CLOSING CARD. The selection persists,
            // so a Studio last left on "Thanks" went live with "Thanks for
            // watching" over the film for the whole next broadcast — found
            // 2026-09-23 when a 20-minute bench run recorded 88 kbps of the
            // ending card and no film. Any scene the host opens on
            // deliberately ("Starting soon") is still restored.
            if let chosen = s.scenes.first(where: { $0.id == pick }), chosen.card == .ending {
                let opener = s.scenes.first { $0.card == .none } ?? s.scenes[0]
                pick = opener.id
                awdiag("AWSCENE opened on %@ rather than the closing card", opener.name)
            }
            selectedID = pick
            showTiles = s.showTiles
            showAudio = s.showAudio
            crossfade = s.crossfade ?? true
        } else {
            scenes = Self.starters
            selectedID = Self.starters[1].id      // "Film": what a Studio opened on a film shows
            showTiles = StudioSceneTiles()
            showAudio = StudioSceneAudio()
        }
        if migrateToSources() { save() }
    }

    /// §D40 — A SCENE SAVED BEFORE SOURCES EXISTED becomes source tiles, and
    /// nothing the host built is lost: its Camera and Call switches become
    /// whether it shows the first camera and the first call in the Sources
    /// list, and its two framings (the show's and its own) become theirs.
    /// §8.74 composites a migrated scene against the one-camera path and
    /// requires the same picture.
    private func migrateToSources() -> Bool {
        let cam = StudioSources.shared.primaryCameraID
        let call = StudioSources.shared.primaryCallID
        var changed = false
        if showTiles.bySource == nil {
            showTiles.bySource = StudioComposition.framings(from: showTiles, primaryCamera: cam,
                                                            primaryCall: call)
            changed = true
        }
        for i in scenes.indices {
            if var own = scenes[i].tiles, own.bySource == nil {
                own.bySource = StudioComposition.framings(from: own, primaryCamera: cam, primaryCall: call)
                scenes[i].tiles = own
                changed = true
            }
            if scenes[i].shown == nil {
                scenes[i].shown = StudioComposition.migrate(
                    cameraOn: scenes[i].camera, callOn: scenes[i].call,
                    tiles: StudioSceneTiles(), primaryCamera: cam, primaryCall: call).shown
                changed = true
            }
        }
        return changed
    }

    /// A source removed from the Sources list leaves every scene (§D40).
    func forget(_ id: String) {
        for i in scenes.indices {
            scenes[i].shown?.removeAll { $0 == id }
            scenes[i].tiles?.bySource?[id] = nil
        }
        showTiles.bySource?[id] = nil
        save()
    }

    var selected: StudioScene { scenes.first { $0.id == selectedID } ?? scenes[0] }
    private var selectedIndex: Int { scenes.firstIndex { $0.id == selectedID } ?? 0 }

    // MARK: Switching

    func select(_ id: UUID) {
        guard id != selectedID, scenes.contains(where: { $0.id == id }) else { return }
        capture()
        selectedID = id
        save()
        // THE SNAPSHOT MUST PRECEDE THE CHANGE. The first build fired the
        // transition in a Task and applied at once, so a frame of the NEW
        // scene rendered before the snapshot was taken and the dissolve ran
        // new-to-new — measured as a one-frame YAVG step 36.5 -> 60.2 on the
        // wire. So with an engine running, apply waits for the snapshot.
        if crossfade, StudioSession.shared.isLive {
            Task { @MainActor in
                await StudioSession.shared.beginTransition(seconds: 0.4)
                self.apply()
                self.logSwitch()
            }
        } else {
            apply()
            logSwitch()
        }
    }

    private func logSwitch() {
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
        if ProcessInfo.processInfo.environment["AW_STUDIO_SCENE_SELFTEST"] == "1" {
            Task { @MainActor in await self.selfTest() }
        }
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
        s.shown = c.shown
        // The pre-§D40 switches, still written: a scene set saved by this
        // version reads sensibly in the last one.
        s.camera = StudioSources.shared.primaryCameraID.map(c.shown.contains) ?? false
        s.call = StudioSources.shared.primaryCallID.map(c.shown.contains) ?? false
        let tiles = StudioSceneTiles(camera: c.framing, guests: c.guestFraming, bySource: c.framings)
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
        c.shown = s.shown ?? []
        c.framings = t.bySource ?? StudioComposition.framings(
            from: t, primaryCamera: StudioSources.shared.primaryCameraID,
            primaryCall: StudioSources.shared.primaryCallID)
        let a = s.useShowAudio ? showAudio : (s.audio ?? showAudio)
        c.filmGain = a.filmGain; c.micGain = a.micGain; c.callGain = a.callGain
        // THE HOST'S MUTES ARE NOT A SCENE'S TO CHANGE (launch audit B). A
        // host who pressed ⇧⌘M and then switched to a scene with its own mix
        // was live again without being told. The mic and the call describe
        // the PERSON; the film's mute is a real scene choice and stays one.
        c.filmMuted = a.filmMuted
        c.duckEnabled = a.duck
        c.showLowerThird = s.lowerThird; c.showFilmTitle = s.lowerTitle
        c.showFilmMeta = s.lowerMeta; c.showProvenance = s.lowerProvenance
        c.showChat = s.chat; c.chatSide = s.chatSide
        // The card last: it is the most visible thing a switch changes, and
        // an empty custom card is refused by the controls themselves (§D10).
        c.cardChoice = s.card
    }

    #if DEBUG
    /// §D31's inheritance, driven through the REAL controls and the real
    /// store — a harness of its own would test a copy. Restores the saved
    /// scenes exactly afterwards, because they are the owner's.
    func selfTest() async {
        let saved = UserDefaults.standard.data(forKey: Self.key)
        let before = (scenes, selectedID, showTiles, showAudio)
        let c = StudioControls.shared
        var fails = 0
        func check(_ name: String, _ ok: Bool) {
            awdiag("AWSCENETEST %@ %@", ok ? "ok  " : "FAIL", name)
            if !ok { fails += 1 }
        }
        guard scenes.count >= 4 else { awdiag("AWSCENETEST FAIL needs four scenes"); return }
        let a = scenes[1].id, b = scenes[3].id, d = scenes[2].id
        // Every scene inherits to start with.
        for i in scenes.indices { scenes[i].useShowAudio = true; scenes[i].useShowTiles = true }

        select(a); c.filmGain = 1.0
        select(b); setUseShowAudio(false)
        check("a scene's own audio starts from the show's", abs(c.filmGain - 1.0) < 0.001)
        c.filmGain = 0.3
        select(a)
        check("its own level does not leak into the show", abs(c.filmGain - 1.0) < 0.001)
        select(b)
        check("and comes back with the scene", abs(c.filmGain - 0.3) < 0.001)
        select(a); c.filmGain = 0.7
        select(d)
        check("an inheriting scene follows the show", abs(c.filmGain - 0.7) < 0.001)
        select(b)
        check("the scene with its own mix ignores the show", abs(c.filmGain - 0.3) < 0.001)
        setUseShowAudio(true)
        check("switching the toggle back returns to the show's", abs(c.filmGain - 0.7) < 0.001)

        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)
        select(b); setUseShowTiles(false)
        var f = c.framing; f.tile = box; c.framing = f
        select(a)
        check("its own tile does not move the show's", c.framing.tile != box)
        select(b)
        check("and the tile returns with the scene", c.framing.tile == box)

        let micBefore = c.micMuted
        select(b); setUseShowAudio(false); c.micMuted = true
        select(a)
        check("a muted microphone stays muted across a scene switch", c.micMuted)
        c.micMuted = false
        select(b)
        check("an unmuted microphone stays unmuted across a scene switch", !c.micMuted)
        c.micMuted = micBefore

        // §D40 — which sources a scene shows follows the scene, reaches the
        // engine, and never touches a mute.
        let sources = StudioSources.shared
        let cam = sources.primaryCameraID, call = sources.primaryCallID
        let callMutedBefore = c.callMuted
        if let cam, let call {
            select(a); c.shown = [call, cam]
            select(b); c.shown = [cam]
            c.callMuted = true
            select(a)
            check("the scene's sources come back with it", c.shown == [call, cam])
            check("a scene that hides the call does not unmute it", c.callMuted)
            check("the tiles are armed where the engine reads them",
                  StudioSession.shared.armedTiles?.map(\.source) == [call, cam])
            select(b)
            check("the other scene's sources come back with it", c.shown == [cam])
            check("and the session carries them",
                  StudioSession.shared.armedTiles?.map(\.source) == [cam])
            if let e = StudioSession.shared.engineForHarness {
                // THE VALUE WHERE IT LANDS (Decision 133): the engine, after
                // the hop, not the control.
                try? await Task.sleep(nanoseconds: 600_000_000)
                let t = await e.tiles
                check("the engine holds the scene's tiles", t?.map(\.source) == [cam])
            } else {
                awdiag("AWSCENETEST skip engine read (no engine running)")
            }
        } else {
            awdiag("AWSCENETEST skip sources (needs a camera and a call source)")
        }
        c.callMuted = callMutedBefore
        let decoded = try? JSONDecoder().decode(StudioScene.self, from: Data(
            #"{"id":"6F9619FF-8B86-D011-B42D-00CF4FC964FF","name":"Old","layout":"corner","card":"intermission","lowerThird":true,"lowerTitle":true,"lowerMeta":true,"lowerProvenance":true,"chat":true,"chatSide":"left","useShowTiles":true,"useShowAudio":true}"#.utf8))
        check("a scene saved before the switches still decodes",
              decoded?.camera == true && decoded?.call == false)

        // Restore: the owner's scenes, exactly.
        (scenes, selectedID, showTiles, showAudio) = before
        if let saved { UserDefaults.standard.set(saved, forKey: Self.key) }
        else { UserDefaults.standard.removeObject(forKey: Self.key) }
        apply()
        awdiag("AWSCENETEST RESULT %@ (%d failed)", fails == 0 ? "PASS" : "FAIL", fails)
    }
    #endif

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
        let s = Saved(scenes: scenes, selectedID: selectedID, showTiles: showTiles,
                      showAudio: showAudio, crossfade: crossfade)
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
            // AT THE MINIMUM WIDTH the fifth scene sat cut off behind "+", with
            // nothing saying more existed (seen at 1120x660, 2026-09-23). The
            // row fades at its trailing edge — over empty space when everything
            // fits, so it shows only when something is hidden — and the scene
            // on air is always scrolled into view, whichever way it was chosen.
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(store.scenes.enumerated()), id: \.element.id) { i, scene in
                            sceneButton(scene, index: i).id(scene.id)
                        }
                    }
                    .padding(.trailing, 20)
                }
                .mask(
                    HStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                    }
                )
                .onChange(of: store.selectedID) { _, id in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            Button { store.add() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("New scene from this one")
                .accessibilityLabel("New Scene")
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
                    Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
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
        // VoiceOver hears the scene's NAME and whether it is the one showing,
        // not "1 Starting soon button" with no state (launch audit B).
        .accessibilityLabel(scene.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(index < 9 ? "Command-\(index + 1)" : "")
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
            Toggle("Crossfade between scenes", isOn: $store.crossfade)
            Divider()
            Button("Rename “\(s.name)”…") { draft = s.name; renaming = s.id }
            Button("Delete “\(s.name)”", role: .destructive) { store.delete(s.id) }
                .disabled(store.scenes.count < 2)
        } label: {
            Label("Scene Settings", systemImage: "slider.horizontal.3")
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
/// Whether the Watch Together Studio is the frontmost window.
struct StudioWindowIsKeyKey: FocusedValueKey { typealias Value = Bool }
extension FocusedValues {
    var studioWindowIsKey: Bool? {
        get { self[StudioWindowIsKeyKey.self] }
        set { self[StudioWindowIsKeyKey.self] = newValue }
    }
}

struct SceneCommand: View {
    let index: Int
    @Bindable private var store = StudioScenes.shared
    /// ⌘1–9 switched scenes from ANY window — typing ⌘2 in a Creation Studio
    /// document crossfaded a live show and dropped a Twitch chapter (launch
    /// audit B). They act only while the Studio is in front.
    @FocusedValue(\.studioWindowIsKey) private var studioIsKey
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
            .disabled(studioIsKey != true)
        }
    }
}
#endif
