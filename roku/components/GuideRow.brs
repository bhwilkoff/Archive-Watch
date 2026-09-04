sub init()
    m.t = Theme()
    m.time = m.top.FindNode("time")
    m.title = m.top.FindNode("title")
    m.chip = m.top.FindNode("nowChip")
    m.chipText = m.top.FindNode("nowText")

    m.time.font = m.t.uMeta : m.time.color = m.t.textSec
    m.time.translation = [18, 18] : m.time.width = 150

    m.title.font = m.t.uBody : m.title.color = m.t.textPri
    m.title.translation = [186, 12] : m.title.width = 690
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.chip.translation = [900, 20] : m.chip.width = 108 : m.chip.height = 30
    m.chip.color = m.t.marquee
    m.chipText.font = m.t.uMeta : m.chipText.color = "0x0B0B0CFF"
    m.chipText.translation = [918, 22]
    m.chipText.text = "ON NOW"
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.time.text = c.SHORTDESCRIPTIONLINE1
    m.title.text = c.title
    on = (c.SHORTDESCRIPTIONLINE2 = "now")
    m.chip.visible = on
    m.chipText.visible = on
end sub

sub onFocus()
    ' §5.4 — focus is a colour step, never a scale: the row sits in a list whose
    ' geometry must not move when the selection does.
    if m.top.focusPercent > 0.5
        m.title.color = m.t.marquee
    else
        m.title.color = m.t.textPri
    end if
end sub
