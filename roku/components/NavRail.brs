' The seven surfaces of ROKU-DESIGN §2.2, in order.
function railItems() as Object
    return [
        { id: "home",        label: "Home" },
        { id: "movies",      label: "Movies" },
        { id: "tv",          label: "TV" },
        { id: "channels",    label: "Channels" },
        { id: "collections", label: "Collections" },
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
        pill.width = m.t.railW - 24
        pill.height = 66
        pill.translation = [12, 0]
        pill.color = "0x00000000"

        lbl = g.CreateChild("Label")
        lbl.text = it.label
        lbl.translation = [30, 18]
        lbl.color = m.t.textSec
        lbl.font = m.t.uMeta

        m.rows.Push({ pill: pill, label: lbl })
        y = y + 78
    end for

    paint()
end sub

' §5.5 — the rail's selected item carries marquee orange; the FOCUSED item
' carries the ring. Colour alone is never the only focus signal, so the focused
' row also brightens its label.
sub paint()
    for i = 0 to m.rows.Count() - 1
        r = m.rows[i]
        isSel = (i = m.index)
        hasFocus = isSel and m.top.focusOn
        if hasFocus
            r.pill.color = m.t.marquee
            r.label.color = "0x0B0B0CFF"
        else if isSel
            r.pill.color = "0xEB553144"
            r.label.color = m.t.textPri
        else
            r.pill.color = "0x00000000"
            r.label.color = m.t.textSec
        end if
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
