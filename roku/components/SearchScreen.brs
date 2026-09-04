sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.kb = m.top.FindNode("kb")
    m.doorsLabel = m.top.FindNode("doorsLabel")
    m.doorGroup = m.top.FindNode("doors")
    m.grid = m.top.FindNode("grid")
    m.status = m.top.FindNode("status")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Search"

    m.kb.translation = [42, 216]
    m.kb.ObserveField("text", "onText")

    m.status.font = m.t.uMeta : m.status.color = m.t.textSec
    ' Below the keyboard, which runs 216..890. At y=690 it printed straight
    ' through the keys.
    m.status.translation = [42, 918] : m.status.width = 570 : m.status.wrap = true
    m.status.text = "Type to search 26,965 titles — or pick a door."

    m.doorsLabel.font = m.t.uRow : m.doorsLabel.color = m.t.textPri
    m.doorsLabel.translation = [660, 216]
    m.doorsLabel.text = "Or start here"

    ' §6.4 — the doors. Real Button nodes, because a Group is not focusable
    ' and a door nobody can reach is not a door.
    m.doorDefs = [
        { id: "feature-film", label: "Feature Films" },
        { id: "tv-series",    label: "Classic TV" },
        { id: "silent-film",  label: "Silent Era" },
        { id: "animation",    label: "Animation" },
        { id: "surprise",     label: "Surprise Me" }
    ]
    m.doors = []
    y = 0
    for each d in m.doorDefs
        b = m.doorGroup.CreateChild("Button")
        b.translation = [0, y]
        b.minWidth = 420
        b.height = 66
        b.text = d.label
        b.textColor = m.t.textPri
        b.focusedTextColor = m.t.marquee
        b.focusBitmapUri = "pkg:/images/focus_ring.9.png"
        b.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
        b.ObserveField("buttonSelected", "onDoorSelected")
        m.doors.Push(b)
        y = y + 84
    end for
    m.doorGroup.translation = [660, 288]
    m.doorIndex = 0

    m.grid.translation = [660, 288]
    m.grid.itemComponentName = "GridTile"
    m.grid.numColumns = 4
    m.grid.numRows = 2
    m.grid.itemSize = [210, 393]
    m.grid.itemSpacing = [24, 24]
    m.grid.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.grid.drawFocusFeedbackOnTop = true
    m.grid.vertFocusAnimationStyle = "floatingFocus"
    m.grid.visible = false
    m.grid.ObserveField("itemSelected", "onSelected")

    m.zone = 0        ' 0 = keyboard, 1 = doors, 2 = results
end sub

sub onText()
    q = m.kb.text
    if q = invalid then q = ""
    svc = m.top.service
    if svc = invalid then return
    if Len(q) < 2
        ' Below two characters the results are noise; the doors stay.
        m.grid.visible = false
        m.doorGroup.visible = true
        m.doorsLabel.visible = true
        m.status.text = "Type to search 26,965 titles — or pick a door."
        return
    end if
    svc.qType = ""
    svc.qDecade = 0
    svc.qSort = "popular"
    svc.qText = q
    svc.queryId = svc.queryId + 1
    m.status.text = "Searching for “" + q + "”…"
end sub

sub showResults(root as Object, total as Integer)
    if Len(m.kb.text) < 2 then return
    m.grid.content = root
    m.grid.visible = (total > 0)
    m.doorGroup.visible = (total = 0)
    m.doorsLabel.visible = (total = 0)
    if total = 0
        m.status.text = "Nothing matches “" + m.kb.text + "”. Try fewer letters, or a door."
    else
        m.status.text = fmt(total) + " titles match “" + m.kb.text + "”. Press Right to browse them."
    end if
end sub

sub onDoorSelected()
    m.top.door = m.doorDefs[m.doorIndex].id
end sub

sub onSelected()
    if m.grid.content = invalid then return
    it = m.grid.content.GetChild(m.grid.itemSelected)
    if it <> invalid then m.top.chosen = it.id
end sub

sub onFocusOn()
    if m.top.focusOn then focusHere()
end sub

sub focusHere()
    if m.zone = 2 and m.grid.visible
        m.grid.setFocus(true)
    else if m.zone = 1
        m.doors[m.doorIndex].setFocus(true)
    else
        m.zone = 0
        m.kb.setFocus(true)
    end if
end sub

' §3.5 / §6.4 — Right leaves the keyboard for whatever is on the right: the
' doors when there is no query, the results when there is one. Left from the
' keyboard's first column reaches the rail (§2.1).
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false

    if m.zone = 0
        if key = "right"
            if m.grid.visible then m.zone = 2 else m.zone = 1
            focusHere()
            return true
        end if
        return false     ' the keyboard owns its own arrows
    else if m.zone = 1
        if key = "down"
            if m.doorIndex < m.doors.Count() - 1
                m.doorIndex = m.doorIndex + 1 : focusHere()
            end if
            return true
        else if key = "up"
            if m.doorIndex > 0
                m.doorIndex = m.doorIndex - 1 : focusHere()
            end if
            return true
        else if key = "left"
            m.zone = 0 : focusHere() : return true
        end if
    else
        if key = "left"
            if m.grid.itemFocused mod m.grid.numColumns = 0
                m.zone = 0 : focusHere() : return true
            end if
        end if
    end if
    return false
end function

' Entering Search from the nav starts a fresh query. Without this the previous
' query survives inside the MiniKeyboard for the life of the channel, so
' reopening Search silently resumes someone else's search.
sub resetSearch()
    m.kb.text = ""
    m.zone = 0
    m.doorIndex = 0
    m.grid.visible = false
    m.doorGroup.visible = true
    m.doorsLabel.visible = true
    m.status.text = "Type to search 26,965 titles — or pick a door."
    focusHere()
end sub
