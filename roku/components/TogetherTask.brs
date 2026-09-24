' The room poll, off the render thread — SHAREPLAY §11.
'
' REACHABLE since v1.42.615 (ROKU-DESIGN §8a): Library ▸ Options ▸ "Join a
' Watch Together room…" opens a keyboard, a `lookupOnly` run of this task
' reads the room once, the Scene starts that film at the room's position, and
' `PlayerScreen.roomCode` runs this task again to FOLLOW. §8.34 still pins the
' alphabet against the other four implementations.
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
    if m.top.lookupOnly
        room = awRoomRead(code)
        if room = invalid
            m.top.problem = "Could not reach the room. Check the connection and try again."
        else if room.DoesExist("ended")
            m.top.problem = "No room with that code. It may have ended, or a character may have been misheard."
        else
            m.top.room = { filmID: room.filmID, position: awRoomExpectedPosition(room), paused: (room.paused = true) }
        end if
        return
    end if
    m.top.running = true
    lastGeneration = -1
    lastChangeAt = awNowSeconds()
    ' A fresh anonymous token per join, for the host's "friends here" count.
    ba = CreateObject("roByteArray")
    ' Two lines, not one: BrightScript refuses a method call on a function's
    ' return value (see PlayerScreen's nowSeconds).
    di = CreateObject("roDeviceInfo")
    ba.FromAsciiString(di.GetRandomUUID())
    token = CreateObject("roEVPDigest")
    token.Setup("sha256")
    token = Left(token.Process(ba), 32)
    lastHereAt = -1000#

    while m.top.running
        if awNowSeconds() - lastHereAt >= 30
            awRoomSayHere(code, token)
            lastHereAt = awNowSeconds()
        end if
        room = awRoomRead(code)
        ' DoesExist, not `room.ended = true`: a normal room has no `ended` key,
        ' and comparing invalid with a boolean is a runtime type mismatch.
        if room <> invalid and room.DoesExist("ended")
            ' A room that has GONE (404/410) is over.
            m.top.problem = "The host ended the room."
            m.top.running = false
            exit while
        end if
        ' A poll that FAILED (invalid) is a poll — not a reason to tear a
        ' viewer out of a film. It used to end the room on the first blip; now
        ' it simply skips to the next poll.
        if room <> invalid

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
        else
            ' BOTH paused: on the host's FRAME, not merely paused — the host
            ' paused to talk about a shot (the rule every other platform
            ' gained on 2026-09-23).
            gap = room.position - local
            if gap < 0 then gap = -gap
            if gap > 0.5
                m.top.verb = { kind: "seek", to: room.position }
            end if
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
