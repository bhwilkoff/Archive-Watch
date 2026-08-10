// What does a machine with NO speech model actually say?
//
// The same failure appears on three environments — a GitHub macos-26 runner, the
// tvOS simulator, and the owner's Apple TV — while the two machines that already
// carry the model (this dev Mac, an iPhone) work perfectly. That difference is
// the whole problem, and it cannot be diagnosed on a machine where it works.
//
// So this asks the framework, in order, every question our caption path depends
// on, and prints the answer to each. Run it on a runner (`swiftc
// tools/probe_speech_assets.swift -o probe && ./probe`) to find out which step
// is actually refusing, instead of inferring it from the error three calls later.

import Foundation
import Speech

@main
struct Probe {
    static func main() async {
        guard #available(macOS 26, iOS 26, tvOS 26, *) else {
            print("PROBE: Speech 26 APIs unavailable"); exit(1)
        }

        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        print("supportedLocales      : \(supported.count) — "
              + supported.prefix(6).map { $0.identifier(.bcp47) }.joined(separator: ", "))
        print("installedLocales      : \(installed.count) — "
              + installed.prefix(6).map { $0.identifier(.bcp47) }.joined(separator: ", "))

        let want = Locale(identifier: "en-US")
        let resolved = await SpeechTranscriber.supportedLocale(equivalentTo: want)
        print("supportedLocale(en-US): \(resolved?.identifier(.bcp47) ?? "nil")")
        let locale = resolved ?? want

        print("maximumReservedLocales: \(AssetInventory.maximumReservedLocales)")
        print("reservedLocales       : \(await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) })")

        let transcriber = SpeechTranscriber(locale: locale,
                                            preset: .timeIndexedProgressiveTranscription)
        print("status(forModules)    : \(await AssetInventory.status(forModules: [transcriber]))")

        // THE question: does reserve() grant, refuse (returning false), or throw?
        // Our code discarded this Bool, so a refusal was read as success.
        do {
            let granted = try await AssetInventory.reserve(locale: locale)
            print("reserve(locale)       : granted=\(granted)")
        } catch {
            print("reserve(locale)       : THREW \(error)")
        }
        print("reservedLocales after : \(await AssetInventory.reservedLocales.map { $0.identifier(.bcp47) })")
        print("status after reserve  : \(await AssetInventory.status(forModules: [transcriber]))")

        // Now the call that actually fails in CI, in isolation.
        do {
            if let req = try await AssetInventory.assetInstallationRequest(
                supporting: [transcriber]) {
                print("installationRequest   : got one, downloading…")
                try await req.downloadAndInstall()
                print("downloadAndInstall    : OK")
            } else {
                print("installationRequest   : nil (framework says nothing to install)")
            }
        } catch {
            print("installationRequest   : THREW \(error)")
        }

        print("installedLocales after: \(await SpeechTranscriber.installedLocales.count)")
        let fmt = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        print("bestAvailableFormat   : \(fmt.map { "\($0.sampleRate)Hz ch\($0.channelCount)" } ?? "nil")")
    }
}
