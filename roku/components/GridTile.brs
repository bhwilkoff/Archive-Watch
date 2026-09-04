sub init()
    m.t = Theme()
    m.plate = m.top.FindNode("plate")
    m.art = m.top.FindNode("art")
    m.caption = m.top.FindNode("caption")
    m.caption.font = m.t.uMeta
    m.caption.color = m.t.textPri
    m.caption.width = 210
    m.caption.maxLines = 2
    m.caption.wrap = true
    setSize(192, 288)
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
    m.art.uri = c.HDPOSTERURL
    m.caption.text = c.title
end sub

sub onFocusChanged()
    f = m.top.itemHasFocus
    if f then setSize(210, 315) else setSize(192, 288)
    m.caption.visible = f
end sub
