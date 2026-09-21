' The room poll, off the render thread — SHAREPLAY §11.
'
' NOT REACHABLE YET. This task and `source/TogetherRoom.brs` are the working
' parts; NOTHING CREATES THIS NODE. Roku's join still needs three things: an
' option row in `openLibraryOptions`, a `StandardKeyboardDialog` (see
' `openNamer` for the two traps that are not optional), and a `roomCode` field
' on `PlayerScreen` that starts this task and applies its `verb`.
'
' It is left in the tree deliberately rather than deleted: §8.34 pins this
' file's alphabet against the other four implementations, so the rule cannot
' drift out from under a later session, and the hard part — polling off the
' render thread with a clock sample taken around the same request — is done.
' PARITY records Roku as NOT BUILT, which is the honest state.
'
' It owns the loop and the arithmetic and touches no video: the player applies
' what comes back. Same split as every other platform (§11.2a) — the rule is a
' value, the surface is a caller — and here it is also what keeps an
' eight-second network wait away from the thing drawing the film.

sub init()
    m.top.functionName = "pollLoop"
end sub

sub pollLoop()
    code = m.top.code
    if code = "" then return
    m.top.running = true
    lastGeneration = -1
    lastChangeAt = awNowSeconds()

    while m.top.running
        room = awRoomRead(code)
        if room = invalid
            ' A room that has GONE is over; anything else is a poll that
            ' failed, and a poll that failed is a poll — not a reason to tear
            ' a viewer out of a film.
            m.top.problem = "The room has ended."
            m.top.running = false
            exit while
        end if

        if room.generation <> lastGeneration
            lastGeneration = room.generation
            lastChangeAt = awNowSeconds()
        end if

        hostPaused = (room.paused = true)
        localPaused = m.top.localPaused
        local = m.top.localPosition

        if hostPaused <> localPaused
            ' Run state first and never eased: a host who pressed pause wants
            ' the film stopped now.
            m.top.verb = { kind: "paused", paused: hostPaused, rate: room.rate }
        else if not hostPaused
            expected = awRoomExpectedPosition(room)
            drift = expected - local
            magnitude = drift
            if magnitude < 0 then magnitude = -magnitude
            ' A Roku video has no playback-rate control, so the 3% nudge every
            ' other platform uses is unavailable here and the band collapses:
            ' inside a second, leave it; beyond, seek. That is coarser than
            ' §11.3 and is a platform limit rather than a choice, so the
            ' threshold is named here rather than hidden.
            if magnitude >= 1.0
                m.top.verb = { kind: "seek", to: expected }
            end if
        end if

        ' Back off while nothing is happening — a film nobody is touching is
        ' the common case in a two-hour watch, and 2-second polls for it are
        ' what would put this outside a free tier.
        quiet = awNowSeconds() - lastChangeAt
        waitSeconds = 2
        if quiet >= 60 then waitSeconds = 10
        sleep(waitSeconds * 1000)
    end while
end sub
