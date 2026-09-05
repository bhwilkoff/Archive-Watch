sub init()
    m.t = Theme()
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
    m.focused = false
    m.plate = m.top.FindNode("plate")
    m.plate.color = "0x121215FF"
    m.art = m.top.FindNode("art")
    m.caption = m.top.FindNode("caption")
    m.caption.font = m.t.uMeta
    m.caption.color = m.t.textPri
    m.caption.width = 210
    m.caption.maxLines = 1
    m.caption.ellipsizeOnBoundary = true
    m.caption.wrap = true
    m.art.ObserveField("loadStatus", "onArtLoaded")
    setSize(192, 288)
end sub

sub onArtLoaded()
    m.plate.visible = (m.art.loadStatus <> "ready")
    AWFramePlace(m.frame, m.art, m.focused)
end sub

sub setSize(w as Integer, h as Integer)
    m.plate.width = w : m.plate.height = h
    m.art.width = w : m.art.height = h
    m.art.loadDisplayMode = "scaleToFit"   ' Decision 097 — never reshape art
    m.caption.translation = [0, h + 6]
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.plate.visible = true
    m.art.uri = c.HDPOSTERURL
    m.caption.text = c.title
end sub

sub onFocusChanged()
    ' §13.3 — one lit thing at a time. A tile that stays ringed after focus
    ' moves to the chips above it is a second lit thing; MarkupGrid keeps
    ' itemHasFocus on the last item, so the grid's OWN focus must gate it.
    f = m.top.itemHasFocus and m.top.gridHasFocus
    m.focused = f
    if f then setSize(210, 315) else setSize(192, 288)
    m.caption.visible = f
    AWFramePlace(m.frame, m.art, f)
end sub
