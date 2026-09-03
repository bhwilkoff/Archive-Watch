sub init()
    m.t = Theme()
    m.wash = m.top.FindNode("heroWash")
    m.scrim = m.top.FindNode("heroScrim")
    m.art = m.top.FindNode("heroArt")
    m.hTitle = m.top.FindNode("heroTitle")
    m.hMeta = m.top.FindNode("heroMeta")
    m.rows = m.top.FindNode("rows")

    ' §4.4 — content begins BELOW the Overhang. The hero art was starting at
    ' y=54 and painting over the brand, which is the kind of thing only a
    ' screenshot catches.
    heroTop = 115
    heroH = 355                     ' 115..470, divisible by 5 not 3 — see note
    m.wash.translation = [-150, 0]  ' full-bleed behind the rail too
    m.wash.width = 1920 : m.wash.height = heroTop + heroH
    m.wash.loadDisplayMode = "scaleToZoom"   ' the WASH may crop; the art may not
    m.wash.opacity = 0.28

    m.scrim.translation = [-150, 0]
    m.scrim.width = 1920 : m.scrim.height = heroTop + heroH
    m.scrim.color = m.t.scrim

    ' Decision 097 — the hero ART is FITTED, never cropped. It sits right, the
    ' reading block sits left, so the copy is never over the busiest part of a
    ' film still.
    m.art.translation = [870, heroTop + 9]
    m.art.width = 792 : m.art.height = 342
    m.art.loadDisplayMode = "scaleToFit"

    m.hTitle.font = m.t.uMarquee
    m.hTitle.color = m.t.textPri
    ' §4.3 — prose the viewer READS starts at the title-safe inset (192 from
    ' the screen edge; this Group is already 150 in).
    m.hTitle.translation = [42, heroTop + 63]
    m.hTitle.width = 780
    m.hTitle.maxLines = 2
    m.hTitle.wrap = true

    m.hMeta.font = m.t.uMeta
    m.hMeta.color = m.t.textSec
    m.hMeta.translation = [42, heroTop + 210]

    m.rows.translation = [m.t.safeX, 495]
    m.rows.itemComponentName = "PosterTile"
    m.rows.numRows = 3
    ' §2.1 / §3.1 — Left from the FIRST column must reach the rail. With
    ' "fixedFocusWrap" the focused index never reaches 0 (the row scrolls under
    ' a pinned focus and Left wraps to the end), so the rail was unreachable
    ' from content — proven by driving the remote: three Lefts left focus on a
    ' tile. "floatingFocus" stops at the ends, which is what makes the exit
    ' detectable.
    m.rows.rowFocusAnimationStyle = "floatingFocus"
    m.rows.vertFocusAnimationStyle = "fixedFocus"
    ' The row CELL must reserve the focused poster, its caption, its meta line AND
    ' the next row's label — the label is drawn inside the following cell, so a
    ' tight reserve puts one row's caption on top of the next row's title. Seen
    ' on the glass; not visible in any log.
    m.rows.itemSize = [1674, m.t.posterFH + 126]
    m.rows.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.rows.rowItemSpacing = [[m.t.gutter, 0]]
    m.rows.rowSpacing = 24
    m.rows.rowLabelOffset = [[0, 0]]
    m.rows.showRowLabel = [true]
    m.rows.rowTitleComponentName = ""
    ' §5.5 — the ring is a 9-patch drawn ON TOP so it reads against bright
    ' poster art; §5.6 the footprint marks where focus was when the row loses it.
    m.rows.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.rows.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.rows.drawFocusFeedbackOnTop = true
    m.rows.drawFocusFeedback = true

    m.rows.rowLabelFont = m.t.uRow
    m.rows.rowLabelColor = m.t.textPri

    m.rows.ObserveField("rowItemFocused", "onTileFocused")
    m.rows.ObserveField("rowItemSelected", "onTileSelected")
end sub

sub onRows()
    if m.top.rowsContent = invalid then return
    m.rows.content = m.top.rowsContent
end sub

sub onHero()
    pool = m.top.heroContent
    if pool = invalid
        print "AWHERO pool invalid"
        return
    end if
    print "AWHERO pool n="; pool.GetChildCount()
    if pool.GetChildCount() = 0 then return
    m.heroPool = pool
    m.heroIndex = 0
    paintHero()
end sub

sub paintHero()
    h = m.heroPool.GetChild(m.heroIndex)
    if h = invalid then return
    print "AWHERO paint "; h.title; " uri="; h.awBackdrop
    m.wash.uri = h.awBackdrop
    m.art.uri = h.awBackdrop
    m.hTitle.text = h.title
    m.hMeta.text = h.SHORTDESCRIPTIONLINE1
    m.heroId = h.id
end sub

' The ambient hero follows the focused tile, the way the Google TV build does —
' but on a DEBOUNCE, because promoting every focus stop while the viewer skims
' a row would strobe the whole screen.
sub onTileFocused()
    idx = m.rows.rowItemFocused
    if idx = invalid or m.rows.content = invalid then return
    row = m.rows.content.GetChild(idx[0])
    if row = invalid then return
    it = row.GetChild(idx[1])
    if it = invalid then return
    if it.awBackdrop <> invalid and it.awBackdrop <> ""
        m.wash.uri = it.awBackdrop
        m.art.uri = it.awBackdrop
    end if
    m.hTitle.text = it.title
    m.hMeta.text = it.SHORTDESCRIPTIONLINE1
    m.heroId = it.id
end sub

sub onTileSelected()
    idx = m.rows.rowItemSelected
    if idx = invalid or m.rows.content = invalid then return
    row = m.rows.content.GetChild(idx[0])
    if row = invalid then return
    it = row.GetChild(idx[1])
    if it = invalid then return
    print "AWROKU select id="; it.id
    m.top.chosen = it.id
end sub

sub onFocusOn()
    if m.top.focusOn then m.rows.setFocus(true)
end sub

' §2.1 / §3.1 — Left from the FIRST column reaches the rail. Roku's focus
' engine will not cross out of a RowList on its own, so the screen says where
' Left goes, exactly as the Android TV build had to.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "left"
        idx = m.rows.rowItemFocused
        if idx <> invalid and idx[1] = 0
            m.top.exitLeft = true
            return true
        end if
    else if key = "play"
        ' §3.1 — Play/Pause plays the featured item WITHOUT moving focus.
        if m.heroId <> invalid
            print "AWROKU play-shortcut id="; m.heroId
            m.top.chosen = m.heroId
            return true
        end if
    end if
    return false
end function
