sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.chipGroup = m.top.FindNode("chips")
    m.grid = m.top.FindNode("grid")
    m.empty = m.top.FindNode("empty")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 120]
    ' The count sits under the heading at Meta — a number in the display
    ' face at heading size competed with the screen's own name.
    m.count = m.top.FindNode("count")
    m.count.font = m.t.uMeta : m.count.color = m.t.textSec
    m.count.translation = [42, 186]

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [42, 400] : m.empty.width = 1200 : m.empty.wrap = true

    m.grid.translation = [42, 336]
    m.grid.itemComponentName = "GridTile"
    m.grid.numColumns = 7
    m.grid.numRows = 2
    ' §13.10 — the cell reserve is the focused poster plus a two-line
    ' caption and nothing more; 393 left 126 px of black between rows.
    ' F10 — the cell reserves two caption lines under the focused 315 px art.
    m.grid.itemSize = [210, 434]
    m.grid.itemSpacing = [24, 12]
    ' The TILE rings its own art (ROKU-DESIGN §5.4a). An explicitly transparent
    ' 9-patch is required: with no bitmap the list draws its own grey box.
    m.grid.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
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
    ' F25 — the Type chip's vocabulary belongs to the TAB. One shared list let
    ' the TV tab filter to "Feature Film" and the Movies tab to "Classic TV",
    ' which is the owner's report. "All" is scoped too, by qScope in the
    ' service, so it means "all television" on the TV tab.
    m.typeValues = {
        movies: ["All", "Feature Film", "Silent Era", "Animation", "Short Film", "Newsreel", "Documentary"],
        tv:     ["All", "Series", "Specials"]
    }
    m.scopeNow = "movies"
    m.chipDefs = [
        { id: "type",   label: "Type",   values: ["All", "Feature Film", "Silent Era", "Animation", "Short Film", "Newsreel", "Documentary"] },
        { id: "decade", label: "Decade", values: ["All", "1900s", "1910s", "1920s", "1930s", "1940s", "1950s", "1960s", "1970s"] },
        { id: "genre",  label: "Genre",  values: ["All", "Drama", "Comedy", "Animation", "Crime", "Romance", "Action", "Western", "Documentary", "Thriller", "Horror", "Mystery", "Adventure", "War", "Family", "Fantasy"] },
        { id: "sort",   label: "Sort",   values: ["Popular", "Newest", "Oldest", "A-Z", "Top Rated", "Shuffle"] }
    ]
    m.chipIndex = [0, 0, 0, 0]
    m.chips = []
    m.restPills = []
    x = 0
    for i = 0 to m.chipDefs.Count() - 1
        ' §13.5 — the rest state is OURS to draw: a Button only paints its
        ' focus bitmap, so without this the unfocused chips were bare text.
        rest = AWPillBuild(m.chipGroup)
        AWPillLayout(rest, x, 0, 300)
        b = m.chipGroup.CreateChild("Button")
        b.translation = [x, 0]
        ' Four chips now, so each is narrower: 4 x 390 fits the content column
        ' where 4 x 429 did not.
        b.minWidth = 300
        b.height = 60
        b.textColor = m.t.textPri
        ' The focus ring is a RING with a transparent centre, so the button
        ' keeps the page behind it when focused. Near-black focused text was
        ' therefore invisible: the chip read as an empty box.
        b.focusedTextColor = m.t.marquee
        ' §13.5 — a chip is a pill. The Button node's own bitmaps are the
        ' cheapest way to get one: rest and focus are the two pill 9-patches
        ' (lists strip the guide border; a Button is a list of one).
        b.focusBitmapUri = "pkg:/images/pill_focus.9.png"
        b.focusFootprintBitmapUri = "pkg:/images/pill_rest.9.png"
        b.focusedTextColor = m.t.canvas
        ' Roku's Button ships a decorative bullet to the left of its text. It
        ' means nothing on a filter chip and reads as a stray dot; blanking the
        ' uri is the only way to be rid of it.
        b.iconUri = ""
        b.focusedIconUri = ""
        b.ObserveField("buttonSelected", "onChipSelected")
        m.chips.Push(b)
        m.restPills.Push(rest)
        x = x + 336
    end for
    m.chipGroup.translation = [42, 240]
    m.focusRow = 0      ' 0 = chips, 1 = grid
    m.focusChip = 0
    m.collectionID = ""
    paintChips()
end sub

' F9 — ROKU-DESIGN §6.3: "a chip opens a dialog". Cycling in place was the
' wrong reading of that rule; a chip now hands the Scene a picker spec and
' the Scene opens the options panel on the current value.
sub onChipSelected()
    print "AWBROWSE chipSelected "; m.focusChip
    i = m.focusChip
    d = m.chipDefs[i]
    vals = []
    for each v in d.values
        vals.Push(displayValue(d, v))
    end for
    m.top.pickChip = { index: i, title: chipTitle(d.id), values: vals, current: m.chipIndex[i] }
end sub

function chipTitle(id as String) as String
    if id = "type" then return "Type"
    if id = "decade" then return "Decade"
    if id = "genre" then return "Genre"
    if id = "sort" then return "Sort by"
    return id
end function

function displayValue(d as Object, v as String) as String
    ' A chip states its VALUE. "Type: Feature Film" read as a settings
    ' form; "Feature Film" reads as what is on the grid.
    if v = "All"
        ' The chip states what is on the grid, so on the TV tab it must say
        ' TV. "All films" was hardcoded here and survived F25's scoping — the
        ' values array was made tab-aware and its DISPLAY was not.
        if d.id = "type"
            if m.scopeNow = "tv" then return "All TV"
            return "All films"
        end if
        if d.id = "decade" then return "Any decade"
        if d.id = "genre" then return "Any genre"
    end if
    if d.id = "sort" and v = "Popular" then return "Most popular"
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
    submit()
end sub

' F16 — a collection browsed as a grid: the heading is the collection, the
' chips leave (its membership IS the filter), and the service answers from
' the collection's own member list.
sub applyCollection(spec as Object)
    if spec = invalid or spec.id = invalid then return
    m.collectionID = spec.id
    m.heading.text = fmt(spec.title)
    m.chipIndex = [0, 0, 0, 0]
    m.chipGroup.visible = false
    m.focusRow = 1
    submit()
end sub

sub paintChips()
    for i = 0 to m.chips.Count() - 1
        d = m.chipDefs[i]
        m.chips[i].text = displayValue(d, d.values[m.chipIndex[i]])
    end for
    layoutChips()
end sub

' F9 — a chip pill fits its VALUE. Four fixed 300 px slabs left "A-Z" swimming
' in plate and "Most popular" cramped; each is now its label + 2 x 32 px, laid
' left to right with an 18 px gap, and the rest pill under it re-drawn to match.
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
    ' The Button's own font decides the real width; fit after one layout pass.
    if m.fitTimer = invalid
        m.fitTimer = m.top.CreateChild("Timer")
        m.fitTimer.duration = 0.05
        m.fitTimer.ObserveField("fire", "onFitChips")
    end if
    m.fitTimer.control = "start"
end sub

sub onFitChips()
    AWFitPillRow(m.chips, m.restPills, 18)
end sub

' Open Browse already scoped — used by the Surprise doors, where "a decade" is
' a place to wander rather than one film.
sub applyFilter(spec as Object)
    m.collectionID = ""
    m.chipGroup.visible = true
    m.focusRow = 0
    if spec.type <> invalid and spec.type <> ""
        for i = 0 to m.chipDefs[0].values.Count() - 1
            if typeValueToId(m.chipDefs[0].values[i]) = spec.type then m.chipIndex[0] = i
        end for
    else
        m.chipIndex[0] = 0
    end if
    if spec.decade <> invalid and spec.decade > 0
        want = fmt(spec.decade) + "s"
        for i = 0 to m.chipDefs[1].values.Count() - 1
            if m.chipDefs[1].values[i] = want then m.chipIndex[1] = i
        end for
        m.heading.text = "The " + fmt(spec.decade) + "s"
    else
        m.chipIndex[1] = 0
    end if
    paintChips()
    submit()
end sub

sub onScope()
    s = m.top.scope
    ' F14 — "the filters should reset when you go from films to tv": decade,
    ' genre and sort carried over, so TV opened pre-narrowed by a Movies pick.
    m.chipIndex[1] = 0 : m.chipIndex[2] = 0 : m.chipIndex[3] = 0
    m.focusChip = 0
    m.collectionID = ""
    m.chipGroup.visible = true
    m.focusRow = 0
    if s = "tv"
        m.heading.text = "TV"
        m.scopeNow = "tv"
        m.chipDefs[0].values = m.typeValues.tv
    else
        m.heading.text = "Movies"
        m.scopeNow = "movies"
        m.chipDefs[0].values = m.typeValues.movies
    end if
    ' Land on "All" within the tab. Pre-selecting one value made the tab look
    ' like it was already filtered, and on TV it hid the specials entirely.
    m.chipIndex[0] = 0
    paintChips()
    submit()
end sub

function typeValueToId(v as String) as String
    if v = "All" then return ""
    if v = "Feature Film" then return "feature-film"
    ' On the TV tab the two values are the two KINDS of television: a spine
    ' (Decision 036's series card) and a one-off broadcast or complete-series
    ' upload. Neither crowds the other out, and neither can reach a film.
    if v = "Series" then return "tv-series"
    if v = "Specials" then return "tv-special"
    if v = "Silent Era" then return "silent-film"
    if v = "Animation" then return "animation"
    if v = "Short Film" then return "short-film"
    if v = "Newsreel" then return "newsreel"
    if v = "Documentary" then return "documentary"
    return ""
end function

sub submit()
    svc = m.top.service
    if svc = invalid
        print "AWBROWSE submit ABORTED — no service node"
        return
    end if
    svc.qCollection = m.collectionID
    ' A collection spans both kinds, so it is browsed unscoped.
    if m.collectionID <> "" then svc.qScope = "" else svc.qScope = m.scopeNow
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
    g = m.chipDefs[2].values[m.chipIndex[2]]
    if g = "All" then g = ""
    svc.qGenre = g
    sv = LCase(m.chipDefs[3].values[m.chipIndex[3]])
    if sv = "a-z" then sv = "alpha"
    if sv = "top rated" then sv = "rating"
    svc.qSort = sv
    svc.qText = ""
    ' One bump, after every field is set — the service triggers on this alone.
    print "AWBROWSE submit sort="; sv; " qid="; svc.queryId
    svc.queryId = svc.queryId + 1
end sub

sub showResults(root as Object, total as Integer)
    ' Top Rated needs index columns that only exist from schema 10. A device
    ' holding an older cached index gets an empty result, and an empty result
    ' with no explanation is the dead control this build keeps re-learning.
    if total = 0 and m.chipDefs[3].values[m.chipIndex[3]] = "Top Rated"
        m.grid.content = invalid
        m.grid.visible = false
        m.empty.visible = true
        m.empty.text = "Ratings are not in this catalog yet. They arrive with the next catalog refresh — try another sort in the meantime."
        return
    end if
    m.grid.content = root
    m.empty.visible = (total = 0)
    if total = 0
        m.empty.text = "Nothing matches those filters yet. Try widening the decade, or set Type to All."
    end if
    ' §6.3 — the count reads in the heading, which is the honest orientation
    ' cue on a 25,000-title catalog.
    base = m.heading.text
    if Instr(1, base, "  ·  ") > 0 then base = Left(base, Instr(1, base, "  ·  ") - 1)
    m.heading.text = base
    m.count.text = AWGroup(total) + " titles"
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
    if m.focusRow = 1 or not m.chipGroup.visible
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
            if m.grid.itemFocused < m.grid.numColumns and m.chipGroup.visible
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
