sub init()
    m.t = Theme()
    m.video = m.top.FindNode("video")
    m.hudScrim = m.top.FindNode("hudScrim")
    m.hudTitle = m.top.FindNode("hudTitle")
    m.hudMeta = m.top.FindNode("hudMeta")
    m.diag = m.top.FindNode("diag")
    m.dog = m.top.FindNode("watchdog")

    m.video.translation = [0, 0]
    m.video.width = 1920 : m.video.height = 1080
    m.video.enableTrickPlay = true

    ' §5.3 — the trick bar is the one piece of the platform transport we are
    ' allowed to colour, so it carries marquee orange and nothing else changes.
    if m.video.trickPlayBar <> invalid
        m.video.trickPlayBar.filledBarBlendColor = m.t.marquee
        m.video.trickPlayBar.trackBlendColor = "0x66666680"
    end if

    ' §6.6 (amended) — Roku's Video node draws its OWN transport overlay on OK,
    ' carrying the title, a progress bar and trick play. Drawing a second one
    ' on top of it is not "our design", it is a duplicate the platform already
    ' provides better — measured on the device, where the system overlay
    ' rendered "The Clairvoyant" and a clock straight over ours.
    '
    ' What remains is the one thing the system CANNOT say: that this film has
    ' subtitles the viewer's own device setting is suppressing. It sits at the
    ' bottom, clear of the system overlay, and only when there is something to
    ' say.
    m.hudScrim.visible = false
    m.hudTitle.visible = false
    m.hudMeta.font = m.t.uBody : m.hudMeta.color = m.t.textPri
    m.hudMeta.translation = [m.t.readX, 906]
    m.hudMeta.width = 1500 : m.hudMeta.maxLines = 1
    m.diag.font = m.t.uMeta : m.diag.color = m.t.textSec
    m.diag.translation = [42, 981]
    m.diag.visible = false

    hideHud()
    m.video.ObserveField("state", "onState")
    m.dog.ObserveField("fire", "onWatchdog")
    m.lastPosn = -1
    m.capReported = false
    m.stalls = 0
    m.recoveries = 0
end sub

sub onUrl()
    url = m.top.playUrl
    if url = invalid or url = "" then return
    ' Whatever the last film said about itself does not apply to this one.
    m.diag.visible = false
    ' A url with a raw space is not a url, and the Video node will not open
    ' one. The spines are repaired at the source now, but this is the single
    ' place EVERY playback path passes through — films, episodes, channels,
    ' Party Play — so it is the cheapest place to be certain. Idempotent: an
    ' already-encoded url contains no spaces to replace.
    url = AWEncodeSpaces(url)

    c = CreateObject("roSGNode", "ContentNode")
    c.title = m.top.playTitle
    c.url = url
    ' archive.org serves progressive MP4 behind a 302 to a storage node.
    c.streamFormat = "mp4"
    if m.top.startAt > 0
        c.playStart = m.top.startAt
        print "AWPLAY resume at "; m.top.startAt
    end if

    ' The coarse resilience that Roku DOES give us (§6.6b). Both are guarded:
    ' a field that does not exist on this OS must not take the channel down.
    ' Side-loaded captions. Roku documents SRT for SubtitleUrl and only accepts
    ' WebVTT inside HLS/DASH — our catalog publishes VTT — so this is set and
    ' then MEASURED: the track count is printed once the item is ready, and
    ' the answer decides whether a VTT-to-SRT conversion is needed rather than
    ' a guess about it.
    if m.top.captionUrl <> ""
        c.SubtitleUrl = m.top.captionUrl
        c.SubtitleConfig = { TrackName: "eng:1:English" }
        print "AWCAP offering "; m.top.captionUrl
    end if
    if m.top.bifUrl <> ""
        ' The HD field serves FHD too; SD would be a 240 px file.
        c.HDBifUrl = m.top.bifUrl
        c.SDBifUrl = m.top.bifUrl
        print "AWBIF offering "; m.top.bifUrl
    end if
    if c.HasField("StreamStickyHttpRedirects") then c.StreamStickyHttpRedirects = true
    if m.video.HasField("ignoreStreamErrors") then m.video.ignoreStreamErrors = true

    meta = ""
    ' Roku owns the caption setting GLOBALLY and an app must not override it —
    ' but a viewer whose device is set to "Off" or "Instant replay" would
    ' otherwise conclude this film simply has no subtitles. Say that it does,
    ' and name the key that reaches the setting (which is `*`, the key Roku
    ' reserves during playback for exactly this).
    if m.top.captionUrl <> ""
        mode = CreateObject("roDeviceInfo").GetCaptionsMode()
        print "AWCAP device captions mode="; mode
        if LCase(fmt(mode)) <> "on"
            meta = "Subtitles available for this film — press * to turn captions on"
        end if
    end if
    m.hudMeta.text = meta
    m.hasNotice = (meta <> "")
    m.capReported = false
    m.video.content = c
    m.video.mute = m.top.muted
    m.video.control = "play"
    m.video.setFocus(true)
    showHud()
    m.hudHideAt = nowSeconds() + 9
    m.dog.control = "start"
    print "AWPLAY start "; url
end sub

sub onState()
    s = m.video.state
    print "AWPLAY state="; s; " posn="; m.video.position
    if s = "playing" and m.capReported <> true
        m.capReported = true
        tracks = m.video.availableSubtitleTracks
        n = 0
        if tracks <> invalid then n = tracks.Count()
        print "AWCAP availableSubtitleTracks="; n; " currentIndex="; m.video.currentSubtitleTrack
        if tracks <> invalid
            for each t in tracks
                print "AWCAP track: "; FormatJson(t)
            end for
        end if
    end if
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
        ' The code goes to the CONSOLE, never the screen. The comment below
        ' has always said so; the line above it did the opposite, and left
        ' "Playback error -5" sitting in the bottom-left corner. It was set
        ' visible on error and cleared NOWHERE, so the first failure of a
        ' session pinned it there over every film that played afterwards —
        ' which is what the owner saw survive Party Play.
        m.diag.visible = false
        ' Hand it up so the viewer is TOLD. A film that dies silently and drops
        ' the viewer back on the same Detail screen looks like a broken remote,
        ' not like a film archive.org will not serve.
        m.dog.control = "stop"
        ' The CODE stays in the console. Roku answers -1 for every HTTP failure,
        ' so putting it on screen tells the viewer nothing and reads like a
        ' crash; what they can act on is that this copy is the problem.
        m.top.failed = "This copy would not play — archive.org would not serve the file. It may have been moved, or restricted by its uploader."
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

    ' Bookmark on the same 5s tick the watchdog already runs on, so playback
    ' costs one timer rather than two. Roku wants bookmarks for VOD over 15
    ' minutes retained 30 days; the registry keeps them until it is full.
    if m.top.archiveID <> "" and posn > 0
        d = Int(m.video.duration)
        if d > 0
            awSetProgress(m.top.archiveID, Int(posn), d, m.top.progressOwner)
            ' Printed so an external audit can SEE the bookmark being written.
            ' The registry cannot be read over ECP, so the console is the only
            ' account of it that does not come from the app asking itself.
            print "AWPLAY bookmark "; m.top.archiveID; " "; Int(posn); "/"; d
        end if
    end if

    if m.hudHideAt <> invalid and nowSeconds() >= m.hudHideAt
        hideHud()
        m.hudHideAt = invalid
    end if
end sub

sub showHud()
    if m.hasNotice = true then m.hudMeta.visible = true
end sub

sub hideHud()
    m.hudMeta.visible = false
end sub

sub stopPlayback()
    ' Write the final position BEFORE tearing the player down — the tick may be
    ' up to five seconds stale, and the last thing a viewer did is the thing
    ' they most expect to be remembered.
    if m.top.archiveID <> "" and m.video.position > 0
        d = Int(m.video.duration)
        if d > 0
            awSetProgress(m.top.archiveID, Int(m.video.position), d, m.top.progressOwner)
            print "AWPLAY bookmark-final "; m.top.archiveID; " "; Int(m.video.position); "/"; d
        end if
    end if
    m.dog.control = "stop"
    m.video.control = "stop"
    m.video.content = invalid
end sub

' §3.1 — OK reveals the HUD. Instant Replay rewinds 15s, inside Roku's
' required 10–25s band. Back exits playback and returns to the referring
' screen; the Scene pops, so it is not consumed here.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    ' OK is NOT consumed: it belongs to Roku's transport overlay, and taking it
    ' would replace a native control with a worse one.
    if key = "instantreplay"
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
