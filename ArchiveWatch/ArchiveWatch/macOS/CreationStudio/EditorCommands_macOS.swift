#if os(macOS)
import SwiftUI

// The Creation Studio's menus (docs/macOS-DESIGN.md Rule 7d, §B14).
//
// Rule 7d asked for "one coherent keyboard scheme wired to the menu bar for
// discoverability" and the editor had NONE: split, markers, zoom, export, text,
// music, voiceover and supercut were toolbar buttons, and the navigation keys
// existed only while the timeline was first responder. Owner, 2026-09-27: "make
// sure that all features that should have menu items (macOS specific need),
// that they are well represented in the menu structure."
//
// Every item acts on the editor window in front (`focusedSceneValue`) and is
// disabled otherwise — so ⌘D, ⌘←/→ and ⌘↑/↓ mean the editor's commands here and
// the Film / Controls commands in a browsing window, never both at once. No
// item takes a bare key: a letter or an arrow bound in the menu bar would be
// taken from the inspector's text fields. The timeline's own bare keys (B, M,
// J/K/L, arrows) still work while it has focus.

struct EditorCommandContext {
    let model: EditorModel
    let inspectorShown: Bool
    let exportBusy: Bool
    let addClip: () -> Void
    let addMusic: () -> Void
    let voiceover: () -> Void
    let supercut: () -> Void
    let export: () -> Void
    let publish: () -> Void
    let toggleInspector: () -> Void
}
struct EditorCommandContextKey: FocusedValueKey { typealias Value = EditorCommandContext }
extension FocusedValues {
    var editorCommands: EditorCommandContext? {
        get { self[EditorCommandContextKey.self] }
        set { self[EditorCommandContextKey.self] = newValue }
    }
}

/// File ▸ Add Clip / Add Music / Export / Publish, beside Save.
struct EditorFileCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor

    private var hasClips: Bool { !(editor?.model.project.timeline.clips.isEmpty ?? true) }

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Add Clip from a Film…") { editor?.addClip() }
                .keyboardShortcut("i", modifiers: .command)
                .disabled(editor == nil)
            Button("Add Music…") { editor?.addMusic() }
                .disabled(editor == nil)
            Divider()
            Button("Export Movie…") { editor?.export() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(editor == nil || !hasClips || editor?.exportBusy == true)
            Button("Publish…") { editor?.publish() }
                .disabled(editor == nil || !hasClips || editor?.exportBusy == true)
        }
    }
}

/// Clip: what is done TO the timeline.
struct EditorClipCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor

    private var model: EditorModel? { editor?.model }
    private var hasClips: Bool { !(model?.project.timeline.clips.isEmpty ?? true) }
    private var hasSelection: Bool { !(model?.selectedIDs.isEmpty ?? true) }

    var body: some Commands {
        CommandMenu("Clip") {
            Button("Split at Playhead") { model?.splitAtPlayhead() }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!hasClips)
            Button("Duplicate") { if let id = model?.selectedClipID { model?.duplicateClip(id) } }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(model?.selectedClipID == nil)
            Button(model?.selectedClip?.audioVolume == 0 ? "Unmute Audio" : "Mute Audio") {
                model?.toggleMuteSelected()
            }
            .disabled(model?.selectedClipID == nil)
            Button("Clear Fades") {
                guard let id = model?.selectedClipID else { return }
                model?.checkpoint()
                model?.setClipFade(id, fadeIn: 0, fadeOut: 0)
            }
            .disabled(model?.selectedClip.map { $0.fadeInSeconds == 0 && $0.fadeOutSeconds == 0 } ?? true)
            Button("Delete") { model?.deleteSelection() }
                .disabled(!hasSelection)
            Button("Deselect All") { model?.clearSelection() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!hasSelection)
            Divider()
            Button("Add Text") { model?.addTextOverlay() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(!hasClips)
            Button(model?.isRecordingVoiceover == true ? "Stop Recording Voiceover" : "Record Voiceover…") {
                editor?.voiceover()
            }
            .disabled(editor == nil)
            Button("Supercut…") { editor?.supercut() }
                .disabled(editor == nil)
        }
    }
}

/// Mark: moving through the timeline, and markers.
struct EditorMarkCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor

    private var model: EditorModel? { editor?.model }
    private var hasClips: Bool { !(model?.project.timeline.clips.isEmpty ?? true) }

    var body: some Commands {
        CommandMenu("Mark") {
            Button(model?.isPlaying == true ? "Pause" : "Play") { model?.togglePlay() }
                .disabled(!hasClips)
            Divider()
            Button("Add or Remove Marker") { model?.toggleMarkerAtPlayhead() }
                .keyboardShortcut("m", modifiers: .control)
                .disabled(!hasClips)
            Button("Next Marker") { model?.goToMarker(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(model?.markers.isEmpty ?? true)
            Button("Previous Marker") { model?.goToMarker(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(model?.markers.isEmpty ?? true)
            Divider()
            Button("Next Edit") { model?.goToEdit(forward: true) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!hasClips)
            Button("Previous Edit") { model?.goToEdit(forward: false) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!hasClips)
            Button("Go to Start") { model?.goToStart() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(!hasClips)
            Button("Go to End") { model?.goToEnd() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(!hasClips)
            Button("Next Frame") { if let m = model { m.nudgePlayhead(seconds: m.frameStep) } }
                .disabled(!hasClips)
            Button("Previous Frame") { if let m = model { m.nudgePlayhead(seconds: -m.frameStep) } }
                .disabled(!hasClips)
        }
    }
}

/// View ▸ the editor's zoom and inspector.
struct EditorViewCommands: Commands {
    @FocusedValue(\.editorCommands) private var editor

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { editor?.model.zoom(by: 1.5) }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(editor == nil)
            Button("Zoom Out") { editor?.model.zoom(by: 1 / 1.5) }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(editor == nil)
            Button(editor?.inspectorShown == false ? "Show Inspector" : "Hide Inspector") {
                editor?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(editor == nil)
        }
    }
}
#endif
