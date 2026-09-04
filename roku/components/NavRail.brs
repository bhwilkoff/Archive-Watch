' The seven surfaces of ROKU-DESIGN §2.2, in order.
function railItems() as Object
    return [
        { id: "home",        label: "Home" },
        { id: "movies",      label: "Movies" },
        { id: "tv",          label: "TV" },
        { id: "channels",    label: "Channels" },
        { id: "collections", label: "Collections" },
        { id: "surprise",    label: "Surprise" },
        { id: "search",      label: "Search" },
        { id: "library",     label: "Library" }
    ]
end function

sub init()
    m.t = Theme()
    m.items = railItems()
    m.index = 0
    m.ground = m.top.FindNode("ground")
    m.holder = m.top.FindNode("items")

    m.ground.width = m.t.railW
    m.ground.height = 1080

    m.rows = []
    y = m.t.contentY
    for each it in m.items
        g = m.holder.CreateChild("Group")
        g.translation = [0, y]

        pill = g.CreateChild("Rectangle")
        pill.width = m.t.railExpandedW - 24
        pill.height = 66
        pill.translation = [12, 0]
        pill.color = "0x00000000"
        ' §13.4 — rounded, via the shared frame's corner overlays.
        frame = AWFrameBuild(g)

        ' Collapsed, each surface is its ICON. A bar carries POSITION — which
        ' of eight you are on — but not IDENTITY, and identity is the whole
        ' point of a collapsed rail: it has to answer "which one is Search"
        ' without expanding. The glyphs are single-colour PNGs tinted through
        ' blendColor, so one asset serves the dim, selected and focused states.
        mark = g.CreateChild("Poster")
        mark.uri = "pkg:/images/nav/" + it.id + ".png"
        mark.width = 48 : mark.height = 48
        mark.translation = [18, 9]

        lbl = g.CreateChild("Label")
        lbl.text = it.label
        lbl.translation = [84, 18]
        lbl.color = m.t.textSec
        lbl.font = m.t.uMeta
        lbl.visible = false

        m.rows.Push({ pill: pill, label: lbl, mark: mark, frame: frame })
        y = y + 78
    end for

    paint()
end sub

' §5.5 — the rail's selected item carries marquee orange; the FOCUSED item
' carries the ring. Colour alone is never the only focus signal, so the focused
' row also brightens its label.
sub paint()
    expanded = m.top.focusOn
    m.ground.width = m.t.railW
    pw = m.t.railW - 24
    if expanded
        m.ground.width = m.t.railExpandedW
        pw = m.t.railExpandedW - 24
    end if

    for i = 0 to m.rows.Count() - 1
        r = m.rows[i]
        isSel = (i = m.index)
        hasFocus = isSel and expanded
        ' The pill has to shrink WITH the rail. Left at its expanded width it
        ' painted a 264px highlight across the collapsed column and over the
        ' hero title beside it — visible only on the glass.
        r.pill.width = pw
        r.label.visible = expanded
        ' The icon stays put when the rail expands and the label appears BESIDE
        ' it — a rail whose icons vanish on expand makes the two states look
        ' like different navigations.
        r.mark.visible = true
        ' Corner overlays are canvas-coloured; over a TRANSPARENT pill they
        ' showed as four dark notches on every unselected row.
        AWFramePlace(r.frame, r.pill, false)
        for each c in r.frame.corners
            c.visible = (hasFocus or isSel)
        end for
        if hasFocus
            r.pill.color = m.t.textPri
            r.label.color = "0x0B0B0CFF"
            r.mark.blendColor = "0x0B0B0CFF"
        else if isSel
            r.pill.color = "0xEB553144"
            r.label.color = m.t.textPri
            r.mark.blendColor = m.t.marquee
        else
            r.pill.color = "0x00000000"
            r.label.color = m.t.textSec
            r.mark.blendColor = "0x8A8F98FF"
        end if
        ' Selected but NOT focused: the pill is a dim wash, so the glyph is the
        ' thing carrying the state and stays marquee.
        if isSel and not expanded then r.mark.blendColor = m.t.marquee
    end for
end sub

sub onFocusOn()
    paint()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false

    if key = "up"
        if m.index > 0
            m.index = m.index - 1
            paint()
        end if
        return true
    else if key = "down"
        if m.index < m.rows.Count() - 1
            m.index = m.index + 1
            paint()
        end if
        return true
    else if key = "right" or key = "OK"
        ' Selecting a rail item hands focus back to the content column. The
        ' Scene owns that transition, so announce it rather than doing it here.
        m.top.selected = m.items[m.index].id
        return true
    end if
    return false
end function


sub onSyncID()
    id = m.top.syncID
    if id = "" then return
    for i = 0 to m.items.Count() - 1
        if m.items[i].id = id
            m.top.selectedIndex = i
            ' paint() reads the rail's own cursor, and so does the next Up or
            ' Down press — both must land on the surface actually on screen.
            m.index = i
        end if
    end for
    paint()
end sub
