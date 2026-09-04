sub init()
    m.t = Theme()
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
    m.focused = false
    m.plate = m.top.FindNode("plate")
    m.art = m.top.FindNode("art")
    m.plate.width = 108 : m.plate.height = 162
    m.plate.color = "0x1C1C22FF"
    m.art.width = 108 : m.art.height = 162
    ' Never reshape the art (Decision 097): fit inside the slot rather than
    ' filling it, so a landscape still stays a still.
    m.art.loadDisplayMode = "scaleToFit"
    m.art.ObserveField("loadStatus", "onArtLoaded")
end sub

sub onArtLoaded()
    m.plate.visible = (m.art.loadStatus <> "ready")
    AWFramePlace(m.frame, m.art, m.focused)
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.plate.visible = true
    m.art.uri = c.HDPOSTERURL
end sub

sub onFocus()
    m.focused = (m.top.focusPercent > 0.5)
    m.plate.color = "0x121215FF"
    AWFramePlace(m.frame, m.art, m.focused)
end sub
