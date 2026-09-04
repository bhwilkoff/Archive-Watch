sub init()
    m.t = Theme()
    m.plate = m.top.FindNode("plate")
    m.art = m.top.FindNode("art")
    m.caption = m.top.FindNode("caption")
    m.meta = m.top.FindNode("meta")

    m.caption.font = m.t.uItem
    m.caption.color = m.t.textPri
    m.caption.width = m.t.posterFW
    m.caption.maxLines = 2
    m.caption.wrap = true
    m.meta.font = m.t.uMeta
    m.meta.color = m.t.textSec

    ' A typographic card for tiles that name a PLACE rather than a film —
    ' "Silent Era", "The 1930s". They have no poster and never will, and an
    ' empty 2:3 box beside real posters reads as a failed image load.
    m.ring = [m.top.FindNode("ringT"), m.top.FindNode("ringB"),
              m.top.FindNode("ringL"), m.top.FindNode("ringR")]
    for each r in m.ring
        r.color = m.t.marquee
    end for
    m.art.ObserveField("loadStatus", "onArtLoaded")
    m.tileRule = m.top.FindNode("tileRule")
    m.tileLabel = m.top.FindNode("tileLabel")
    m.tileLabel.font = m.t.uRow
    m.tileLabel.color = m.t.textPri
    m.tileLabel.wrap = true
    m.tileLabel.maxLines = 3

    ' Initialised explicitly: positionRing() runs from the art's load callback,
    ' which fires BEFORE the first focus change, and `not invalid` is a Type
    ' Mismatch that takes the whole tile's render path down — every poster in
    ' the app disappeared until this line existed.
    m.focused = false
    m.isTile = false
    setSize(m.t.posterW, m.t.posterH)
end sub

sub setSize(w as Integer, h as Integer)
    m.plate.width = w : m.plate.height = h
    m.art.width = w : m.art.height = h
    ' Decision 097 binds on every platform: NEVER reshape the art. scaleToZoom
    ' would crop; the tile is already 2:3 and the art is fitted into it.
    m.art.loadDisplayMode = "scaleToFit"
    ' The caption wraps to TWO lines, so the meta line has to clear both of
    ' them. At h+48 a two-line title ran straight through it — "The Smith
    ' Family (Season 1)" over "1971 · TV" — which is the overlap class the
    ' owner reported. One line of uItem is ~34px, so two plus a gap is 78.
    m.caption.translation = [0, h + 9]
    m.meta.translation = [0, h + 114]
    if m.isTile = true
        m.tileRule.translation = [18, 24]
        m.tileRule.width = 72 : m.tileRule.height = 6
        m.tileLabel.width = w - 36
        m.tileLabel.translation = [18, 48]
    end if
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.isTile = (Left(fmt(c.id), 7) = "browse:")
    if m.isTile
        m.art.uri = ""
        m.art.visible = false
        m.tileLabel.visible = true
        m.tileLabel.text = c.title
        m.caption.text = ""
        m.meta.text = ""
        ' A dark plate with a coloured rule, the same language the Surprise
        ' doors use. Eight full-bleed accent slabs in a row shout louder than
        ' the films they sit beside, and a shelf of navigation should be
        ' quieter than the content, not louder.
        acc = "feature-film"
        if c.awType <> invalid and c.awType <> "" then acc = c.awType
        m.plate.color = "0x1C1C22FF"
        m.tileRule.color = AccentFor(acc)
        m.tileRule.visible = true
        m.tileLabel.color = m.t.textPri
        setSize(m.t.posterW, m.t.posterH)
        return
    end if
    m.art.visible = true
    m.tileRule.visible = false
    m.plate.color = "0x16161AFF"
    m.art.uri = c.HDPOSTERURL
    ' A film with no artwork gets its NAME on the plate rather than an empty
    ' box. An empty 2:3 rectangle beside real posters reads as a failed image
    ' load, and in a Continue Watching row it is the one thing the viewer most
    ' expects to recognise.
    ' The title card sits UNDER the art at all times, not only when art is
    ' missing. A RowList RECYCLES its item components, and a Poster keeps the
    ' previous bitmap until the new one finishes loading — so a rebound tile
    ' showed the WRONG film's poster under the right film's caption, which is
    ' worse than showing no poster at all. Clearing the uri first makes the
    ' card the thing on screen until the real art arrives.
    m.art.uri = ""
    hideRing()
    m.tileLabel.visible = true
    m.tileLabel.text = c.title
    m.tileLabel.color = m.t.textSec
    m.tileLabel.width = m.t.posterW - 36
    m.tileLabel.translation = [18, 36]
    if c.HDPOSTERURL <> invalid and c.HDPOSTERURL <> "" then m.art.uri = c.HDPOSTERURL
    m.caption.text = c.title
    m.meta.text = c.SHORTDESCRIPTIONLINE1
end sub

' The selection ring is drawn around the ART, not around the CELL. A cell is
' always 2:3; the art often is not — a 16:9 still fitted into it leaves wide
' empty margins, and a ring around the cell then reads as "much bigger than
' the poster", which is exactly what it is. bitmapWidth/bitmapHeight give the
' real aspect once loaded, so the ring can match what the viewer sees.
sub onArtLoaded()
    if m.art.loadStatus <> "ready" then return
    ' The card is a PLACEHOLDER. Once the picture is up it must go, or the
    ' title reads straight across the artwork — the label is declared after the
    ' Poster in the XML, so it draws on top of it.
    m.tileLabel.visible = false
    positionRing()
end sub

sub hideRing()
    if m.ring = invalid then return
    for each r in m.ring
        r.visible = false
    end for
end sub

sub positionRing()
    if m.focused <> true
        hideRing()
        return
    end if
    w = m.art.width
    h = m.art.height
    bw = m.art.bitmapWidth
    bh = m.art.bitmapHeight
    dw = w
    dh = h
    if bw > 0 and bh > 0
        sx = w / bw
        sy = h / bh
        sc = sx
        if sy < sc then sc = sy
        dw = Int(bw * sc)
        dh = Int(bh * sc)
    end if
    ' Sits just OUTSIDE the art so it never eats the picture's own edge.
    pad = 5
    th = 4
    x = Int((w - dw) / 2) - pad
    y = Int((h - dh) / 2) - pad
    rw = dw + pad * 2
    rh = dh + pad * 2
    m.ring[0].translation = [x, y] : m.ring[0].width = rw : m.ring[0].height = th
    m.ring[1].translation = [x, y + rh - th] : m.ring[1].width = rw : m.ring[1].height = th
    m.ring[2].translation = [x, y] : m.ring[2].width = th : m.ring[2].height = rh
    m.ring[3].translation = [x + rw - th, y] : m.ring[3].width = th : m.ring[3].height = rh
    for each r in m.ring
        r.visible = true
    end for
end sub

sub onFocusChanged()
    focused = m.top.itemHasFocus
    m.focused = focused
    if focused
        setSize(m.t.posterFW, m.t.posterFH)
    else
        setSize(m.t.posterW, m.t.posterH)
    end if
    if m.isTile = true
        m.caption.visible = false
        m.meta.visible = false
        if focused
            m.plate.color = "0x2A2A34FF"
        else
            m.plate.color = "0x1C1C22FF"
        end if
        return
    end if
    m.caption.visible = focused
    m.meta.visible = focused
    positionRing()
end sub
