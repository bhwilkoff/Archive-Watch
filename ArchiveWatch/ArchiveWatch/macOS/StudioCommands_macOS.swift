#if os(macOS)
import SwiftUI

// THE BROADCAST MENU — roadmap #6.
//
// OBS's most-used feature by a distance is its hotkeys, and this Studio had
// none: every live action — muting the microphone, raising a card, changing
// where the host sits, ending the show — needed the Studio window found,
// focused, scrolled to the right column and clicked.
//
// WHY A MENU AND NOT A GLOBAL HOTKEY. A menu key equivalent is discoverable
// (a host finds it by looking), self-documenting (it prints its own shortcut
// next to it), needs no permission, and cannot collide silently with another
// app. A system-wide hotkey needs Accessibility TCC and works when Archive
// Watch is not frontmost at all — a real difference, and a bigger ask. These
// fire whenever ANY Archive Watch window is front, which covers the case the
// roadmap actually named: a host looking at the player rather than the
// Studio.
//
// AND IT IS A NEW TOP-LEVEL MENU, which Rule B13g explicitly declined to
// invent ("inventing a menu is the larger claim"). That reading was right when
// there was one command. There are now eleven, and burying them under File
// beside "New Project" would be the larger claim.

/// Everything a host does while a show is running, with a key for each.
struct StudioBroadcastCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Broadcast") {
            StudioWindowCommand()
            StudioGoLiveCommand()

            Divider()

            PreviewCommand()
            EndCommand()

            Divider()

            FilmPlaybackCommand()
            MicMuteCommand()
            DuckCommand()
            LowerThirdCommand()

            Divider()

            Menu("Show a Card") {
                ForEach(Array(MacCardChoice.allCases.enumerated()), id: \.element) { index, choice in
                    CardCommand(choice: choice, index: index)
                }
            }
            Menu("Scenes") {
                ForEach(0..<9, id: \.self) { SceneCommand(index: $0) }
            }
            Menu("Placement") {
                ForEach(StudioLayout.allCases, id: \.self) { layout in
                    PlacementCommand(layout: layout)
                }
            }
        }
    }
}

// Each command is its own small VIEW rather than a bare `Button`, for the
// reason `StudioWindowCommand` already documents: a command that needs to read
// observable state has to be a view, or SwiftUI never re-evaluates its title
// and a "Mute" that has become "Unmute" keeps saying Mute.

private struct PreviewCommand: View {
    private var studio: StudioSession { StudioSession.shared }
    @Bindable private var show = StudioMacShow.shared
    var body: some View {
        Button(studio.isRehearsing ? "Stop the Preview" : "Start the Preview") {
            if studio.isLive { Task { await studio.end() } }
            else if let film = show.film {
                Task { _ = await studio.beginShow(film: film, destination: nil) }
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        // A preview of nothing is not a state the engine can serve, and going
        // ON AIR is not something a preview key should be able to stop.
        .disabled(show.film == nil || studio.isOnAir)
    }
}

private struct EndCommand: View {
    private var studio: StudioSession { StudioSession.shared }
    var body: some View {
        Button("End the Broadcast") { Task { await StudioSession.shared.end() } }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!studio.isLive)
    }
}

private struct FilmPlaybackCommand: View {
    private var studio: StudioSession { StudioSession.shared }
    var body: some View {
        Button(studio.filmIsPlaying ? "Pause the Film" : "Play the Film") {
            studio.toggleFilmPlayback()
        }
        .keyboardShortcut(.space, modifiers: [.command, .shift])
        .disabled(!studio.hasFilm)
    }
}

private struct MicMuteCommand: View {
    @Bindable private var controls = StudioControls.shared
    var body: some View {
        // THE MOST IMPORTANT KEY ON THE LIST. A host who needs to cough, or
        // answer the door, or say something to the room, currently has to
        // find a window and click a switch.
        Button(controls.micMuted ? "Unmute My Microphone" : "Mute My Microphone") {
            controls.micMuted.toggle()
        }
        .keyboardShortcut("m", modifiers: [.command, .shift])
    }
}

private struct DuckCommand: View {
    @Bindable private var controls = StudioControls.shared
    var body: some View {
        Button(controls.duckEnabled ? "Stop Ducking the Film" : "Duck the Film Under My Voice") {
            controls.duckEnabled.toggle()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
    }
}

private struct LowerThirdCommand: View {
    @Bindable private var controls = StudioControls.shared
    var body: some View {
        Button(controls.showLowerThird ? "Hide the Lower Third" : "Show the Lower Third") {
            controls.showLowerThird.toggle()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}

private struct CardCommand: View {
    let choice: MacCardChoice
    let index: Int
    @Bindable private var controls = StudioControls.shared

    var body: some View {
        Button {
            // A SECOND PRESS TAKES IT DOWN. A card is the one control a host
            // raises in a hurry and wants gone in a hurry, and making the same
            // key do both is one thing to remember instead of two.
            controls.cardChoice = (controls.cardChoice == choice) ? .none : choice
        } label: {
            if controls.cardChoice == choice { Label(choice.label, systemImage: "checkmark") }
            else { Text(choice.label) }
        }
        // ⌃⌘0…4, which leaves ⌘1…n free for whatever a window wants.
        .keyboardShortcut(KeyEquivalent(Character("\(index)")),
                          modifiers: [.command, .control])
        // §D10: an empty custom card is never shown, so the key that would
        // raise one is disabled rather than doing nothing.
        .disabled(choice == .custom && !controls.customCardHasWords)
    }
}

private struct PlacementCommand: View {
    let layout: StudioLayout
    @Bindable private var controls = StudioControls.shared
    var body: some View {
        Button {
            controls.layout = layout
        } label: {
            if controls.layout == layout { Label(layout.label, systemImage: "checkmark") }
            else { Text(layout.label) }
        }
        // NO key equivalents. Five placements would want five more keys, and
        // §D14a made the host's framing a drag rather than a preset anyway —
        // a placement is a decision made once a show, not mid-sentence. They
        // are here to be FOUND, which is the other half of what a menu is for.
    }
}
#endif
