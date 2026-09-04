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
    m.tileRule = m.top.FindNode("tileRule")
    m.tileLabel = m.top.FindNode("tileLabel")
    m.tileLabel.font = m.t.uRow
    m.tileLabel.color = m.t.textPri
    m.tileLabel.wrap = true
    m.tileLabel.maxLines = 3

    setSize(m.t.posterW, m.t.posterH)
end sub

sub setSize(w as Integer, h as Integer)
    m.plate.width = w : m.plate.height = h
    m.art.width = w : m.art.height = h
    ' Decision 097 binds on every platform: NEVER reshape the art. scaleToZoom
    ' would crop; the tile is already 2:3 and the art is fitted into it.
    m.art.loadDisplayMode = "scaleToFit"
    m.caption.translation = [0, h + 9]
    m.meta.translation = [0, h + 48]
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
    m.tileLabel.visible = false
    m.tileRule.visible = false
    m.plate.color = "0x16161AFF"
    m.art.uri = c.HDPOSTERURL
    m.caption.text = c.title
    m.meta.text = c.SHORTDESCRIPTIONLINE1
end sub

sub onFocusChanged()
    focused = m.top.itemHasFocus
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
end sub
