sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.accent = m.top.FindNode("accent")
    m.blurb = m.top.FindNode("blurb")
    m.empty = m.top.FindNode("empty")
    m.rows = m.top.FindNode("rows")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Collections"

    ' A short rule in the collection's own accent, the same device Detail uses
    ' for its category chip — colour carries MEANING here, never decoration.
    m.accent.translation = [42, 202]
    m.accent.width = 96 : m.accent.height = 6
    m.accent.color = m.t.marquee

    m.blurb.font = m.t.uMeta : m.blurb.color = m.t.textSec
    m.blurb.translation = [156, 186]
    m.blurb.width = 1400 : m.blurb.maxLines = 1

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [150, 400] : m.empty.width = 1200 : m.empty.wrap = true

    m.rows.translation = [42, 258]
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
    m.rows.ObserveField("rowItemFocused", "onFocusedRow")
end sub

sub showResults(root as Object, total as Integer)
    m.rows.content = root
    m.rows.visible = (total > 0)
    m.empty.visible = (total = 0)
    if total = 0
        m.empty.text = "Collections could not be loaded. Check the network and try again."
        m.blurb.text = ""
    else
        paintBlurb(0)
    end if
end sub

sub onFocusedRow()
    idx = m.rows.rowItemFocused
    if idx <> invalid then paintBlurb(idx[0])
end sub

sub paintBlurb(rowIndex as Integer)
    if m.rows.content = invalid then return
    row = m.rows.content.GetChild(rowIndex)
    if row = invalid then return
    if row.awBlurb <> invalid then m.blurb.text = row.awBlurb
    if row.awAccent <> invalid and row.awAccent <> "" then m.accent.color = row.awAccent
end sub

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
