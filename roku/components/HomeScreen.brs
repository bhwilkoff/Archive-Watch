' Two-digit hex for an 8-bit alpha. BrightScript has no format specifier for
' this and Str() on a number carries a leading space.
function alphaHex(a as Integer) as String
    if a < 0 then a = 0
    if a > 255 then a = 255
    d = "0123456789ABCDEF"
    hi = Int(a / 16)
    lo = a - (hi * 16)
    return Mid(d, hi + 1, 1) + Mid(d, lo + 1, 1)
end function

sub init()
    m.t = Theme()
    m.wash = m.top.FindNode("heroWash")
    m.scrim = m.top.FindNode("heroScrim")
    m.art = m.top.FindNode("heroArt")
    m.hKind = m.top.FindNode("heroKind")
    m.hTitle = m.top.FindNode("heroTitle")
    m.hMeta = m.top.FindNode("heroMeta")
    m.rows = m.top.FindNode("rows")
    m.scroll = m.top.FindNode("scroll")
    m.scrollAnim = m.top.FindNode("scrollAnim")
    m.scrollInterp = m.top.FindNode("scrollInterp")
    m.hint = m.top.FindNode("heroHint")
    m.dots = m.top.FindNode("heroDots")

    ' §4.4 — content begins BELOW the Overhang. The hero art was starting at
    ' y=54 and painting over the brand, which is the kind of thing only a
    ' screenshot catches.
    heroTop = 0
    ' tvOS's hero is 940 of 1080, and that is WHY its backdrops look right: a
    ' 16:9 image filling a 1920x940 frame loses 13% off the top and bottom. The
    ' same image filling a 1920x384 band loses 64% — which is what "cropped
    ' terribly" was. The band is now 880 (18% crop) and it SCROLLS AWAY on
    ' Down, exactly as tvOS's does, so the shelves are never far.
    heroH = 880
    m.heroH = heroH

    ' The hero is a PICTURE, full width, with the copy over it — the shape
    ' every television app uses, and the one the old layout was only gesturing
    ' at. A 792px image floating in the top-right of an otherwise empty band
    ' reads as a placeholder, not as a marquee.
    '
    ' Decision 097 still binds: a real landscape backdrop may be cropped to
    ' fill; a 2:3 poster may NOT, so that case keeps the fitted-art-on-the-
    ' right shape over an ambient wash.
    ' The BACKDROP is the hero. It fills the band at full brightness and the
    ' gradient above it does the legibility work — a dimmed picture under a
    ' dark ramp is why this band "could hardly be seen".
    ' This Group sits at x = railW, so a 1920-wide band starting at -150 ends
    ' 66 px short of the right edge — a dark strip down the side of every
    ' hero, plainly visible in the screenshot and missed twice.
    m.wash.translation = [-150, 0]
    m.wash.width = 2070 : m.wash.height = heroH
    m.wash.loadDisplayMode = "scaleToZoom"
    m.wash.opacity = 1.0

    ' Retained but inert: the gradient PNG replaced it.
    m.scrim.visible = false

    ' tvOS layers a top-to-bottom LinearGradient over the backdrop — clear,
    ' clear, .45, .9, black — so the picture stays a picture and the copy sits
    ' on darkness at its foot. A left-to-right ramp (the previous build) dims
    ' the subject instead of the caption area, which is why the band read as
    ' murky. Roku has no gradient node, so this is that gradient as a PNG:
    ' geometry-based fakes band, and the owner saw the lines.
    fade = m.top.FindNode("heroFade")
    fade.uri = "pkg:/images/hero_scrim_v.png"
    fade.translation = [-150, 0]
    fade.width = 2070 : fade.height = heroH
    fade.loadDisplayMode = "scaleToFill"

    floor = m.top.FindNode("heroFloor")
    floor.visible = false

    ' Used only when the item has no landscape backdrop.
    m.art.translation = [1010, 96]
    m.art.width = 740 : m.art.height = 348
    m.art.loadDisplayMode = "scaleToFit"

    m.hKind.font = m.t.uMeta
    m.hKind.translation = [m.t.readX, heroH - 316]
    m.hTitle.font = m.t.uMarquee
    m.hTitle.color = m.t.textPri
    ' §4.3 — prose the viewer READS starts at the title-safe inset (192 from
    ' the screen edge; this Group is already 150 in).
    m.hTitle.translation = [m.t.readX, heroH - 260]
    m.hTitle.width = 780
    m.hTitle.maxLines = 2
    m.hTitle.wrap = true

    m.hMeta.font = m.t.uMeta
    m.hMeta.color = m.t.textSec
    m.hMeta.translation = [m.t.readX, heroH - 140]

    m.rows.translation = [m.t.safeX, 908]
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
    m.rows.itemSize = [1740, m.t.posterFH + 196]
    m.rows.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.rows.rowItemSpacing = [[m.t.gutter, 0]]
    ' `rowSpacing` DOES NOT EXIST on RowList — the field is `rowSpacings`, an
    ' array. Setting the singular logged "Tried to set nonexistent field" as a
    ' warning, not an error, so row spacing had simply never applied since the
    ' first build (ROKU-PARITY lesson 43).
    m.rows.rowSpacings = [24]
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
    ' A dead backdrop falls back to the film's poster rather than to whatever
    ' was on screen a moment ago.
    m.wash.ObserveField("loadStatus", "onHeroArtStatus")
    m.heroFallback = ""
    m.heroArtTimer = m.top.FindNode("heroArtTimer")
    m.heroArtTimer.ObserveField("fire", "onHeroArtDue")
    m.heroIndex = 0
    m.rows.ObserveField("rowItemSelected", "onTileSelected")
    m.rows.ObserveField("rowItemFocused", "onRowFocusTrace")

    ' The hero is a CONTROL, not a band. It takes focus, pages with Left/Right,
    ' opens the film on OK, and slides off the top when the viewer goes down —
    ' the tvOS HeroCarousel contract, expressed with the nodes Roku has.
    m.ringT = m.top.FindNode("heroRingT")
    m.ringB = m.top.FindNode("heroRingB")
    m.ringL = m.top.FindNode("heroRingL")
    m.ringR = m.top.FindNode("heroRingR")
    ' INSET into the title-safe area. Drawn flush to the screen edge the ring
    ' read as clipped — the top edge sat in overscan, which on a real panel is
    ' the half that gets cut.
    rx = 0 : ry = 30 : rw = 1812 : rh = heroH - 60 : th = 4
    m.ringT.translation = [rx, ry]           : m.ringT.width = rw : m.ringT.height = th
    m.ringB.translation = [rx, ry + rh - th] : m.ringB.width = rw : m.ringB.height = th
    m.ringL.translation = [rx, ry]           : m.ringL.width = th : m.ringL.height = rh
    m.ringR.translation = [rx + rw - th, ry] : m.ringR.width = th : m.ringR.height = rh
    ' No ring. A 1920x880 orange rectangle is not a focus indicator, it is a
    ' border around the screen — and the hero is the only focusable thing up
    ' here, so the moment focus leaves it the whole band scrolls away. That
    ' movement IS the indicator.
    for each r in [m.ringT, m.ringB, m.ringL, m.ringR]
        r.visible = false
    end for

    ' Says what OK does. A focusable hero with no affordance reads as a poster.
    m.hint.font = m.t.uMeta : m.hint.color = m.t.textPri
    m.hint.translation = [m.t.readX, heroH - 84]
    ' No instructions. A hero that has to explain Left and Right is a hero
    ' that does not read as one — the dots below it already say there is more,
    ' and OK on a focused thing is the platform's own contract.
    m.hint.text = ""
    m.hint.visible = false

    ' Page indicator, the tvOS capsule row rendered as Rectangles.
    m.dots.translation = [m.t.readX, heroH - 84]
    m.dotNodes = []

    m.focusZone = "hero"
    m.heroOffset = 0
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
    buildDots(pool.GetChildCount())
    paintHero(pool.GetChild(0))
    m.heroTimer.control = "start"
end sub

sub buildDots(n as Integer)
    while m.dots.GetChildCount() > 0
        m.dots.RemoveChildIndex(0)
    end while
    m.dotNodes = []
    if n <= 1 then return
    x = 0
    for i = 0 to n - 1
        d = m.dots.CreateChild("Rectangle")
        d.translation = [x, 0]
        d.height = 8
        d.width = 10
        d.color = "0xFFFFFF59"
        m.dotNodes.Push(d)
        x = x + 22
    end for
    paintDots()
end sub

sub paintDots()
    if m.dotNodes = invalid then return
    for i = 0 to m.dotNodes.Count() - 1
        if i = m.heroIndex
            m.dotNodes[i].width = 30
            m.dotNodes[i].color = "0xFFFFFFFF"
        else
            m.dotNodes[i].width = 10
            m.dotNodes[i].color = "0xFFFFFF59"
        end if
    end for
    ' The dots move as the widths change, so lay them out every time rather
    ' than once — a fixed 22px stride leaves the active capsule overlapping
    ' its neighbour.
    x = 0
    for i = 0 to m.dotNodes.Count() - 1
        m.dotNodes[i].translation = [x, 0]
        x = x + m.dotNodes[i].width + 12
    end for
end sub

sub onHeroTick()
    ' Rotating a hero nobody can see wastes image loads and, worse, means the
    ' banner has silently changed under the viewer by the time they scroll back
    ' up. tvOS advances a hero that is on screen; so does this.
    if m.focusZone <> "hero" then return
    advanceHero(1)
end sub

' `step` is RESERVED (`for … step`) and fails to compile as a parameter name —
' the same class as `pos`, `run` and `on` (ROKU-PARITY lesson 44).
sub advanceHero(delta as Integer)
    pool = m.top.heroContent
    if pool = invalid or pool.GetChildCount() = 0 then return
    n = pool.GetChildCount()
    m.heroIndex = ((m.heroIndex + delta) + n) mod n
    print "AWHERO index="; m.heroIndex
    paintHero(pool.GetChild(m.heroIndex))
    paintDots()
end sub

' The copy is free; the art is not. Paging updates the words immediately and
' DEFERS the image, so holding Right reads instantly and loads once — the
' remote-response measurement went from a 73 ms median to 165 ms (worst 621)
' the moment paging started loading a backdrop per press.
sub paintHero(it as Object)
    if it = invalid then return
    m.hTitle.text = it.title
    m.hMeta.text = it.SHORTDESCRIPTIONLINE1
    ' The category, in the category's own accent (Decision 013) — the line
    ' tvOS leads its hero copy with.
    kind = ""
    if it.HasField("awType") then kind = fmt(it.awType)
    if kind = "" then kind = "feature-film"
    m.hKind.text = AWTracked(UCase(KindLabel(kind)))
    m.hKind.color = AccentFor(kind)
    m.heroId = it.id
    m.pendingHeroArt = it
    m.heroArtTimer.control = "stop"
    m.heroArtTimer.control = "start"
end sub

sub onHeroArtStatus()
    if m.wash.loadStatus <> "failed" then return
    print "AWHERO backdrop failed, falling back"
    if m.heroFallback <> "" and m.wash.uri <> m.heroFallback
        f = m.heroFallback
        m.heroFallback = ""
        m.wash.uri = f
        m.wash.opacity = 0.85
        m.art.uri = f
        m.art.visible = true
    else
        m.wash.uri = ""
    end if
end sub

sub onHeroArtDue()
    it = m.pendingHeroArt
    if it = invalid
        print "AWHERO art due but nothing pending"
        return
    end if
    print "AWHERO art -> "; it.title
    paintHeroArt(it)
end sub

sub paintHeroArt(it as Object)
    if it = invalid then return
    ' Clear FIRST. A backdrop that fails to load leaves the previous one on
    ' screen, so the band showed "She Killed in Ecstasy" under the title "The
    ' Longest Day" — a picture that is merely absent is honest, one that
    ' belongs to a different film is not.
    m.wash.uri = ""
    m.art.visible = false
    m.heroFallback = ""
    if it.HDPOSTERURL <> invalid then m.heroFallback = it.HDPOSTERURL
    if it.awBackdrop <> invalid and it.awBackdrop <> ""
        m.wash.uri = it.awBackdrop
        m.wash.opacity = 1.0
        m.art.visible = false
    else
        ' tvOS puts a CATEGORY-ACCENT FIELD here when a film has no backdrop —
        ' never a 2:3 poster. A poster in a 2.2:1 band can only be cropped to
        ' ribbon or letterboxed into a box, and both look broken. Nothing to
        ' crop means nothing cropped.
        m.wash.uri = ""
        m.wash.opacity = 1.0
        m.art.uri = it.HDPOSTERURL
        m.art.visible = true
    end if
end sub

' The hero slides off the top and the shelves come with it — one Group, one
' animation, so nothing can drift out of register.
sub slideTo(y as Integer)
    if m.heroOffset = y then return
    m.scrollAnim.control = "stop"
    m.scrollInterp.keyValue = [[0, m.heroOffset], [0, y]]
    m.scrollAnim.control = "start"
    m.heroOffset = y
end sub

sub enterHero()
    print "AWHERO zone=hero"
    m.focusZone = "hero"
    slideTo(0)
    paintHeroFocus(true)
    m.top.setFocus(true)
end sub

sub enterRows()
    print "AWHERO zone=rows"
    m.focusZone = "rows"
    slideTo(-m.heroH)
    paintHeroFocus(false)
    m.rows.setFocus(true)
end sub

sub paintHeroFocus(lit as Boolean)
    m.hint.visible = false
    if m.dots <> invalid then m.dots.visible = (m.focusZone = "hero")
end sub

' Timestamped focus trace. Roku certification requires a response to a remote
' press within 250ms, and the only way to know is to measure from the press to
' the moment the app acts on it — a screenshot cannot time anything.
sub onRowFocusTrace()
    idx = m.rows.rowItemFocused
    if idx = invalid then return
    print "AWTILE focus "; idx[0]; ","; idx[1]
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

' The hero rotated on EVERY surface — a sweep of the whole app found
' `AWHERO index=` firing while Channels, Library and Search were on screen.
' A hidden hero that keeps loading art wastes the device's image cache, and
' worse, it has silently changed by the time the viewer scrolls back to it.
sub onOnScreen()
    if m.top.onScreen
        m.heroTimer.control = "start"
    else
        m.heroTimer.control = "stop"
    end if
end sub

sub onFocusOn()
    ' Home opens ON the hero, the way it does on every other platform: the
    ' marquee is the first thing the viewer can act on, not a row of thumbnails
    ' under it.
    if m.top.focusOn then enterHero()
end sub

' §2.1 / §3.1 — Left from the FIRST column reaches the rail. Roku's focus
' engine will not cross out of a RowList on its own, so the screen says where
' Left goes, exactly as the Android TV build had to.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false

    ' Play/Pause plays the featured item from anywhere, without moving focus.
    if key = "play"
        if m.heroId <> invalid
            print "AWROKU play-shortcut id="; m.heroId
            m.top.chosen = m.heroId
            return true
        end if
        return false
    end if

    if m.focusZone = "hero"
        ' RIGHT advances and wraps. LEFT steps BACK through the pool until the
        ' first hero, and only then falls through to the rail — the tvOS
        ' left-catcher contract, which needs no catcher here because this
        ' component sees the press itself.
        if key = "right"
            advanceHero(1)
            return true
        else if key = "left"
            if m.heroIndex > 0
                advanceHero(-1)
                return true
            end if
            m.top.exitLeft = true
            return true
        else if key = "down"
            enterRows()
            return true
        else if key = "up"
            return true
        else if key = "OK"
            if m.heroId <> invalid and m.heroId <> ""
                print "AWROKU hero-select id="; m.heroId
                m.top.chosen = m.heroId
            end if
            return true
        end if
        return false
    end if

    ' In the shelves.
    if key = "up"
        idx = m.rows.rowItemFocused
        if idx <> invalid and idx[0] = 0
            enterHero()
            return true
        end if
    else if key = "left"
        idx = m.rows.rowItemFocused
        if idx <> invalid and idx[1] = 0
            m.top.exitLeft = true
            return true
        end if
    end if
    return false
end function
