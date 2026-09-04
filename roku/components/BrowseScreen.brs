sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.chipGroup = m.top.FindNode("chips")
    m.grid = m.top.FindNode("grid")
    m.empty = m.top.FindNode("empty")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [42, 400] : m.empty.width = 1200 : m.empty.wrap = true

    m.grid.translation = [42, 306]
    m.grid.itemComponentName = "GridTile"
    m.grid.numColumns = 7
    m.grid.numRows = 2
    m.grid.itemSize = [210, 393]
    m.grid.itemSpacing = [24, 24]
    m.grid.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.grid.drawFocusFeedbackOnTop = true
    m.grid.vertFocusAnimationStyle = "floatingFocus"
    m.grid.ObserveField("itemSelected", "onSelected")

    ' §6.3 — Type, Decade and Sort, one focusable row above the grid.
    '
    ' These are real Button nodes, not styled Rectangles. A Group is NOT
    ' focusable: setFocus(true) on a Group whose descendants are all Rectangles
    ' and Labels silently does nothing, the Scene keeps focus, and this
    ' component's onKeyEvent never runs — which is exactly how the first build
    ' of this screen came out completely inert while looking correct in a
    ' screenshot.
    m.chipDefs = [
        { id: "type",   label: "Type",   values: ["All", "Feature Film", "Classic TV", "Silent Era", "Animation", "Short Film", "Newsreel", "Documentary"] },
        { id: "decade", label: "Decade", values: ["All", "1900s", "1910s", "1920s", "1930s", "1940s", "1950s", "1960s", "1970s"] },
        { id: "sort",   label: "Sort",   values: ["Popular", "Newest", "Oldest", "A-Z"] }
    ]
    m.chipIndex = [0, 0, 0]
    m.chips = []
    x = 0
    for i = 0 to m.chipDefs.Count() - 1
        b = m.chipGroup.CreateChild("Button")
        b.translation = [x, 0]
        b.minWidth = 390
        b.height = 60
        b.textColor = m.t.textPri
        ' The focus ring is a RING with a transparent centre, so the button
        ' keeps the page behind it when focused. Near-black focused text was
        ' therefore invisible: the chip read as an empty box.
        b.focusedTextColor = m.t.marquee
        b.focusBitmapUri = "pkg:/images/focus_ring.9.png"
        b.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
        b.ObserveField("buttonSelected", "onChipSelected")
        m.chips.Push(b)
        x = x + 429
    end for
    m.chipGroup.translation = [42, 216]
    m.focusRow = 0      ' 0 = chips, 1 = grid
    m.focusChip = 0
    paintChips()
end sub

sub onChipSelected()
    print "AWBROWSE chipSelected "; m.focusChip
    ' Cycle the chip in place. A dialog is the design's answer for long lists;
    ' with at most nine values, cycling is fewer presses and no new surface.
    i = m.focusChip
    d = m.chipDefs[i]
    m.chipIndex[i] = (m.chipIndex[i] + 1) mod d.values.Count()
    paintChips()
    submit()
end sub

sub paintChips()
    for i = 0 to m.chips.Count() - 1
        d = m.chipDefs[i]
        m.chips[i].text = d.label + ":  " + d.values[m.chipIndex[i]]
    end for
end sub

sub onScope()
    s = m.top.scope
    if s = "tv"
        m.heading.text = "TV"
        m.chipIndex[0] = 2
    else
        m.heading.text = "Movies"
        m.chipIndex[0] = 1
    end if
    paintChips()
    submit()
end sub

function typeValueToId(v as String) as String
    if v = "All" then return ""
    if v = "Feature Film" then return "feature-film"
    if v = "Classic TV" then return "tv-series"
    if v = "Silent Era" then return "silent-film"
    if v = "Animation" then return "animation"
    if v = "Short Film" then return "short-film"
    if v = "Newsreel" then return "newsreel"
    if v = "Documentary" then return "documentary"
    return ""
end function

sub submit()
    svc = m.top.service
    if svc = invalid then return
    svc.qType = typeValueToId(m.chipDefs[0].values[m.chipIndex[0]])
    dv = m.chipDefs[1].values[m.chipIndex[1]]
    if dv = "All"
        svc.qDecade = 0
    else
        ' Int(Val(x)), not Val(x).ToInt(). Val returns a Float PRIMITIVE,
        ' which has no member functions, so the method form compiles and then
        ' dies at runtime with "Member function not found" — the third variant
        ' of BrightScript's no-methods-on-return-values rule seen today.
        svc.qDecade = Int(Val(Left(dv, 4)))
    end if
    sv = LCase(m.chipDefs[2].values[m.chipIndex[2]])
    if sv = "a-z" then sv = "alpha"
    svc.qSort = sv
    svc.qText = ""
    ' One bump, after every field is set — the service triggers on this alone.
    svc.queryId = svc.queryId + 1
end sub

sub showResults(root as Object, total as Integer)
    m.grid.content = root
    m.empty.visible = (total = 0)
    if total = 0
        m.empty.text = "Nothing matches those filters yet. Try widening the decade, or set Type to All."
    end if
    ' §6.3 — the count reads in the heading, which is the honest orientation
    ' cue on a 25,000-title catalog.
    base = m.heading.text
    if Instr(1, base, "  ·  ") > 0 then base = Left(base, Instr(1, base, "  ·  ") - 1)
    m.heading.text = base + "  ·  " + fmt(total) + " titles"
end sub

sub onSelected()
    idx = m.grid.itemSelected
    if m.grid.content = invalid then return
    it = m.grid.content.GetChild(idx)
    if it <> invalid then m.top.chosen = it.id
end sub

sub onFocusOn()
    if m.top.focusOn then focusHere()
end sub

sub focusHere()
    print "AWBROWSE focusHere row="; m.focusRow; " chip="; m.focusChip
    if m.focusRow = 1
        m.grid.setFocus(true)
    else
        m.chips[m.focusChip].setFocus(true)
    end if
end sub

' Key events reach a component from the FOCUSED node upward, so this runs
' because a Button (chips) or the MarkupGrid (results) actually holds focus.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if press then print "AWBROWSE key="; key; " focusOn="; m.top.focusOn; " row="; m.focusRow
    if not press then return false
    if not m.top.focusOn then return false

    if m.focusRow = 0
        if key = "right"
            if m.focusChip < m.chips.Count() - 1
                m.focusChip = m.focusChip + 1 : focusHere()
            end if
            return true
        else if key = "left"
            if m.focusChip > 0
                m.focusChip = m.focusChip - 1 : focusHere() : return true
            end if
            m.top.exitLeft = true
            return true
        else if key = "down"
            m.focusRow = 1 : focusHere() : return true
        end if
    else
        if key = "up"
            if m.grid.itemFocused < m.grid.numColumns
                m.focusRow = 0 : focusHere() : return true
            end if
        else if key = "left"
            if m.grid.itemFocused mod m.grid.numColumns = 0
                m.top.exitLeft = true
                return true
            end if
        end if
    end if
    return false
end function
