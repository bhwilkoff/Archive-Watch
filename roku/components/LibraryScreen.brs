sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.budget = m.top.FindNode("budget")
    m.empty = m.top.FindNode("empty")
    m.rows = m.top.FindNode("rows")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Library"

    m.budget.font = m.t.uMeta : m.budget.color = m.t.textSec
    m.budget.translation = [42, 198]

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    ' §4.3 — prose the viewer READS starts at the title-safe inset.
    m.empty.translation = [150, 396] : m.empty.width = 1200 : m.empty.wrap = true

    m.rows.translation = [42, 276]
    m.rows.itemComponentName = "PosterTile"
    m.rows.numRows = 2
    m.rows.rowFocusAnimationStyle = "floatingFocus"
    m.rows.vertFocusAnimationStyle = "fixedFocus"
    m.rows.itemSize = [1740, m.t.posterFH + 240]
    m.rows.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.rows.rowItemSpacing = [[m.t.gutter, 0]]
    m.rows.rowSpacings = [24]
    m.rows.showRowLabel = [true]
    m.rows.rowLabelFont = m.t.uRow
    m.rows.rowLabelColor = m.t.textPri
    ' The TILE draws the ring, around the art. Without an explicit bitmap the
    ' list falls back to its own grey box at CELL size — the very thing the
    ' owner reported as "much bigger than the poster".
    m.rows.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.rows.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.rows.drawFocusFeedbackOnTop = false
    m.rows.ObserveField("rowItemSelected", "onSelected")
    m.rows.ObserveField("rowItemFocused", "onRowFocused")
    m.rowMeta = []
end sub

' A pure RENDERER. It builds nothing and looks nothing up.
'
' The previous version was handed the catalog and searched it for every saved
' id, which meant the lookup lived on one side of a callFunc boundary and the
' data on the other. It failed twice for different reasons — once with good
' data it could not turn into rows, once with an argument that arrived empty —
' and both times Library showed its empty state while its own budget line said
' otherwise. Home has never had this problem because its task builds the rows
' and its screen only draws them. This now does the same.
sub showRows(payload as Object)
    root = payload.rows
    m.rowMeta = payload.meta
    n = 0
    if root <> invalid then n = root.GetChildCount()
    m.rows.content = root
    m.rows.visible = (n > 0)
    m.empty.visible = (n = 0)
    if n = 0
        m.empty.text = "Nothing saved yet. Press Save on any film, add one to a playlist from More, or just start watching — where you stopped shows up here."
    end if
    m.budget.text = payload.budget
end sub

sub onRowFocused()
    idx = m.rows.rowItemFocused
    if idx = invalid then return
    if idx[0] >= 0 and idx[0] < m.rowMeta.Count()
        m.top.focusedPlaylist = m.rowMeta[idx[0]]
    else
        m.top.focusedPlaylist = ""
    end if
    if m.rows.content <> invalid
        row = m.rows.content.GetChild(idx[0])
        if row <> invalid
            it = row.GetChild(idx[1])
            if it <> invalid then m.top.focusedItem = it.id
        end if
    end if
end sub

' The ids in the focused row, in order — what Play All needs.
function focusedRowIDs() as Object
    out = []
    idx = m.rows.rowItemFocused
    if idx = invalid or m.rows.content = invalid then return out
    row = m.rows.content.GetChild(idx[0])
    if row = invalid then return out
    for i = 0 to row.GetChildCount() - 1
        out.Push(row.GetChild(i).id)
    end for
    return out
end function

' Two sources, searched in order: the viewer's OWN resolved items (a flat list
' straight from the service, which covers anything in the 26,965-row index),
' then Home's shelves. The previous version cloned both into one synthetic
' tree and lost 24 of 27 rows doing it — a lookup does not need a new tree,
' it needs both places to look.
function findInCatalog(catalog as Object, id as String) as Object
    if catalog = invalid then return invalid
    if catalog.mine <> invalid
        mine = catalog.mine
        for i = 0 to mine.GetChildCount() - 1
            it = mine.GetChild(i)
            if it.id = id then return it
        end for
    end if
    if catalog.shelves <> invalid then return findInRows(catalog.shelves, id)
    return findInRows(catalog, id)
end function

function findInRows(catalog as Object, id as String) as Object
    if catalog = invalid then return invalid
    for i = 0 to catalog.GetChildCount() - 1
        row = catalog.GetChild(i)
        for j = 0 to row.GetChildCount() - 1
            it = row.GetChild(j)
            if it.id = id then return it
        end for
    end for
    return invalid
end function

sub onSelected()
    idx = m.rows.rowItemSelected
    if m.rows.content = invalid then return
    row = m.rows.content.GetChild(idx[0])
    if row = invalid then return
    it = row.GetChild(idx[1])
    if it <> invalid then m.top.chosen = it.id
end sub

sub onFocusOn()
    if not m.top.focusOn then return
    ' A screen that CANNOT take focus traps the viewer on the previous one.
    ' This used to claim focus only when the rows were visible, so an empty
    ' Library left focus on whatever was underneath — a sweep found Select
    ' here starting a channel, because Channels still held it. When there are
    ' no rows the Group itself takes focus, which is enough for Back and Left
    ' to reach this screen's own key handler.
    if m.rows.visible
        m.rows.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if key = "left"
        idx = m.rows.rowItemFocused
        if idx <> invalid and idx[1] = 0
            m.top.exitLeft = true
            return true
        end if
    end if
    return false
end function
