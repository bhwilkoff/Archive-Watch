#if os(macOS)
import SwiftUI

// §D41 — A SHOW'S WHOLE SETUP, saved and loaded before Go Live.
//
// Owner, 2026-09-30: "Is there any way to get everything set up for a future
// show, including cameras, audio, etc. and then be able to load it into the
// studio again before pressing 'go live'?"
//
// Capture and load go through the stores every control already writes to —
// `StudioScenes` (the scene set, applied layout-first), `StudioSources`,
// `StudioControls`, `StudioOutputSettings`, the versions store — so a loaded
// value lands where a hand-set one would (Decision 133).

@MainActor
@Observable
final class StudioMacSetups: StudioSetupTarget {
    static let shared = StudioMacSetups()

    private(set) var saved: [StudioNamedSetup] = StudioSetupStore.load()
    /// One line after a load or save that could not do all it was asked.
    var note: String?

    /// The fingerprint of the setup last loaded or saved on this Mac. A load
    /// asks first only when what is set up now differs from it.
    private static let baselineKey = "studio.setupBaseline"
    private var baseline: String? {
        get { UserDefaults.standard.string(forKey: Self.baselineKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.baselineKey) }
    }

    /// What `applyFilm` takes the film through, for the length of one load.
    @ObservationIgnored private var context: (store: AppStore, router: AppRouter)?

    private init() {}

    // MARK: Capture

    func capture() -> StudioSetup { StudioSetup.capture(from: self) }

    func fingerprint(_ s: StudioSetup) -> String {
        var w = s
        w.scenes = StudioScenes.withoutSelection(s.scenes)
        return StudioSetup.fingerprint(w)
    }

    /// True when loading would throw away work that was never saved.
    var needsConfirmation: Bool { baseline != fingerprint(capture()) }

    /// Captures the setup now and marks it as saved.
    func captureForSaving() -> StudioSetup {
        let s = capture()
        baseline = fingerprint(s)
        return s
    }

    func saveNamed(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        StudioSetupStore.save(name: n, setup: captureForSaving())
        saved = StudioSetupStore.load()
        note = nil
        awdiag("AWSETUP saved named setup (%d kept)", saved.count)
    }

    func saveToShow(_ show: StudioScheduledShow) {
        StudioSchedule.setSetup(captureForSaving(), broadcastID: show.broadcastID)
        StudioMacSchedule.shared.reload()
        note = nil
        awdiag("AWSETUP saved setup to show %@", show.broadcastID)
    }

    func delete(_ id: UUID) {
        StudioSetupStore.remove(id: id)
        saved = StudioSetupStore.load()
    }

    // MARK: Load

    /// Why a load cannot happen now, or nil.
    var loadRefusal: String? {
        StudioSession.shared.isLive ? "End the preview to load a setup." : nil
    }

    /// Replaces the Studio's setup with `setup`. With no setup (a show
    /// scheduled before §D41), the film and copy only. `copy` overrides the
    /// setup's: a show plays the copy that was announced. Never goes live.
    @discardableResult
    func load(_ setup: StudioSetup?, film: String?, copy: String?,
              store: AppStore, router: AppRouter) -> Bool {
        if let why = loadRefusal { note = why; return false }
        note = nil
        context = (store, router)
        defer { context = nil }
        guard var s = setup else {
            applyFilm(film, copy: copy)
            return note == nil
        }
        if let film { s.archiveID = film }
        if let copy { s.copy = copy }
        StudioSetup.apply(s, to: self)
        baseline = fingerprint(capture())
        awdiag("AWSETUP loaded film=%@ sources=%d", s.archiveID ?? "none", s.sources.count)
        return note == nil
    }

    func loadShow(_ show: StudioScheduledShow, store: AppStore, router: AppRouter) {
        guard load(show.setup, film: show.archiveID, copy: show.copy, store: store, router: router)
        else { return }
        let mac = StudioMacShow.shared
        mac.platform = .youtube
        mac.connectWithKey = false
        StudioMacSchedule.shared.goLiveRequest = show.broadcastID
    }

    // MARK: StudioSetupTarget

    var setupFilm: String? { StudioMacShow.shared.film?.archiveID }

    func setupCopy() -> String? {
        guard let film = StudioMacShow.shared.film else { return nil }
        return ArchiveVersions.copyPath(for: film.archiveID, default: film.videoURLParsed)
    }

    func setupScenes() -> Data { StudioScenes.shared.exportSet() }

    func setupSources() -> [StudioSetup.Source] {
        let sources = StudioSources.shared
        return sources.list.map { ref in
            switch ref.kind {
            case .camera:
                return .init(id: ref.id, kind: .camera, deviceID: ref.deviceID,
                             name: sources.cameraName(ref))
            case .call:
                return .init(id: ref.id, kind: .call, name: ref.appName)
            }
        }
    }

    var setupMix: StudioSetup.Mix {
        let c = StudioControls.shared
        return .init(microphoneID: StudioDevices.chosenMicrophoneID,
                     micGateEnabled: c.micGateEnabled, micGateThreshold: c.micGateThreshold)
    }

    var setupOnScreen: StudioSetup.OnScreen {
        let c = StudioControls.shared
        return .init(customCard: c.customCardLines.map { .init(text: $0.text, rank: $0.rank.rawValue) },
                     chatHideCommands: c.chatHideCommands, chatHideLinks: c.chatHideLinks,
                     chatBlocked: c.chatBlocked)
    }

    var setupOutput: StudioSetup.Output {
        .init(width: StudioOutputSettings.width, height: StudioOutputSettings.height,
              frameRate: StudioOutputSettings.frameRate, bitrateKbps: StudioOutputSettings.bitrateKbps)
    }

    func applyFilm(_ archiveID: String?, copy: String?) {
        guard let archiveID else { return }
        let show = StudioMacShow.shared
        let current = show.film?.archiveID == archiveID ? show.film : nil
        guard let item = current ?? context?.store.db?.item(archiveID) else {
            note = "This film is not in the catalog on this Mac."
            return
        }
        let before = ArchiveVersions.copyPath(for: archiveID, default: item.videoURLParsed)
        // THE COPY BEFORE THE FILM, so the player built for it plays that file.
        if let copy { ArchiveVersions.chooseCopy(copy, for: archiveID, defaultURL: item.videoURLParsed) }
        if current == nil {
            if let router = context?.router { show.take(item, from: router) }
        } else if ArchiveVersions.copyPath(for: archiveID, default: item.videoURLParsed) != before {
            show.reloadCopy()
        }
    }

    func applySources(_ list: [StudioSetup.Source]) {
        StudioSources.shared.replace(with: list.map {
            StudioSourceRef(id: $0.id, kind: $0.kind == .camera ? .camera : .call,
                            deviceID: $0.kind == .camera ? $0.deviceID : nil,
                            appName: $0.kind == .call ? $0.name : nil)
        })
    }

    func applyScenes(_ data: Data) {
        if !StudioScenes.shared.importSet(data) { note = "This setup's scenes could not be read." }
    }

    func applyMix(_ mix: StudioSetup.Mix) {
        if StudioDevices.chosenMicrophoneID != mix.microphoneID {
            StudioDevices.chosenMicrophoneID = mix.microphoneID
        }
        let c = StudioControls.shared
        c.micGateEnabled = mix.micGateEnabled
        c.micGateThreshold = mix.micGateThreshold
    }

    func applyOnScreen(_ o: StudioSetup.OnScreen) {
        let c = StudioControls.shared
        var lines = c.customCardLines
        for i in lines.indices {
            let saved = i < o.customCard.count ? o.customCard[i] : nil
            lines[i].text = saved?.text ?? ""
            if let r = saved.flatMap({ StudioOverlay.CardLine.Rank(rawValue: $0.rank) }) { lines[i].rank = r }
        }
        if lines != c.customCardLines { c.customCardLines = lines }
        c.chatHideCommands = o.chatHideCommands
        c.chatHideLinks = o.chatHideLinks
        c.chatBlocked = o.chatBlocked
    }

    func applyOutput(_ o: StudioSetup.Output) {
        StudioOutputSettings.width = o.width
        StudioOutputSettings.height = o.height
        StudioOutputSettings.frameRate = o.frameRate
        StudioOutputSettings.bitrateKbps = o.bitrateKbps
    }

    #if DEBUG
    // MARK: - The §D41 self-test door

    /// `AW_STUDIO_SETUP_SELFTEST=1`, or `AW_STUDIO_SETUP_PHASE=save|load` for a
    /// relaunch. Runs through the SAME capture, save and load the buttons call;
    /// never schedules, never goes live, never calls YouTube. Lines are
    /// `AWSETUPTEST …` through `awdiag`.
    func runDoorIfAsked(store: AppStore, router: AppRouter) async {
        let env = ProcessInfo.processInfo.environment
        let phase = env["AW_STUDIO_SETUP_PHASE"]
        guard env["AW_STUDIO_SETUP_SELFTEST"] == "1" || phase != nil else { return }
        guard !Self.doorRan else { return }
        Self.doorRan = true
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aw-setup-selftest.json")
        awdiag("AWSETUPTEST start phase=%@ expectFile=%@", phase ?? "full", tmp.path)
        for _ in 0..<60 where store.db == nil { try? await Task.sleep(for: .seconds(1)) }
        if phase != "load" {
            for _ in 0..<90 where StudioMacShow.shared.film == nil { try? await Task.sleep(for: .seconds(1)) }
            guard StudioMacShow.shared.film != nil else {
                awdiag("AWSETUPTEST FAIL no film loaded in the Studio"); return
            }
        }
        if let why = loadRefusal { awdiag("AWSETUPTEST FAIL refused: %@", why); return }
        switch phase {
        case "save": selfTestSave(tmp)
        case "load": await selfTestLoad(tmp, store: store, router: router)
        default: await selfTestFull(store: store, router: router)
        }
    }
    private static var doorRan = false

    private struct Expect: Codable {
        var setup: StudioSetup
        var fingerprint: String
        var choiceKey: String?
        var savedSetups: Data?
        /// The baseline BEFORE the save phase set one, so the relaunch phase
        /// can put the owner's own value back rather than the test's.
        var baselineBefore: String?
    }

    @ObservationIgnored private var pass = 0
    @ObservationIgnored private var fail = 0
    private func check(_ name: String, _ ok: Bool) {
        awdiag("AWSETUPTEST %@ %@", ok ? "ok" : "FAIL", name)
        if ok { pass += 1 } else { fail += 1 }
    }

    private func compare(_ got: StudioSetup, _ want: StudioSetup) {
        let diffs = StudioSetup.differences(got, want)
        for part in ["film", "copy", "scenes", "sources", "mix", "onScreen", "output"] {
            check(part, !diffs.contains(part))
        }
        if diffs.contains("scenes") {
            for d in StudioScenes.differences(got.scenes, want.scenes) { awdiag("AWSETUPTEST FAIL %@", d) }
        }
        // WHERE THE VALUES LAND (Decision 133): the session the engine reads.
        let scenes = StudioScenes.shared
        check("layout armed at the session", StudioSession.shared.armedLayout == scenes.selected.layout)
        check("tiles armed at the session",
              StudioSession.shared.armedTiles?.map(\.source) == StudioControls.shared.currentTiles.map(\.source))
        if let film = StudioMacShow.shared.film, let def = film.videoURLParsed {
            let path = StudioRoomCopy.path(from: ArchiveVersions.preferredURL(for: film.archiveID, default: def))
            awdiag("AWSETUPTEST copy %@", path ?? "none")
            check("preferredURL is the setup's copy", path == want.copy)
        }
    }

    /// Changes one of everything, through the controls a host uses.
    private func mutate() async {
        let c = StudioControls.shared
        let scenes = StudioScenes.shared
        if let other = scenes.scenes.first(where: { $0.id != scenes.selectedID }) { scenes.select(other.id) }
        c.layout = c.layout == .side ? .corner : .side
        c.cardChoice = c.cardChoice == .intermission ? .none : .intermission
        if let first = StudioSources.shared.list.first {
            c.setShown(first.id, !c.isShown(first.id))
        }
        if let cam = StudioSources.shared.primaryCameraID {
            var f = c.framings[cam] ?? StudioCameraFraming()
            f.zoom = f.zoom > 1.2 ? 1.0 : 1.5
            c.framings[cam] = f
        } else {
            awdiag("AWSETUPTEST skip crop (no camera source)")
        }
        c.filmGain = c.filmGain > 0.5 ? 0.37 : 0.9
        c.callGain = c.callGain > 0.5 ? 0.41 : 0.9
        StudioOutputSettings.bitrateKbps = StudioOutputSettings.bitrateKbps == 3000 ? 4000 : 3000
        if let film = StudioMacShow.shared.film {
            let current = ArchiveVersions.copyPath(for: film.archiveID, default: film.videoURLParsed)
            let versions = await ArchiveVersions.list(itemID: film.archiveID)
            if let v = versions.first(where: {
                StudioSetup.copyPath(choiceKey: $0.choiceKey, archiveID: film.archiveID) != current }) {
                ArchiveVersions.choose(v, for: film.archiveID)
                StudioMacShow.shared.reloadCopy()
                awdiag("AWSETUPTEST mutated copy to %@",
                       StudioSetup.copyPath(choiceKey: v.choiceKey, archiveID: film.archiveID))
            } else {
                awdiag("AWSETUPTEST skip copy (the film has one copy)")
            }
        }
    }

    private func selfTestFull(store: AppStore, router: AppRouter) async {
        let c = StudioControls.shared
        let micMuted = c.micMuted, callMuted = c.callMuted
        let filmID = StudioMacShow.shared.film?.archiveID
        let rawChoice = filmID.flatMap { ArchiveVersions.chosenName(for: $0) }
        let rawSaved = UserDefaults.standard.data(forKey: StudioSetupStore.defaultsKey)
        let rawBaseline = baseline

        // (a) the owner's setup, through the real capture, saved by name.
        saveNamed("selftest")
        let a = capture()
        guard let entry = saved.first(where: { $0.name == "selftest" }) else {
            awdiag("AWSETUPTEST FAIL the named setup was not saved"); return
        }
        check("a saved setup round-trips through the store", entry.setup == a)
        check("a just-saved setup does not ask", !needsConfirmation)

        // (b) change one of everything.
        await mutate()
        let mutated = capture()
        let changed = StudioSetup.differences(mutated, a)
        awdiag("AWSETUPTEST mutated parts=%@", changed.joined(separator: ","))
        check("the mutation changed the setup", !changed.isEmpty)
        check("unsaved work asks before it is replaced", needsConfirmation)

        // (c) load it back through the function Load calls.
        let loaded = load(entry.setup, film: nil, copy: nil, store: store, router: router)
        check("load ran", loaded)
        try? await Task.sleep(for: .milliseconds(600))

        // (d) field by field.
        compare(capture(), a)
        check("a just-loaded setup does not ask", !needsConfirmation)
        check("the microphone mute is the host's", c.micMuted == micMuted)
        check("the call mute is the host's", c.callMuted == callMuted)
        awdiag("AWSETUPTEST done pass=%d fail=%d", pass, fail)

        // (e) the owner's setup, exactly as it was.
        delete(entry.id)
        load(a, film: nil, copy: nil, store: store, router: router)
        if let filmID { ArchiveVersions.setChoiceKey(rawChoice, for: filmID) }
        if let rawSaved { UserDefaults.standard.set(rawSaved, forKey: StudioSetupStore.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: StudioSetupStore.defaultsKey) }
        saved = StudioSetupStore.load()
        baseline = rawBaseline
        let restored = StudioSetup.differences(capture(), a)
        let choiceBack = filmID.map { ArchiveVersions.chosenName(for: $0) == rawChoice } ?? true
        let ok = restored.isEmpty && choiceBack && !saved.contains { $0.name == "selftest" }
            && c.micMuted == micMuted && c.callMuted == callMuted
        awdiag("AWSETUPTEST restored %@%@", ok ? "ok" : "FAIL",
               ok ? "" : " " + restored.joined(separator: ",") + (choiceBack ? "" : ",choice"))
    }

    private func selfTestSave(_ tmp: URL) {
        let filmID = StudioMacShow.shared.film?.archiveID
        let rawSaved = UserDefaults.standard.data(forKey: StudioSetupStore.defaultsKey)
        let baselineBefore = UserDefaults.standard.string(forKey: Self.baselineKey)
        saveNamed("selftest")
        let a = capture()
        let e = Expect(setup: a, fingerprint: fingerprint(a),
                       choiceKey: filmID.flatMap { ArchiveVersions.chosenName(for: $0) },
                       savedSetups: rawSaved, baselineBefore: baselineBefore)
        do {
            try JSONEncoder().encode(e).write(to: tmp, options: .atomic)
            awdiag("AWSETUPTEST saved fingerprint=%@ to %@", e.fingerprint, tmp.path)
            awdiag("AWSETUPTEST done pass=1 fail=0 (phase save — relaunch with AW_STUDIO_SETUP_PHASE=load)")
        } catch {
            awdiag("AWSETUPTEST FAIL could not write %@", tmp.path)
        }
    }

    private func selfTestLoad(_ tmp: URL, store: AppStore, router: AppRouter) async {
        guard let data = try? Data(contentsOf: tmp),
              let e = try? JSONDecoder().decode(Expect.self, from: data) else {
            awdiag("AWSETUPTEST FAIL no saved expectation at %@ — run phase save first", tmp.path); return
        }
        let c = StudioControls.shared
        let micMuted = c.micMuted, callMuted = c.callMuted
        guard let entry = saved.first(where: { $0.name == "selftest" }) else {
            awdiag("AWSETUPTEST FAIL the named setup did not survive the relaunch"); return
        }
        check("the named setup survived the relaunch", entry.setup == e.setup)
        // The film open at THIS launch is not the setup's, and mutate() picks a
        // copy of it: record its choice and the baseline so both go back
        // exactly (the first owner-Mac run left The Man Who Laughs on another
        // copy, 2026-09-30).
        let launchFilm = StudioMacShow.shared.film?.archiveID
        let launchChoice = launchFilm.flatMap { ArchiveVersions.chosenName(for: $0) }
        let baselineBefore = UserDefaults.standard.object(forKey: Self.baselineKey)
        await mutate()
        load(entry.setup, film: nil, copy: nil, store: store, router: router)
        try? await Task.sleep(for: .seconds(2))
        let got = capture()
        compare(got, e.setup)
        check("fingerprint", fingerprint(got) == e.fingerprint)
        check("the microphone mute is the host's", c.micMuted == micMuted)
        check("the call mute is the host's", c.callMuted == callMuted)
        awdiag("AWSETUPTEST done pass=%d fail=%d", pass, fail)

        // The owner's setup IS the saved one; put back the rest exactly.
        delete(entry.id)
        if let film = e.setup.archiveID { ArchiveVersions.setChoiceKey(e.choiceKey, for: film) }
        if let launchFilm, launchFilm != e.setup.archiveID {
            ArchiveVersions.setChoiceKey(launchChoice, for: launchFilm)
        }
        // The save phase's own baseline is not the owner's: restore the value
        // recorded before it (absent in an expectation from an older build).
        let ownerBaseline = e.baselineBefore ?? (baselineBefore as? String)
        if let ownerBaseline { UserDefaults.standard.set(ownerBaseline, forKey: Self.baselineKey) }
        else { UserDefaults.standard.removeObject(forKey: Self.baselineKey) }
        if let raw = e.savedSetups { UserDefaults.standard.set(raw, forKey: StudioSetupStore.defaultsKey) }
        else { UserDefaults.standard.removeObject(forKey: StudioSetupStore.defaultsKey) }
        saved = StudioSetupStore.load()
        try? FileManager.default.removeItem(at: tmp)
        let restored = StudioSetup.differences(capture(), e.setup)
        let choiceBack = (e.setup.archiveID.map { ArchiveVersions.chosenName(for: $0) == e.choiceKey } ?? true)
            && (launchFilm.map { $0 == e.setup.archiveID || ArchiveVersions.chosenName(for: $0) == launchChoice } ?? true)
        let ok = restored.isEmpty && choiceBack && !saved.contains { $0.name == "selftest" }
        awdiag("AWSETUPTEST restored %@%@", ok ? "ok" : "FAIL",
               ok ? "" : " " + restored.joined(separator: ",") + (choiceBack ? "" : ",choice"))
    }
    #endif
}

// MARK: - Save Setup…

struct StudioSaveSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(suggested: String) { _name = State(initialValue: suggested) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save Setup").font(.headline)
            TextField("Name", text: $name)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 360)
    }

    private func save() {
        StudioMacSetups.shared.saveNamed(name)
        dismiss()
    }
}
#endif
