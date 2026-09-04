sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.hint = m.top.FindNode("hint")
    m.chList = m.top.FindNode("chList")
    m.accent = m.top.FindNode("accent")
    m.chTitle = m.top.FindNode("chTitle")
    m.tagline = m.top.FindNode("tagline")
    m.onNow = m.top.FindNode("onNow")
    m.guide = m.top.FindNode("guide")
    m.empty = m.top.FindNode("empty")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Channels"

    m.hint.font = m.t.uMeta : m.hint.color = m.t.textSec
    m.hint.translation = [42, 204]
    m.hint.text = "Press OK on a channel to tune in — you join whatever is already playing."

    m.chList.translation = [42, 276]
    m.chList.itemSize = [396, 66]
    m.chList.itemSpacing = [0, 12]
    m.chList.numRows = 9
    m.chList.font = m.t.uBody
    m.chList.color = m.t.textPri
    m.chList.focusedColor = m.t.marquee
    m.chList.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.chList.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.chList.drawFocusFeedbackOnTop = true
    m.chList.vertFocusAnimationStyle = "floatingFocus"
    m.chList.ObserveField("itemFocused", "onChannelFocused")
    m.chList.ObserveField("itemSelected", "onChannelSelected")

    px = 486
    m.accent.translation = [px, 288]
    m.accent.width = 96 : m.accent.height = 6
    m.accent.color = m.t.marquee

    m.chTitle.font = m.t.uRow : m.chTitle.color = m.t.textPri
    m.chTitle.translation = [px, 264] : m.chTitle.width = 900
    m.tagline.font = m.t.uMeta : m.tagline.color = m.t.textSec
    m.tagline.translation = [px, 318] : m.tagline.width = 900
    m.onNow.font = m.t.uMeta : m.onNow.color = m.t.textSec
    m.onNow.translation = [px, 360] : m.onNow.width = 1050

    m.guide.translation = [px, 414]
    m.guide.itemComponentName = "GuideRow"
    m.guide.itemSize = [1050, 66]
    m.guide.itemSpacing = [0, 6]
    m.guide.numRows = 8
    m.guide.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.guide.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.guide.drawFocusFeedbackOnTop = true
    m.guide.vertFocusAnimationStyle = "floatingFocus"
    m.guide.ObserveField("itemSelected", "onGuideSelected")

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [150, 420] : m.empty.width = 1200 : m.empty.wrap = true

    m.col = 0            ' 0 = channel list, 1 = guide
    m.channels = invalid
    m.slots = []
end sub

sub showChannels(payload as Object)
    if payload = invalid or payload.list = invalid or payload.list.Count() = 0
        m.empty.visible = true
        m.empty.text = "The channel guide could not be loaded. Check the network and try again."
        return
    end if
    m.channels = payload.list
    root = CreateObject("roSGNode", "ContentNode")
    for each c in m.channels
        n = root.CreateChild("ContentNode")
        n.title = c.title
    end for
    m.chList.content = root
    m.chList.jumpToItem = 0
    paintChannel(0)
end sub

sub onChannelFocused()
    paintChannel(m.chList.itemFocused)
end sub

' Rebuilt per channel rather than for all fifteen up front: a schedule is ~40
' slots of cheap arithmetic, and building every channel's day would run the
' 64-bit shuffle fifteen times for fourteen listings nobody is looking at.
sub paintChannel(idx as Integer)
    if m.channels = invalid or idx < 0 or idx >= m.channels.Count() then return
    c = m.channels[idx]
    m.chTitle.text = c.title
    if c.tagline <> invalid then m.tagline.text = c.tagline
    if c.accent <> invalid then m.accent.color = BroadcastSafe(c.accent)

    nowS = nowLocalSeconds()
    m.slots = buildSchedule(fmt(c.id), c.programs, nowS)
    m.nowIndex = -1
    root = CreateObject("roSGNode", "ContentNode")
    shown = 0
    for i = 0 to m.slots.Count() - 1
        s = m.slots[i]
        ' Everything already finished is history; the guide starts at what is on.
        if s.endS <= nowS then continue for
        n = root.CreateChild("ContentNode")
        n.title = StripHTML(fmt(s.prog[1]))
        n.SHORTDESCRIPTIONLINE1 = clockLabel(s.startS)
        if s.startS <= nowS and nowS < s.endS
            n.SHORTDESCRIPTIONLINE2 = "now"
            if m.nowIndex < 0 then m.nowIndex = shown
        end if
        n.AddField("awSlot", "integer", false)
        n.awSlot = i
        shown = shown + 1
        if shown >= 40 then exit for
    end for
    m.guide.content = root
    m.guide.jumpToItem = 0

    if m.nowIndex >= 0
        s = m.slots[root.GetChild(m.nowIndex).awSlot]
        left = Int((s.endS - nowS) / 60)
        m.onNow.text = "On now: " + fmt(s.prog[1]) + "  ·  " + fmt(left) + " min left"
    else
        m.onNow.text = ""
    end if
end sub

sub onChannelSelected()
    tuneIn(m.chList.itemSelected)
end sub

' Tuning in JOINS whatever is playing, part-way through, the way a television
' does. Starting at the beginning would make it a playlist, not a channel.
sub tuneIn(idx as Integer)
    if m.slots.Count() = 0 then return
    nowS = nowLocalSeconds()
    for each s in m.slots
        if s.startS <= nowS and nowS < s.endS
            m.top.tune = { url: fmt(s.prog[3]), title: fmt(s.prog[1]),
                           meta: fmt(m.channels[idx].title) + "  ·  live",
                           startAt: nowS - s.startS }
            return
        end if
    end for
end sub

sub onGuideSelected()
    i = m.guide.itemSelected
    if m.guide.content = invalid then return
    n = m.guide.content.GetChild(i)
    if n = invalid then return
    if n.SHORTDESCRIPTIONLINE2 = "now"
        tuneIn(m.chList.itemFocused)
    else
        ' A programme later today cannot be "tuned into" — there is nothing to
        ' join yet. Its Detail screen is the honest destination: watch it now
        ' from the start, or save it.
        s = m.slots[n.awSlot]
        m.top.chosen = fmt(s.prog[0])
    end if
end sub

sub onFocusOn()
    if m.top.focusOn
        if m.col = 1 then m.guide.setFocus(true) else m.chList.setFocus(true)
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if m.col = 0
        if key = "right"
            if m.guide.content <> invalid and m.guide.content.GetChildCount() > 0
                m.col = 1 : m.guide.setFocus(true)
            end if
            return true
        else if key = "left"
            m.top.exitLeft = true
            return true
        end if
    else
        if key = "left"
            m.col = 0 : m.chList.setFocus(true)
            return true
        end if
    end if
    return false
end function
