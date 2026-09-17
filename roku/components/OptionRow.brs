sub init()
    m.t = Theme()
    m.pill = m.top.FindNode("pill")
    m.label = m.top.FindNode("label")
    ' A pill pre-rendered at the row's size: a plain Poster keeps a 9-patch's
    ' guide pixels (§13.3), and OS 9.1 stretches one as a flat bitmap anyway.
    ' Loaded synchronously: 3 KB, and the first row focused after the panel
    ' opens otherwise lit its text before its pill had arrived (XD, 2026-09-17).
    m.pill.loadSync = true
    m.pill.uri = "pkg:/images/pill_focus_822x60.png"
    m.pill.width = 822 : m.pill.height = 60
    m.pill.opacity = 0
    ' Text inset from the end cap, the button rule (§13.5): 30 px, the same
    ' inset the action tiles use; vertically centred in the pill.
    m.label.translation = [30, 0]
    m.label.width = 762 : m.label.height = 60
    m.label.vertAlign = "center"
    m.label.font = m.t.uItem
    m.label.color = m.t.textPri
    m.label.maxLines = 1 : m.label.ellipsizeOnBoundary = true
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.label.text = c.title
end sub

sub onFocus()
    lit = (m.top.focusPercent > 0.5)
    if lit
        m.pill.opacity = 1
        m.label.color = m.t.canvas
    else
        m.pill.opacity = 0
        m.label.color = m.t.textPri
    end if
end sub
