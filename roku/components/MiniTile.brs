sub init()
    m.t = Theme()
    m.plate = m.top.FindNode("plate")
    m.art = m.top.FindNode("art")
    m.plate.width = 108 : m.plate.height = 162
    m.plate.color = "0x1C1C22FF"
    m.art.width = 108 : m.art.height = 162
    ' Never reshape the art (Decision 097): fit inside the slot rather than
    ' filling it, so a landscape still stays a still.
    m.art.loadDisplayMode = "scaleToFit"
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.art.uri = c.HDPOSTERURL
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.plate.color = "0x33333DFF"
    else
        m.plate.color = "0x1C1C22FF"
    end if
end sub
