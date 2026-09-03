sub init()
    m.t = Theme()
    m.rail = m.top.FindNode("rail")
    m.content = m.top.FindNode("content")
    m.loading = m.top.FindNode("loading")

    ' A Label's `font` takes a URI STRING. Assigning a Font NODE that carries
    ' a font: system URI renders NOTHING — no error, no warning, an empty
    ' screen with a healthy console. Proven by a three-way experiment on the
    ' device in tick 2 and the reason half this shell was invisible.
    brand = m.top.FindNode("brand")
    brand.font = m.t.uRow
    brand.text = "ARCHIVE WATCH"
    brand.color = m.t.marquee
    ' Clear the rail: the content column starts at railW, and the brand is
    ' content chrome, not rail chrome.
    brand.translation = [m.t.railW + m.t.safeX, 39]

    clock = m.top.FindNode("clock")
    clock.font = m.t.uMeta : clock.color = m.t.textSec
    clock.translation = [1560, 45]
    clock.text = nowString()

    ' §5.7 — the (*) indicator, shown because Options ARE available here.
    opt = m.top.FindNode("optHint")
    opt.font = m.t.uMeta : opt.color = m.t.textSec
    opt.translation = [1770, 45]
    opt.text = "(*)"

    m.loading.font = m.t.uBody : m.loading.color = m.t.textSec
    m.loading.translation = [m.t.railW + m.t.readX, 480]
    m.loading.text = "Loading the archive…"

    ' The home screen lives in the content column, right of the rail.
    m.home = m.content.CreateChild("HomeScreen")
    m.home.translation = [m.t.railW, 0]
    m.home.ObserveField("exitLeft", "focusRail")
    m.home.ObserveField("chosen", "onChosen")

    m.overlay = m.top.FindNode("overlay")
    m.route = "home"

    m.rail.ObserveField("selected", "onRailSelected")

    m.task = CreateObject("roSGNode", "HomeTask")
    m.task.ObserveField("status", "onStatus")
    m.task.control = "RUN"

    ' §1.4 / TV-DESIGN §3.1 — something is ALWAYS focused, or the remote does
    ' nothing at all and the viewer thinks the app has hung. Until content
    ' lands, the rail holds focus.
    focusRail()
    print "AWROKU scene ready"
end sub

sub onStatus()
    s = m.task.status
    print "AWROKU home status="; s
    if s = "ready"
        m.loading.visible = false
        m.home.rowsContent = m.task.rows
        m.home.heroContent = m.task.hero
        focusContent()
    else if s = "error"
        m.loading.text = "Could not reach the archive. Check the network and try again."
    end if
end sub

sub focusRail()
    m.rail.focusOn = true
    m.home.focusOn = false
    m.rail.setFocus(true)
    print "AWFOCUS rail"
end sub

sub focusContent()
    m.rail.focusOn = false
    m.home.focusOn = true
    m.home.setFocus(true)
    print "AWFOCUS content"
end sub

sub onRailSelected()
    id = m.rail.selected
    print "AWROKU rail-select "; id
    ' Only Home exists this tick; the other six surfaces arrive in later ticks
    ' and the rail already announces them, so nothing here silently swallows a
    ' press — it says what is not built yet.
    if id = "home"
        focusContent()
    else
        m.loading.visible = true
        m.loading.text = titleFor(id) + " arrives in a later build."
        focusContent()
    end if
end sub

' §2.5 — depth is at most 2: rail → surface → item. Detail and the player are
' overlays over the shell rather than a growing stack, which is what keeps
' Back's meaning simple (§2.6).
sub onChosen()
    id = m.home.chosen
    if id = invalid or id = "" then return
    openDetail(id)
end sub

sub openDetail(archiveID as String)
    it = findItem(archiveID)
    if m.detail = invalid
        m.detail = m.overlay.CreateChild("DetailScreen")
        m.detail.translation = [m.t.railW, 0]
        m.detail.ObserveField("play", "onPlay")
    end if
    ' The overlay must actually COVER: with Home still composited beneath it,
    ' Home's own hero title and rows read through the scrim as ghosts.
    m.content.visible = false
    m.detail.visible = true
    m.detail.item = it
    m.detail.detail = {}
    m.detail.focusOn = true
    m.home.focusOn = false
    m.rail.focusOn = false
    m.detail.setFocus(true)
    m.route = "detail"
    print "AWFOCUS detail "; archiveID

    if m.dtask = invalid
        m.dtask = CreateObject("roSGNode", "DetailTask")
        m.dtask.ObserveField("detail", "onDetailLoaded")
    end if
    m.dtask.archiveID = archiveID
    m.dtask.control = "RUN"
end sub

sub onDetailLoaded()
    if m.detail <> invalid then m.detail.detail = m.dtask.detail
end sub

' Walk the rows we already hold rather than re-querying: the Home content tree
' IS the model, and Detail is opened from it.
function findItem(archiveID as String) as Object
    rows = m.task.rows
    if rows = invalid then return invalid
    for i = 0 to rows.GetChildCount() - 1
        row = rows.GetChild(i)
        for j = 0 to row.GetChildCount() - 1
            it = row.GetChild(j)
            if it.id = archiveID then return it
        end for
    end for
    return invalid
end function

sub onPlay()
    url = m.detail.play
    if url = invalid or url = "" then return
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        m.player.translation = [m.t.railW, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
    end if
    m.player.visible = true
    m.detail.visible = false
    m.player.playTitle = m.detail.item.title
    m.player.playMeta = m.detail.item.SHORTDESCRIPTIONLINE1
    m.player.playUrl = url
    m.player.setFocus(true)
    m.route = "player"
    print "AWFOCUS player"
end sub

' §6.6 / §2.6 — the end of a film returns the viewer where they came from.
' Stranded on a dead screen is not a state.
sub onPlaybackEnded()
    if m.player <> invalid and m.player.ended then closePlayer()
end sub

sub closePlayer()
    if m.player = invalid then return
    m.player.callFunc("stopPlayback")
    m.player.visible = false
    m.detail.visible = true
    m.detail.focusOn = true
    m.detail.setFocus(true)
    m.route = "detail"
    print "AWFOCUS detail (from player)"
end sub

sub closeDetail()
    if m.detail <> invalid
        m.detail.visible = false
        m.detail.focusOn = false
    end if
    m.content.visible = true
    focusContent()
    m.route = "home"
end sub

function titleFor(id as String) as String
    if id = "movies" then return "Movies"
    if id = "tv" then return "TV"
    if id = "channels" then return "Channels"
    if id = "collections" then return "Collections"
    if id = "search" then return "Search"
    if id = "library" then return "Library"
    return "Home"
end function

function nowString() as String
    d = CreateObject("roDateTime")
    d.ToLocalTime()
    h = d.GetHours()
    ampm = "AM"
    if h >= 12 then ampm = "PM"
    if h > 12 then h = h - 12
    if h = 0 then h = 12
    mn = d.GetMinutes()
    mm = fmt(mn)
    if mn < 10 then mm = "0" + mm
    return fmt(h) + ":" + mm + " " + ampm
end function

' §2.6 — Back is sacred. It is NOT trapped here: returning false lets Roku
' close the channel from Home, which is the platform convention and a
' certification requirement.
' §2.6 — Back is sacred. It pops one level; from Home it is NOT consumed, so
' Roku closes the channel, which is the platform convention and a
' certification requirement.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    print "AWKEY "; key; " route="; m.route
    if key = "back"
        if m.route = "player"
            closePlayer()
            return true
        else if m.route = "detail"
            closeDetail()
            return true
        end if
        return false
    end if
    return false
end function
