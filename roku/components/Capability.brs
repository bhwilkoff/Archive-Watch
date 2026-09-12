' Capability.brs — ONE place that decides what this player can be asked to do.
'
' THE POLICY (owner, 2026-09-11): "There is no reason to do a bunch of work
' pushing the platform on for modern Roku users if it is going to be hamstrung
' by the older devices that are mostly stuck in 2014."
'
' So the rule here is asymmetric on purpose:
'
'   MODERN is never constrained by legacy. A feature that a current Roku can
'   do is built for a current Roku, at full quality, and is switched OFF on
'   the legacy tier if it cannot run there. Legacy never sets the ceiling.
'
'   LEGACY gets a working app, not the same app. It keeps navigation,
'   browsing, Detail and playback — all verified on a Roku 2 XD (Roku OS
'   9.1.0, ARM11 600 MHz, 256 MB) on 2026-09-11, including a film played
'   6m40s at 1.00x. It loses decoration and telemetry, which cost it frames
'   and buy it nothing.
'
' WHAT THIS CANNOT GATE, and it is worth being honest about it: BrightScript
' has no conditional compilation. A language feature the oldest supported
' firmware cannot PARSE is unavailable everywhere in the channel, because the
' component fails to install rather than fails to run. That is why
' `continue for` was removed from all 29 components rather than gated — see
' tools/test_roku_legacy_syntax.py. It is a one-off syntactic cost, it blocks
' no feature, and it is the ONLY thing legacy imposes on modern code. If that
' ever stops being true — if the oldest tier starts costing real capability —
' the answer is to raise the manifest's firmware floor, not to spread
' conditionals through the app.

function AWTier() as String
    if m.awTier = invalid
        ui = CreateObject("roDeviceInfo").GetUIResolution()
        name = ""
        if ui <> invalid then name = LCase(fmt(ui.name))
        ' UI resolution is the available PROXY for the hardware generation —
        ' a player Roku renders our FHD layout at HD or SD is the 2014-and-
        ' earlier tier. It is not a truth: a modern Roku on an old television
        ' overscans too, and nothing in the API reveals that. Where the
        ' difference matters to a VIEWER rather than to the CPU, the right
        ' answer is a setting, not this function.
        if name = "hd" or name = "sd"
            m.awTier = "legacy"
        else
            m.awTier = "modern"
        end if
        print "AWTIER "; m.awTier; " (ui="; name; ")"
    end if
    return m.awTier
end function

function AWIsLegacy() as Boolean
    return (AWTier() = "legacy")
end function

' Named capabilities, so a call site reads as WHAT it needs rather than WHICH
' devices it distrusts. Each one records why it is off, and what it cost.
function AWCan(feature as String) as Boolean
    if AWTier() = "modern" then return true

    ' focusFrame — twelve Poster nodes per tile (four corners, eight ring
    ' slices), each decoding a PNG. Thirty tiles is 360 nodes and the XD
    ' answered "Execution timeout (runtime error &h23)" inside AWFrameBuild.
    ' Focus itself is NOT dropped: a focused tile still grows 224x336 ->
    ' 248x360, verified legible on that TV.
    if feature = "focusFrame" then return false

    ' memoryMonitor — roAppMemoryMonitor does not exist below Roku OS 13 and
    ' CreateObject returns invalid there. Telemetry, not a feature.
    if feature = "memoryMonitor" then return false

    ' edgeToEdge — a television of this era crops ~5% off every edge, which
    ' swallows a nav rail that starts at x = 0. The interface is inset on this
    ' tier and full-bleed on modern panels.
    if feature = "edgeToEdge" then return false

    return true
end function
