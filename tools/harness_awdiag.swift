// `awdiag` for the §8 harness cases, which compile Studio sources WITHOUT the
// app around them.
//
// The real one lives in `Networking/ResilientStreamLoader.swift` alongside
// `DiagFile`, and pulling that file into a harness would drag the whole
// playback stack in behind it. The Studio sources only need the symbol.
//
// WHY THIS EXISTS AT ALL: on 2026-09-19 the §8 Swift cases would not compile.
// Every failure was `cannot find 'awdiag' in scope` — two of them predating
// that day's work (StudioEngine has carried an `awdiag` call since the clocks
// diagnostic) and six more added the same day when the RTMP publisher was
// finally instrumented. The suite reports a case that does not build as FAIL,
// but nobody had run it, so the harness had quietly stopped covering the
// transport and the mixer. That is the second time this has happened —
// Decision 130 records "three §8 cases had not compiled for a session" — and
// the reason it keeps happening is that adding one log line to a shipping
// file silently breaks a build nothing else performs.
//
// So: every `swift_case` that compiles a Studio source now also compiles this,
// and the fix for the next `awdiag` added anywhere is nothing at all.
//
// It prints, rather than swallowing. A harness that hides the diagnostics of
// the code under test is throwing away the evidence it was run to collect.

import Foundation

func awdiag(_ format: String, _ args: CVarArg...) {
    FileHandle.standardError.write(
        ("[awdiag] " + String(format: format, arguments: args) + "\n").data(using: .utf8)!)
}
