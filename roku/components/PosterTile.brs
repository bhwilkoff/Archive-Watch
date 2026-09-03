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
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
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
    m.caption.visible = focused
    m.meta.visible = focused
end sub
