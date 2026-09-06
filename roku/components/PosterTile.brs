sub init()
    m.t = Theme()
    m.plate = m.top.FindNode("plate")
    m.art = m.top.FindNode("art")
    m.caption = m.top.FindNode("caption")
    m.meta = m.top.FindNode("meta")

    m.caption.font = m.t.uItem
    m.caption.color = m.t.textPri
    m.caption.width = m.t.posterFW
    ' F10 — "never abbreviate": three full lines, no ellipsis; the row cell
    ' reserves the height (posterFH + 232) and the meta line sits below them.
    m.caption.maxLines = 3
    m.caption.ellipsizeOnBoundary = false
    m.caption.wrap = true
    m.meta.font = m.t.uMeta
    m.meta.color = m.t.textSec
    ' BOUND IT. An unbounded Roku Label does not wrap — it just keeps drawing,
    ' so "1956  ·  Crime  ·  Mystery" ran straight out of its own cell and
    ' across the NEXT film's title. The caption above has always carried a
    ' width; the meta line never did. One line, ellipsized: the year and a
    ' genre are a glance, and a meta line that wrapped would push into the
    ' row below.
    m.meta.width = m.t.posterFW
    m.meta.maxLines = 1
    m.meta.ellipsizeOnBoundary = true
    m.meta.wrap = false

    ' A typographic card for tiles that name a PLACE rather than a film —
    ' "Silent Era", "The 1930s". They have no poster and never will, and an
    ' empty 2:3 box beside real posters reads as a failed image load.
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
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
    m.plate.color = "0x121215FF"
    m.art.width = w : m.art.height = h
    ' Decision 097 binds on every platform: NEVER reshape the art. scaleToZoom
    ' would crop; the tile is already 2:3 and the art is fitted into it.
    m.art.loadDisplayMode = "scaleToFit"
    ' The caption wraps to TWO lines, so the meta line has to clear both of
    ' them. At h+48 a two-line title ran straight through it — "The Smith
    ' Family (Season 1)" over "1971 · TV" — which is the overlap class the
    ' owner reported. One line of uItem is ~34px, so two plus a gap is 78.
    ' Pinned to the UNFOCUSED height, so the caption does not jump when a tile
    ' grows under focus — a row of titles that dances as you scroll is worse
    ' than no titles at all.
    m.caption.translation = [0, m.t.posterFH + 9]
    m.meta.translation = [0, m.t.posterFH + 150]
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
    m.plate.visible = true
    AWFramePlace(m.frame, m.art, false)
    m.tileLabel.visible = true
    m.tileLabel.text = c.title
    ' A film with no artwork gets a DESIGNED card, not a grey line on a dark
    ' plate. The owner read the old one as "completely blank", and they were
    ' right: secondary grey on 0x1C1C22 is barely a card at all. White type
    ' under the category accent rule is the same language Detail uses.
    m.tileLabel.color = m.t.textPri
    m.tileLabel.width = m.t.posterW - 36
    m.tileLabel.translation = [18, 66]
    kind = ""
    if c.HasField("awType") then kind = fmt(c.awType)
    if kind = "" then kind = "feature-film"
    m.tileRule.translation = [18, 36]
    m.tileRule.width = 72 : m.tileRule.height = 6
    m.tileRule.color = AccentFor(kind)
    m.tileRule.visible = true
    if c.HDPOSTERURL <> invalid and c.HDPOSTERURL <> "" then m.art.uri = c.HDPOSTERURL
    m.caption.text = c.title
    m.caption.visible = true
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
    m.tileRule.visible = false
    m.plate.visible = false
    positionRing()
end sub

sub positionRing()
    AWFramePlace(m.frame, m.art, m.focused = true)
end sub

sub onFocusChanged()
    ' §13.3 — same gate as GridTile: RowList keeps itemHasFocus on the
    ' last item after focus leaves the row, so the ROW's focus gates the ring.
    ' rowHasFocus stays true on the current row after the LIST loses focus
    ' (measured: the tile stayed enlarged under a focused hero); the list's
    ' own flag is the one that flips.
    focused = m.top.itemHasFocus and m.top.rowHasFocus and m.top.rowListHasFocus
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
    ' The title is ALWAYS on. Showing it only under the focused tile meant a
    ' shelf of unlabelled pictures, which is not how any other platform in this
    ' project presents a shelf — the owner's words were "why are the titles not
    ' all listed on the shelves". The META line stays focus-only: year and type
    ' are detail, and six of them per row is noise.
    m.caption.visible = not m.isTile
    m.meta.visible = focused
    ' The meta line sits under the caption's RENDERED height, not under the
    ' three-line reserve: pinned at the reserve it floated 100 px below a
    ' one-line title, detached from the tile it describes.
    if focused
        ch = 34
        r = m.caption.boundingRect()
        if r <> invalid and r.height > 0 then ch = Int(r.height)
        m.meta.translation = [0, m.t.posterFH + 9 + ch + 6]
    end if
    positionRing()
end sub
