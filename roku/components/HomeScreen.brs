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
    heroTop = 0
    heroH = 480
    m.heroH = heroH

    ' The hero is a PICTURE, full width, with the copy over it — the shape
    ' every television app uses, and the one the old layout was only gesturing
    ' at. A 792px image floating in the top-right of an otherwise empty band
    ' reads as a placeholder, not as a marquee.
    '
    ' Decision 097 still binds: a real landscape backdrop may be cropped to
    ' fill; a 2:3 poster may NOT, so that case keeps the fitted-art-on-the-
    ' right shape over an ambient wash.
    m.wash.translation = [-150, 0]
    m.wash.width = 1920 : m.wash.height = heroH
    m.wash.loadDisplayMode = "scaleToZoom"
    m.wash.opacity = 1.0

    m.scrim.translation = [-150, 0]
    m.scrim.width = 1920 : m.scrim.height = heroH
    m.scrim.color = "0x0B0B0C00"

    ' Roku has no gradient node, so the fade is four stacked rectangles. At ten
    ' feet the steps are invisible; what matters is that the copy always has
    ' something dark under it whatever the still happens to contain.
    fa = m.top.FindNode("heroFadeA")
    fb = m.top.FindNode("heroFadeB")
    fc = m.top.FindNode("heroFadeC")
    fbase = m.top.FindNode("heroFadeBase")
    fa.translation = [-150, 0] : fa.width = 800 : fa.height = heroH : fa.color = "0x0B0B0CF2"
    fb.translation = [650, 0]  : fb.width = 260 : fb.height = heroH : fb.color = "0x0B0B0CB3"
    fc.translation = [910, 0]  : fc.width = 260 : fc.height = heroH : fc.color = "0x0B0B0C66"
    ' The band under the hero, so the first shelf label never sits on a bright
    ' patch of film.
    fbase.translation = [-150, heroH - 120] : fbase.width = 1920 : fbase.height = 120
    fbase.color = "0x0B0B0CCC"

    ' Used only when the item has no landscape backdrop.
    m.art.translation = [1010, 96]
    m.art.width = 740 : m.art.height = 348
    m.art.loadDisplayMode = "scaleToFit"

    m.hTitle.font = m.t.uMarquee
    m.hTitle.color = m.t.textPri
    ' §4.3 — prose the viewer READS starts at the title-safe inset (192 from
    ' the screen edge; this Group is already 150 in).
    m.hTitle.translation = [m.t.readX, 246]
    m.hTitle.width = 780
    m.hTitle.maxLines = 2
    m.hTitle.wrap = true

    m.hMeta.font = m.t.uMeta
    m.hMeta.color = m.t.textSec
    m.hMeta.translation = [m.t.readX, 366]

    m.rows.translation = [m.t.safeX, 504]
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
    ' The cell must hold the row LABEL, the focused poster, a caption that
    ' wraps to two lines and the meta line under it: 48 + 432 + 9 + ~100 + 40.
    ' At +180 the meta ran into the NEXT row's label — the same overlap class
    ' three surfaces over, because all three shelves share these numbers.
    m.rows.itemSize = [1740, m.t.posterFH + 240]
    m.rows.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.rows.rowItemSpacing = [[m.t.gutter, 0]]
    m.rows.rowSpacing = 24
    m.rows.rowLabelOffset = [[0, 0]]
    m.rows.showRowLabel = [true]
    m.rows.rowTitleComponentName = ""
    ' §5.5 — the ring is a 9-patch drawn ON TOP so it reads against bright
    ' poster art; §5.6 the footprint marks where focus was when the row loses it.
    ' The TILE draws the ring, around the art. Without an explicit bitmap the
    ' list falls back to its own grey box at CELL size — the very thing the
    ' owner reported as "much bigger than the poster".
    m.rows.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.rows.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.rows.drawFocusFeedbackOnTop = false
    m.rows.drawFocusFeedback = true

    m.rows.rowLabelFont = m.t.uRow
    m.rows.rowLabelColor = m.t.textPri

    ' The hero ROTATES through the pool, the way it does on every other
    ' platform. It used to follow the focused tile, which meant the marquee
    ' changed on every press — busy, and it made a poster-less title blank the
    ' whole band. A carousel is the shape a hero is.
    m.heroTimer = m.top.FindNode("heroTimer")
    m.heroTimer.ObserveField("fire", "onHeroTick")
    m.heroIndex = 0
    m.rows.ObserveField("rowItemSelected", "onTileSelected")
end sub

sub onRows()
    if m.top.rowsContent = invalid then return
    m.rows.content = m.top.rowsContent
end sub

sub onHero()
    pool = m.top.heroContent
    if pool = invalid or pool.GetChildCount() = 0
        print "AWHERO pool empty"
        return
    end if
    print "AWHERO pool n="; pool.GetChildCount()
    m.heroIndex = 0
    paintHero(pool.GetChild(0))
    m.heroTimer.control = "start"
end sub

sub onHeroTick()
    pool = m.top.heroContent
    if pool = invalid or pool.GetChildCount() = 0 then return
    m.heroIndex = (m.heroIndex + 1) mod pool.GetChildCount()
    paintHero(pool.GetChild(m.heroIndex))
end sub

sub paintHero(it as Object)
    if it = invalid then return
    if it.awBackdrop <> invalid and it.awBackdrop <> ""
        m.wash.uri = it.awBackdrop
        m.wash.opacity = 1.0
        m.art.visible = false
    else if it.HDPOSTERURL <> invalid and it.HDPOSTERURL <> ""
        m.wash.uri = it.HDPOSTERURL
        m.wash.opacity = 0.5
        m.art.uri = it.HDPOSTERURL
        m.art.visible = true
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
