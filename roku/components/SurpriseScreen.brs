' Each door is (id, label, what it does, accent category). The `type:` doors
' land on a random film's Detail; `browse:` doors open Browse already scoped,
' because "show me a decade" is a place to wander, not one film.
function surpriseDoors() as Object
    ' F17 — twelve doors, four rows of three, ALL on screen: the fifth row of
    ' the old fifteen sat below 1080 and the grid never scrolled to it. The
    ' set mirrors the tvOS SurpriseView (a dozen tiles). "Random Film" is a
    ' FEATURE — the "anything at all" door handed the owner a TV special —
    ' and TV is a random SERIES (the show), as tvOS does, never a loose
    ' episode without art. Documentary is gone: the catalog holds four.
    return [
        { id: "type:feature-film", label: "Random Film",       sub: "A full-length picture",         cat: "feature-film" },
        { id: "type:silent-film",  label: "Random Silent",     sub: "Before the talkies",            cat: "silent-film" },
        { id: "type:animation",    label: "Random Animation",  sub: "Ink, paint and cels",           cat: "animation" },
        { id: "type:tv-series",    label: "Random TV Series",  sub: "Drop into a show",              cat: "tv-series" },
        { id: "type:newsreel",     label: "Random Newsreel",   sub: "The week as it was told",       cat: "newsreel" },
        { id: "type:ephemeral",    label: "Random Ephemera",   sub: "Industrial and educational",    cat: "ephemeral" },
        { id: "type:commercial",   label: "Random Commercial", sub: "Vintage advertising",           cat: "commercial" },
        { id: "type:short-film",   label: "Random Short",      sub: "Under twenty minutes",          cat: "short-film" },
        { id: "browse:decade",     label: "Random Decade",     sub: "Wander a whole era",            cat: "feature-film" },
        { id: "party",             label: "Party Play",        sub: "Colour films, shuffled, muted", cat: "animation" },
        { id: "cartoonmode",       label: "Cartoon Mode",      sub: "Shelves by character",          cat: "animation" },
        { id: "wall",              label: "Cover Art Wall",    sub: "The archive, as posters",       cat: "feature-film" }
    ]
end function

sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.hint = m.top.FindNode("hint")
    m.grid = m.top.FindNode("grid")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Surprise"

    m.hint.font = m.t.uMeta : m.hint.color = m.t.textSec
    m.hint.translation = [42, 204]
    m.hint.text = "Twelve doors into 26,000 films. Every one of them re-rolls."

    m.grid.translation = [42, 276]
    m.grid.itemComponentName = "ActionTile"
    m.grid.numColumns = 3
    m.grid.numRows = 4
    m.grid.itemSize = [528, 162]
    m.grid.itemSpacing = [24, 24]
    ' The TILE draws its own ring (§13.3); the grid's bitmap would be a
    ' second, concentric one — which is what the glass showed.
    m.grid.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.drawFocusFeedbackOnTop = true
    m.grid.vertFocusAnimationStyle = "floatingFocus"
    m.grid.ObserveField("itemSelected", "onSelected")

    m.doors = surpriseDoors()
    root = CreateObject("roSGNode", "ContentNode")
    for each d in m.doors
        n = root.CreateChild("ContentNode")
        n.title = d.label
        n.SHORTDESCRIPTIONLINE1 = d.sub
        n.SHORTDESCRIPTIONLINE2 = d.cat
    end for
    m.grid.content = root
end sub

sub onSelected()
    i = m.grid.itemSelected
    if i >= 0 and i < m.doors.Count() then m.top.action = m.doors[i].id
end sub

sub onFocusOn()
    if m.top.focusOn then m.grid.setFocus(true)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if key = "left"
        if m.grid.itemFocused mod m.grid.numColumns = 0
            m.top.exitLeft = true
            return true
        end if
    end if
    return false
end function
