// §8.75 — a show's whole setup, saved and loaded (macOS-DESIGN §D41).
//
// Compiles the REAL StudioSetup, StudioSchedule, ArchiveVersions and output
// settings (Decision 119). The Studio's stores are macOS UI types, so capture
// and apply are driven through `StudioSetupTarget` with an in-memory model
// whose scene part behaves like the real composition: a scene's tile that
// names a source the Sources list does not hold is DROPPED. That is what makes
// the apply ORDER testable, not merely asserted.
//
//   bash tools/test_studio_all.sh   (case "8.75 saved setups")
//
// CONTROLS: an apply that drops the sources must be caught by `differences`
// AND lose the scene's tiles; an apply in the wrong order (scenes before
// sources) must lose them too. A detector that cannot see either would pass
// the real apply for the wrong reason.

import Foundation

@main
struct SetupTest {
    nonisolated(unsafe) static var pass = 0
    nonisolated(unsafe) static var fail = 0

    static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if ok { pass += 1; print("  PASS  \(name)") }
        else  { fail += 1; print("  FAIL  \(name)\(detail.isEmpty ? "" : " — \(detail)")") }
    }

    /// The scene part as the model keeps it: which sources each scene shows.
    struct FakeScenes: Codable, Equatable {
        var selected: String
        var shown: [String: [String]]
    }

    @MainActor
    final class Model: StudioSetupTarget {
        var film: String?
        var choice: String?            // the versions store's key
        var scenes = FakeScenes(selected: "Film", shown: [:])
        var sources: [StudioSetup.Source] = []
        var mix = StudioSetup.Mix()
        var onScreen = StudioSetup.OnScreen()
        var order: [String] = []

        var setupFilm: String? { film }
        func setupCopy() -> String? {
            guard let film else { return nil }
            return choice.map { StudioSetup.copyPath(choiceKey: $0, archiveID: film) } ?? "\(film)/default.mp4"
        }
        func setupScenes() -> Data { StudioSetup.canonical(scenes)! }
        func setupSources() -> [StudioSetup.Source] { sources }
        var setupMix: StudioSetup.Mix { mix }
        var setupOnScreen: StudioSetup.OnScreen { onScreen }
        var setupOutput: StudioSetup.Output {
            .init(width: StudioOutputSettings.width, height: StudioOutputSettings.height,
                  frameRate: StudioOutputSettings.frameRate, bitrateKbps: StudioOutputSettings.bitrateKbps)
        }

        func applyFilm(_ archiveID: String?, copy: String?) {
            order.append("film")
            guard let archiveID else { return }
            if let copy {
                choice = copy == "\(archiveID)/default.mp4" ? nil
                    : StudioSetup.choiceKey(forCopy: copy, archiveID: archiveID)
            }
            film = archiveID
        }
        func applySources(_ s: [StudioSetup.Source]) { order.append("sources"); sources = s }
        func applyScenes(_ data: Data) {
            order.append("scenes")
            guard var s = try? JSONDecoder().decode(FakeScenes.self, from: data) else { return }
            // AS THE REAL COMPOSITION DOES: an id the Sources list does not hold
            // has nothing to draw, and the scene loses it.
            let known = Set(sources.map(\.id))
            s.shown = s.shown.mapValues { $0.filter(known.contains) }
            scenes = s
        }
        func applyMix(_ m: StudioSetup.Mix) { order.append("mix"); mix = m }
        func applyOnScreen(_ o: StudioSetup.OnScreen) { order.append("onScreen"); onScreen = o }
        func applyOutput(_ o: StudioSetup.Output) {
            order.append("output")
            StudioOutputSettings.width = o.width
            StudioOutputSettings.height = o.height
            StudioOutputSettings.frameRate = o.frameRate
            StudioOutputSettings.bitrateKbps = o.bitrateKbps
        }
    }

    static func sample() -> StudioSetup {
        let scenes = FakeScenes(selected: "Discussion",
                                shown: ["Film": ["camera-A"], "Discussion": ["call-B", "camera-A", "camera-C"]])
        return StudioSetup(
            archiveID: "TheScarecrow1920",
            copy: "the-scarecrow/The Scarecrow (1920) sound.mp4",
            scenes: StudioSetup.canonical(scenes)!,
            sources: [.init(id: "camera-A", kind: .camera, deviceID: "0x1420000005ac8600", name: "FaceTime HD Camera"),
                      .init(id: "call-B", kind: .call, name: "zoom.us"),
                      .init(id: "camera-C", kind: .camera, deviceID: nil, name: "System default camera")],
            mix: .init(microphoneID: "BuiltInMicrophoneDevice", micGateEnabled: true, micGateThreshold: 0.05),
            onScreen: .init(customCard: [.init(text: "Back in five", rank: "display"),
                                         .init(text: "", rank: "body")],
                            chatHideCommands: false, chatHideLinks: true, chatBlocked: "spoiler"),
            output: .init(width: 1280, height: 720, frameRate: 24, bitrateKbps: 3000))
    }

    @MainActor
    static func run() {
        let outBefore = (StudioOutputSettings.width, StudioOutputSettings.height,
                         StudioOutputSettings.frameRate, StudioOutputSettings.bitrateKbps)
        defer {
            StudioOutputSettings.width = outBefore.0; StudioOutputSettings.height = outBefore.1
            StudioOutputSettings.frameRate = outBefore.2; StudioOutputSettings.bitrateKbps = outBefore.3
        }
        let s = sample()

        print("— the record")
        let json = try! JSONEncoder().encode(s)
        let back = try? JSONDecoder().decode(StudioSetup.self, from: json)
        check("a whole setup round-trips through JSON", back == s)
        check("and compares equal part by part", back.map { StudioSetup.differences($0, s).isEmpty } == true)

        let oldShow = #"{"broadcastID":"b1","streamID":"s1","archiveID":"Nosferatu","copy":"Nosferatu/n.mp4","title":"Nosferatu","description":"d","start":780000000,"privacy":"unlisted"}"#
        let old = try? JSONDecoder().decode(StudioScheduledShow.self, from: Data(oldShow.utf8))
        check("a show scheduled before §D41 still decodes", old?.broadcastID == "b1")
        check("and carries no setup", old != nil && old?.setup == nil)
        if var withSetup = old {
            withSetup.setup = s
            let d = try! JSONEncoder().encode(withSetup)
            check("a show with a setup round-trips", (try? JSONDecoder().decode(StudioScheduledShow.self, from: d)) == withSetup)
        }

        print("— the copy")
        check("own item's file is the bare name",
              StudioSetup.choiceKey(forCopy: "Nosferatu/dir/n.mp4", archiveID: "Nosferatu") == "dir/n.mp4")
        check("a merged upload's file is @item:name",
              StudioSetup.choiceKey(forCopy: "the-scarecrow/s.mp4", archiveID: "TheScarecrow1920") == "@the-scarecrow:s.mp4")
        check("the key reads back as the path, merged",
              StudioSetup.copyPath(choiceKey: "@the-scarecrow:s.mp4", archiveID: "TheScarecrow1920") == "the-scarecrow/s.mp4")
        check("the key reads back as the path, own",
              StudioSetup.copyPath(choiceKey: "dir/n.mp4", archiveID: "Nosferatu") == "Nosferatu/dir/n.mp4")
        check("a path with no file is refused", StudioSetup.choiceKey(forCopy: "Nosferatu", archiveID: "Nosferatu") == nil)

        // Through the REAL versions store and the URL every player asks for.
        let title = "awSetupHarnessTitle"
        let def = URL(string: "https://archive.org/download/\(title)/default.mp4")!
        let rawBefore = ArchiveVersions.chosenName(for: title)
        for copy in ["the-scarecrow/The Scarecrow (1920) sound.mp4", "\(title)/other file.mp4"] {
            ArchiveVersions.chooseCopy(copy, for: title, defaultURL: def)
            let url = ArchiveVersions.preferredURL(for: title, default: def)
            check("preferredURL plays the setup's copy: \(copy)", StudioRoomCopy.path(from: url) == copy,
                  url.absoluteString)
            check("and copyPath reads it back", ArchiveVersions.copyPath(for: title, default: def) == copy)
        }
        ArchiveVersions.chooseCopy("\(title)/default.mp4", for: title, defaultURL: def)
        check("the default copy clears the choice rather than pinning it",
              ArchiveVersions.chosenName(for: title) == nil)
        ArchiveVersions.setChoiceKey(rawBefore, for: title)

        print("— apply, then capture")
        let m = Model()
        StudioSetup.apply(s, to: m)
        let got = StudioSetup.capture(from: m)
        let diffs = StudioSetup.differences(got, s)
        check("apply-then-capture equals the original", diffs.isEmpty, diffs.joined(separator: ","))
        for part in ["film", "copy", "scenes", "sources", "mix", "onScreen", "output"] {
            check("  \(part)", !diffs.contains(part))
        }
        check("the order is film, sources, scenes, mix, onScreen, output",
              m.order == ["film", "sources", "scenes", "mix", "onScreen", "output"], m.order.joined(separator: ","))

        print("— controls")
        let dropped = Model()
        StudioSetup.apply(s, to: dropped, parts: StudioSetup.Parts.all.subtracting(.sources))
        let dd = StudioSetup.differences(StudioSetup.capture(from: dropped), s)
        check("CONTROL: an apply that drops the sources is caught", dd.contains("sources"), dd.joined(separator: ","))
        check("CONTROL: and the scene lost its tiles with them", dd.contains("scenes"))

        let wrong = Model()
        wrong.applyFilm(s.archiveID, copy: s.copy)
        wrong.applyScenes(s.scenes)            // before its sources exist
        wrong.applySources(s.sources)
        wrong.applyMix(s.mix); wrong.applyOnScreen(s.onScreen); wrong.applyOutput(s.output)
        let wd = StudioSetup.differences(StudioSetup.capture(from: wrong), s)
        check("CONTROL: scenes before sources lose the tiles", wd == ["scenes"], wd.joined(separator: ","))

        print("— the fingerprint")
        let f = StudioSetup.fingerprint(s)
        var renamed = s; renamed.sources[0].name = "Camera not connected"
        check("a device's NAME is not work", StudioSetup.fingerprint(renamed) == f)
        var otherFilm = s; otherFilm.archiveID = "Nosferatu"; otherFilm.copy = "Nosferatu/n.mp4"
        check("the film and copy are not work", StudioSetup.fingerprint(otherFilm) == f)
        var louder = s; louder.output.bitrateKbps = 6000
        check("an output change is", StudioSetup.fingerprint(louder) != f)
        var lessCamera = s; lessCamera.sources.removeLast()
        check("a removed source is", StudioSetup.fingerprint(lessCamera) != f)
        var otherDevice = s; otherDevice.sources[0].deviceID = "elsewhere"
        check("a camera's device is", StudioSetup.fingerprint(otherDevice) != f)
        check("it is stable", StudioSetup.fingerprint(try! JSONDecoder().decode(StudioSetup.self, from: json)) == f)

        print("— named setups")
        let suite = "aw.studio.setup.harness"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let one = StudioSetupStore.save(name: "Noir night", setup: s, defaults: d)
        StudioSetupStore.save(name: "Silent Sunday", setup: otherFilm, defaults: d)
        StudioSetupStore.save(name: "noir NIGHT", setup: louder, defaults: d)
        let all = StudioSetupStore.load(from: d)
        check("saving under a used name replaces it", all.count == 2, "\(all.count)")
        check("keeping its identity", all.first { $0.id == one.id }?.setup == louder)
        StudioSetupStore.remove(id: one.id, defaults: d)
        check("delete removes one", StudioSetupStore.load(from: d).map(\.name) == ["Silent Sunday"])
        d.removePersistentDomain(forName: suite)
    }

    static func main() async {
        await MainActor.run { run() }
        print("pass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }
}
