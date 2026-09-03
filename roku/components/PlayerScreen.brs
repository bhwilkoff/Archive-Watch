sub init()
    m.t = Theme()
    m.video = m.top.FindNode("video")
    m.hudScrim = m.top.FindNode("hudScrim")
    m.hudTitle = m.top.FindNode("hudTitle")
    m.hudMeta = m.top.FindNode("hudMeta")
    m.diag = m.top.FindNode("diag")
    m.dog = m.top.FindNode("watchdog")

    m.video.translation = [-150, 0]
    m.video.width = 1920 : m.video.height = 1080
    m.video.enableTrickPlay = true

    ' §5.3 — the trick bar is the one piece of the platform transport we are
    ' allowed to colour, so it carries marquee orange and nothing else changes.
    if m.video.trickPlayBar <> invalid
        m.video.trickPlayBar.filledBarBlendColor = m.t.marquee
        m.video.trickPlayBar.trackBlendColor = "0x66666680"
    end if

    ' §6.6 — OK reveals a NON-INTERACTIVE HUD carrying title and description
    ' (Decision 037). It is not a scrubber; the platform owns that.
    m.hudScrim.translation = [-150, 0]
    m.hudScrim.width = 1920 : m.hudScrim.height = 288
    m.hudScrim.color = "0x0B0B0CCC"
    m.hudTitle.font = m.t.uScreen : m.hudTitle.color = m.t.textPri
    m.hudTitle.translation = [42, 63] : m.hudTitle.width = 1500
    m.hudTitle.maxLines = 2 : m.hudTitle.wrap = true
    m.hudMeta.font = m.t.uMeta : m.hudMeta.color = m.t.textSec
    m.hudMeta.translation = [42, 201]
    m.diag.font = m.t.uMeta : m.diag.color = m.t.textSec
    m.diag.translation = [42, 981]
    m.diag.visible = false

    hideHud()
    m.video.ObserveField("state", "onState")
    m.dog.ObserveField("fire", "onWatchdog")
    m.lastPosn = -1
    m.stalls = 0
    m.recoveries = 0
end sub

sub onUrl()
    url = m.top.playUrl
    if url = invalid or url = "" then return

    c = CreateObject("roSGNode", "ContentNode")
    c.title = m.top.playTitle
    c.url = url
    ' archive.org serves progressive MP4 behind a 302 to a storage node.
    c.streamFormat = "mp4"

    ' The coarse resilience that Roku DOES give us (§6.6b). Both are guarded:
    ' a field that does not exist on this OS must not take the channel down.
    if c.HasField("StreamStickyHttpRedirects") then c.StreamStickyHttpRedirects = true
    if m.video.HasField("ignoreStreamErrors") then m.video.ignoreStreamErrors = true

    m.hudTitle.text = m.top.playTitle
    m.hudMeta.text = m.top.playMeta
    m.video.content = c
    m.video.control = "play"
    m.video.setFocus(true)
    showHud()
    m.dog.control = "start"
    print "AWPLAY start "; url
end sub

sub onState()
    s = m.video.state
    print "AWPLAY state="; s; " posn="; m.video.position
    if s = "playing"
        ' The HUD behaves like the transport: it appears on interaction and
        ' leaves once the film is actually running.
        m.hudHideAt = nowSeconds() + 4
    else if s = "finished"
        m.dog.control = "stop"
        m.top.ended = true
    else if s = "error"
        ' Say WHY. A silent failure here is the single most expensive thing on
        ' this platform, and the error fields are the only account we get.
        print "AWPLAY error code="; m.video.errorCode; " msg="; m.video.errorMsg
        m.diag.visible = true
        m.diag.text = "Playback error " + fmt(m.video.errorCode) + " — " + fmt(m.video.errorMsg)
    end if
end sub

' The ONLY recovery available to a Roku channel: watch the position, and if it
' stops advancing while we believe we are playing, re-issue play at the last
' known position. Every recovery is a visible cold re-buffer — that is the
' honest cost of having no control over the HTTP layer (§6.6b), and it is
' recorded in PARITY rather than hidden.
sub onWatchdog()
    st = m.video.state
    posn = m.video.position
    if st = "playing" or st = "buffering"
        if posn = m.lastPosn and posn > 0
            m.stalls = m.stalls + 1
            print "AWPLAY stall n="; m.stalls; " at "; posn
            ' Two consecutive samples, so a single slow read is not treated as
            ' a stall. Ten seconds of no progress is a stall by any measure.
            if m.stalls >= 2
                m.recoveries = m.recoveries + 1
                print "AWPLAY recover #"; m.recoveries; " from "; posn
                c = m.video.content
                if c <> invalid
                    c.playStart = posn
                    m.video.control = "stop"
                    m.video.content = c
                    m.video.control = "play"
                end if
                m.stalls = 0
            end if
        else
            m.stalls = 0
        end if
    end if
    m.lastPosn = posn

    if m.hudHideAt <> invalid and nowSeconds() >= m.hudHideAt
        hideHud()
        m.hudHideAt = invalid
    end if
end sub

sub showHud()
    m.hudScrim.visible = true : m.hudTitle.visible = true : m.hudMeta.visible = true
end sub

sub hideHud()
    m.hudScrim.visible = false : m.hudTitle.visible = false : m.hudMeta.visible = false
end sub

sub stopPlayback()
    m.dog.control = "stop"
    m.video.control = "stop"
    m.video.content = invalid
end sub

' §3.1 — OK reveals the HUD. Instant Replay rewinds 15s, inside Roku's
' required 10–25s band. Back exits playback and returns to the referring
' screen; the Scene pops, so it is not consumed here.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "OK"
        showHud()
        m.hudHideAt = nowSeconds() + 6
        return true
    else if key = "instantreplay"
        p = m.video.position - 15
        if p < 0 then p = 0
        m.video.seek = p
        print "AWPLAY replay to "; p
        return true
    end if
    return false
end function

' BrightScript will not accept a method call on a function's RETURN VALUE:
' CreateObject("roDateTime").AsSeconds() is a compile error ("Builtin function
' call expected"), which is why this exists rather than being inlined.
function nowSeconds() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

' NOTE: `pos` is a BrightScript builtin; a variable of that name fails to
' compile with "Builtin function call expected". Hence `posn`.
