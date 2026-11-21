// Stand-ins for the app symbols LocalMediaServer.swift reaches, so
// tools/test_audio_sync_offset.swift can run the REAL server outside the app.
import Foundation

func awdiag(_ format: String, _ args: CVarArg...) {
    if ProcessInfo.processInfo.environment["AW_SYNC_VERBOSE"] == "1" {
        print(String(format: format, arguments: args))
    }
}

enum PlaybackDiag { static let enabled = false }

final class FilmAudioBridge: @unchecked Sendable {
    static let shared = FilmAudioBridge()
    func deliver(_ frames: [Data], firstSample: Int, sampleRate: Int) {}
}
