sub init()
    m.t = Theme()
    m.plate = m.top.FindNode("plate")
    m.rule = m.top.FindNode("rule")
    m.label = m.top.FindNode("label")
    m.sub = m.top.FindNode("sub")

    m.plate.width = 528 : m.plate.height = 162
    m.plate.color = "0x1C1C22FF"
    ' §13.4 — a rounded card. The frame's corner overlays round the plate;
    ' its ring lights on focus.
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
    AWFramePlace(m.frame, m.plate, false)

    ' A short accent rule instead of an icon: no asset to ship, no glyph to
    ' misread at ten feet, and it carries the per-category colour the rest of
    ' the app already uses for meaning (Decision 013).
    m.rule.translation = [30, 36] : m.rule.width = 72 : m.rule.height = 6
    m.rule.color = m.t.marquee

    m.label.font = m.t.uRow : m.label.color = m.t.textPri
    m.label.translation = [30, 60] : m.label.width = 468
    m.label.maxLines = 1 : m.label.ellipsizeOnBoundary = true

    m.sub.font = m.t.uMeta : m.sub.color = m.t.textSec
    m.sub.translation = [30, 114] : m.sub.width = 468
    m.sub.maxLines = 1 : m.sub.ellipsizeOnBoundary = true
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.label.text = c.title
    m.sub.text = c.SHORTDESCRIPTIONLINE1
    if c.SHORTDESCRIPTIONLINE2 <> invalid and c.SHORTDESCRIPTIONLINE2 <> ""
        m.rule.color = AccentFor(c.SHORTDESCRIPTIONLINE2)
    end if
end sub

sub onFocus()
    lit = (m.top.focusPercent > 0.5)
    if lit then m.plate.color = "0x26262EFF" else m.plate.color = "0x1C1C22FF"
    AWFramePlace(m.frame, m.plate, lit)
end sub
