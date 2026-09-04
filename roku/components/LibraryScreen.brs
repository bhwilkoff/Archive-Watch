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
    m.rows.itemSize = [1740, m.t.posterFH + 180]
    m.rows.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.rows.rowItemSpacing = [[m.t.gutter, 0]]
    m.rows.rowSpacing = 24
    m.rows.showRowLabel = [true]
    m.rows.rowLabelFont = m.t.uRow
    m.rows.rowLabelColor = m.t.textPri
    m.rows.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.rows.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.rows.drawFocusFeedbackOnTop = true
    m.rows.ObserveField("rowItemSelected", "onSelected")
    m.rows.ObserveField("rowItemFocused", "onRowFocused")
    m.rowMeta = []
end sub

' Built from the ids the registry holds, resolved against the catalog the
' service already has in memory — Library never fetches anything of its own.
sub reload(catalog as Object)
    root = CreateObject("roSGNode", "ContentNode")
    cw = awContinueWatching()
    favs = awFavorites()

    m.rowMeta = []
    print "AWPL library playlists="; awPlaylists().Count()
    added = addRow(root, "Continue Watching", cw, catalog, true, "")
    added = added + addRow(root, "Favorites", favs, catalog, false, "")
    ' Playlists follow the two built-in rows, in creation order — the viewer
    ' made them, so they are not re-sorted underneath them.
    for each p in awPlaylists()
        added = added + addRow(root, p.name, p.ids, catalog, false, p.id)
    end for
    ' Watched comes LAST: it is a record, not a recommendation, and putting it
    ' above the playlists a viewer made would bury their own work under ours.
    watched = []
    for each r in awProgressRows()
        if r.dur > 0 and r.posn >= (r.dur * 95) / 100 then watched.Push(r.id)
    end for
    added = added + addRow(root, "Watched", watched, catalog, false, "")

    m.rows.content = root
    m.rows.visible = (added > 0)
    m.empty.visible = (added = 0)
    if added = 0
        m.empty.text = "Nothing saved yet. Press Save on any film, add one to a playlist from More, or just start watching — where you stopped shows up here."
    end if

    ' §7.2 — the budget is real and finite, so say where it stands rather than
    ' waiting to fail silently at the cap.
    used = awStorageUsed()
    ' Report BYTES until there are kilobytes to report — "0 KB of 32 KB" reads
    ' like a broken meter when the truth is that a few saves cost almost nothing.
    if used < 1024
        m.budget.text = fmt(favs.Count()) + " saved  ·  " + fmt(cw.Count()) + " in progress  ·  " + fmt(awPlaylists().Count()) + " playlists  ·  " + fmt(used) + " bytes of 32 KB used"
    else
        m.budget.text = fmt(favs.Count()) + " saved  ·  " + fmt(cw.Count()) + " in progress  ·  " + fmt(awPlaylists().Count()) + " playlists  ·  " + fmt(Int(used / 1024)) + " KB of 32 KB used"
    end if
end sub

function addRow(root as Object, title as String, entries as Object, catalog as Object, isProgress as Boolean, plID as String) as Integer
    if entries.Count() = 0 then return 0
    row = root.CreateChild("ContentNode")
    row.title = title
    n = 0
    for each e in entries
        id = e
        if isProgress then id = e.id
        src = findInCatalog(catalog, id)
        if src <> invalid
            it = row.CreateChild("ContentNode")
            it.id = src.id
            it.title = src.title
            it.HDPOSTERURL = src.HDPOSTERURL
            it.SHORTDESCRIPTIONLINE1 = src.SHORTDESCRIPTIONLINE1
            n = n + 1
        end if
    end for
    if n = 0
        root.RemoveChild(row)
        return 0
    end if
    m.rowMeta.Push(plID)
    return 1
end function

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

function findInCatalog(catalog as Object, id as String) as Object
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
    if m.top.focusOn and m.rows.visible then m.rows.setFocus(true)
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
