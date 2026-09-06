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
    m.doorPills = []
    y = 0
    for each d in m.doorDefs
        ' §13.5 — a door is a pill at rest too; a Button paints only its
        ' focus bitmap, so the rest state is ours to draw.
        rest = AWPillBuild(m.doorGroup)
        ' F19 — a door pill fits its label (+ 2 x 36 px), not a fixed 420.
        dw = AWTextWidth(m.doorGroup, m.t.uRow, d.label) + 80
        if dw < 200 then dw = 200
        AWPillLayout(rest, 0, y + 3, dw)
        m.doorPills.Push(rest)
        b = m.doorGroup.CreateChild("Button")
        b.translation = [0, y]
        b.minWidth = dw
        b.height = 66
        b.text = d.label
        b.textColor = m.t.textPri
        b.focusedTextColor = m.t.marquee
        b.focusBitmapUri = "pkg:/images/pill_focus.9.png"
        b.focusFootprintBitmapUri = "pkg:/images/pill_rest.9.png"
        b.focusedTextColor = m.t.canvas
        b.iconUri = ""
        b.focusedIconUri = ""
        b.ObserveField("buttonSelected", "onDoorSelected")
        m.doors.Push(b)
        y = y + 84
    end for
    if m.fitTimer = invalid
        m.fitTimer = m.top.CreateChild("Timer")
        m.fitTimer.duration = 0.05
        m.fitTimer.ObserveField("fire", "onFitPills")
    end if
    m.fitTimer.control = "start"
    m.doorGroup.translation = [660, 288]
    m.doorIndex = 0

    ' §6.4 — filters over RESULTS, offered only for facets the results actually
    ' contain. A "Silent Era" chip on a search that returned no silent films is
    ' a control that can only disappoint.
    m.chipGroup = m.top.FindNode("chips")
    m.chipGroup.translation = [660, 288]
    m.chipDefs = [
        { id: "type",   label: "Type",   values: ["All"] },
        { id: "decade", label: "Decade", values: ["All"] }
    ]
    m.chipIndex = [0, 0]
    m.chips = []
    m.restPills = []
    cx = 0
    for i = 0 to m.chipDefs.Count() - 1
        ' §13.5 — the same pill chips as Browse: a resting pill we draw (a
        ' Button paints only its focus bitmap), a solid light pill on focus.
        rest = AWPillBuild(m.chipGroup)
        AWPillLayout(rest, cx, 0, 300)
        m.restPills.Push(rest)
        b = m.chipGroup.CreateChild("Button")
        b.translation = [cx, 0]
        b.minWidth = 300
        b.height = 60
        b.iconUri = "" : b.focusedIconUri = ""
        b.textColor = m.t.textPri
        b.focusedTextColor = m.t.canvas
        b.focusBitmapUri = "pkg:/images/pill_focus.9.png"
        b.focusFootprintBitmapUri = "pkg:/images/pill_rest.9.png"
        b.ObserveField("buttonSelected", "onChipPressed")
        m.chips.Push(b)
        cx = cx + 336
    end for
    m.chipGroup.visible = false
    m.chipFocus = 0

    m.grid.translation = [660, 360]
    m.grid.itemComponentName = "GridTile"
    m.grid.numColumns = 4
    m.grid.numRows = 2
    m.grid.numRows = 2
    ' F10 — the cell reserves two caption lines under the focused 315 px art.
    m.grid.itemSize = [210, 434]
    m.grid.itemSpacing = [24, 12]
    ' The TILE rings its own art (ROKU-DESIGN §5.4a). An explicitly transparent
    ' 9-patch is required: with no bitmap the list draws its own grey box.
    m.grid.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.drawFocusFeedbackOnTop = true
    m.grid.vertFocusAnimationStyle = "floatingFocus"
    m.grid.visible = false
    m.grid.ObserveField("itemSelected", "onSelected")

    m.matchTotal = 0
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
    svc.qCollection = ""
    svc.qType = ""
    svc.qDecade = 0
    svc.qSort = "popular"
    svc.qText = q
    svc.queryId = svc.queryId + 1
    m.status.text = "Searching for “" + q + "”…"
end sub

sub showResults(root as Object, total as Integer)
    if Len(m.kb.text) < 2 then return
    m.allResults = root
    m.matchTotal = total
    ' The facet vocabularies are rebuilt from THESE results, so the chips can
    ' only ever offer something that exists in them.
    buildFacets(root)
    applyFilters()
end sub

sub buildFacets(root as Object)
    types = {} : decades = {}
    if root <> invalid
        for i = 0 to root.GetChildCount() - 1
            it = root.GetChild(i)
            if it.awType <> invalid and it.awType <> "" then types[fmt(it.awType)] = true
            y = Int(Val(Left(fmt(it.SHORTDESCRIPTIONLINE1), 4)))
            if y > 1800 then decades[fmt(Int(y / 10) * 10) + "s"] = true
        end for
    end if
    tv = ["All"]
    for each k in types
        tv.Push(prettyFacet(k))
    end for
    dv = ["All"]
    ' Sorted, because an associative array hands them back in whatever order it
    ' pleases and a decade list out of order reads as a bug.
    years = []
    for each k in decades
        years.Push(k)
    end for
    for i = 0 to years.Count() - 2
        for j = 0 to years.Count() - 2 - i
            if years[j] > years[j + 1]
                t = years[j] : years[j] = years[j + 1] : years[j + 1] = t
            end if
        end for
    end for
    for each y in years
        dv.Push(y)
    end for
    m.chipDefs[0].values = tv
    m.chipDefs[1].values = dv
    if m.chipIndex[0] >= tv.Count() then m.chipIndex[0] = 0
    if m.chipIndex[1] >= dv.Count() then m.chipIndex[1] = 0
    ' Two values means "All" plus one — nothing to choose between.
    m.chipGroup.visible = (tv.Count() > 2 or dv.Count() > 2)
    paintChips()
end sub

function prettyFacet(t as String) as String
    if t = "feature-film" then return "Feature Film"
    if t = "tv-series" then return "TV Series"
    if t = "tv-special" then return "TV Special"
    if t = "tv-episode" then return "TV Episode"
    if t = "silent-film" then return "Silent Era"
    if t = "short-film" then return "Short Film"
    return titleFacet(t)
end function

function titleFacet(t as String) as String
    if t = "" then return t
    return UCase(Left(t, 1)) + Mid(t, 2)
end function

sub paintChips()
    for i = 0 to m.chips.Count() - 1
        d = m.chipDefs[i]
        m.chips[i].text = displayValue(d, d.values[m.chipIndex[i]])
    end for
    layoutChips()
end sub

' F9 — a chip opens a picker (ROKU-DESIGN §6.3), never cycles.
sub onChipPressed()
    i = m.chipFocus
    d = m.chipDefs[i]
    vals = []
    for each v in d.values
        vals.Push(displayValue(d, v))
    end for
    t = "Type"
    if d.id = "decade" then t = "Decade"
    m.top.pickChip = { index: i, title: t, values: vals, current: m.chipIndex[i] }
end sub

function displayValue(d as Object, v as String) as String
    if v = "All"
        ' Search spans the whole catalog, TV included — the facet list is
        ' built from what the RESULTS actually contain — so this chip must
        ' not claim films.
        if d.id = "type" then return "All types"
        if d.id = "decade" then return "Any decade"
    end if
    return v
end function

sub applyChip(spec as Object)
    if spec = invalid or spec.index = invalid then return
    i = spec.index
    if i < 0 or i >= m.chipDefs.Count() then return
    if spec.value <> invalid and spec.value >= 0 and spec.value < m.chipDefs[i].values.Count()
        m.chipIndex[i] = spec.value
    end if
    paintChips()
    applyFilters()
end sub

sub applyFilters()
    root = m.allResults
    wantType = ""
    if m.chipIndex[0] > 0 then wantType = m.chipDefs[0].values[m.chipIndex[0]]
    wantDec = ""
    if m.chipIndex[1] > 0 then wantDec = m.chipDefs[1].values[m.chipIndex[1]]

    out = CreateObject("roSGNode", "ContentNode")
    n = 0
    if root <> invalid
        for i = 0 to root.GetChildCount() - 1
            it = root.GetChild(i)
            if wantType <> "" and prettyFacet(fmt(it.awType)) <> wantType then continue for
            if wantDec <> ""
                y = Int(Val(Left(fmt(it.SHORTDESCRIPTIONLINE1), 4)))
                if fmt(Int(y / 10) * 10) + "s" <> wantDec then continue for
            end if
            out.AppendChild(it.Clone(false))
            n = n + 1
        end for
    end if
    m.grid.content = out
    m.grid.visible = (n > 0)
    m.doorGroup.visible = (n = 0 and wantType = "" and wantDec = "")
    m.doorsLabel.visible = m.doorGroup.visible

    if n = 0
        if wantType <> "" or wantDec <> ""
            m.status.text = "No results left after those filters. Set them back to All."
        else
            m.status.text = "Nothing matches “" + m.kb.text + "”. Try fewer letters, or a door."
        end if
    else
        ' "Press Right to browse them" implied ONE press. The MiniKeyboard
        ' owns its own arrows, so Right walks the letter grid and leaves it
        ' only from the last column — six presses from "a". A Fast-forward
        ' shortcut was tried and REVERTED: measured on the device, Roku does
        ' not deliver the transport keys (Fwd/Rev/Play) to a screen that is
        ' not playing video, so the branch was dead code the moment it was
        ' written. Walking out of the keyboard is the platform idiom; the
        ' line now describes it accurately.
        ' The line states the RESULT and nothing else. "Press Right past the
        ' keyboard" was instruction, and the owner's rule is that navigation
        ' is never narrated on screen — the results are visibly to the right.
        ' The TRUE match count, not the grid's render cap. The service found
        ' thousands for a common stem; "300 titles match" (the cap) undersold
        ' it, where Browse honestly shows its full total.
        shown = m.matchTotal
        if wantType <> "" or wantDec <> "" then shown = n
        m.status.text = AWPlural(shown, "title") + " match “" + m.kb.text + "”"
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
    if m.zone = 3 and m.chipGroup.visible
        m.chips[m.chipFocus].setFocus(true)
    else if m.zone = 2 and m.grid.visible
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
        ' Right reaches here only once the MiniKeyboard has run out of columns
        ' — it owns its own arrows and consumes every Right until then. Roku
        ' does not deliver Fwd to a non-video screen (measured; see onResults).
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
    else if m.zone = 3
        ' The filter chips. They had NO handler and the grid never sent Up to
        ' them, so the row the parity table called "present-facets-only" was
        ' unreachable by remote — a dead control found only by tracing the
        ' flow to its console line (lesson 93).
        if key = "right"
            if m.chipFocus < m.chips.Count() - 1
                m.chipFocus = m.chipFocus + 1 : focusHere()
            end if
            return true
        else if key = "left"
            if m.chipFocus > 0
                m.chipFocus = m.chipFocus - 1 : focusHere() : return true
            end if
            m.zone = 0 : focusHere() : return true
        else if key = "down"
            if m.grid.visible then m.zone = 2 else m.zone = 0
            focusHere() : return true
        end if
    else
        if key = "left"
            if m.grid.itemFocused mod m.grid.numColumns = 0
                m.zone = 0 : focusHere() : return true
            end if
        else if key = "up"
            ' Top row of results -> the chips above them.
            if m.grid.itemFocused < m.grid.numColumns and m.chipGroup.visible
                m.zone = 3 : focusHere() : return true
            end if
        end if
    end if
    return false
end function

' Entering Search from the nav starts a fresh query. Without this the previous
' query survives inside the MiniKeyboard for the life of the channel, so
' reopening Search silently resumes someone else's search.
sub resetSearch()
    m.chipIndex = [0, 0]
    m.chipFocus = 0
    m.chipGroup.visible = false
    m.allResults = invalid
    m.kb.text = ""
    m.zone = 0
    m.doorIndex = 0
    m.grid.visible = false
    m.doorGroup.visible = true
    m.doorsLabel.visible = true
    m.status.text = "Type to search 26,965 titles — or pick a door."
    focusHere()
end sub

' F9/F19 — search chips fit their value, laid left to right (see BrowseScreen).
sub layoutChips()
    x = 0
    for i = 0 to m.chips.Count() - 1
        b = m.chips[i]
        w = AWTextWidth(m.chipGroup, m.t.uRow, b.text) + 72
        if w < 150 then w = 150
        w = Int(w / 3) * 3
        b.minWidth = w
        b.translation = [x, 0]
        AWPillLayout(m.restPills[i], x, 0, w)
        x = x + w + 18
    end for
    if m.fitTimer = invalid
        m.fitTimer = m.top.CreateChild("Timer")
        m.fitTimer.duration = 0.05
        m.fitTimer.ObserveField("fire", "onFitPills")
    end if
    m.fitTimer.control = "start"
end sub

sub onFitPills()
    AWFitPillRow(m.chips, m.restPills, 18)
    AWFitPillColumn(m.doors, m.doorPills)
end sub
