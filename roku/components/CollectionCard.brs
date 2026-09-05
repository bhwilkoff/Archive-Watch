sub init()
    m.t = Theme()
    m.w = 852 : m.h = 324
    m.plate = m.top.FindNode("plate")
    m.plate.width = m.w : m.plate.height = m.h
    m.plate.color = "0x1C1C22FF"

    ' Three posters side by side, each a third of the card, crop-filled: a
    ' composite is a MONTAGE, the one place the tvOS app itself crops a
    ' poster (CollectionCard.posterStack uses .fill). The middle one leads.
    m.posters = []
    third = 284
    for i = 0 to 2
        p = m.top.FindNode("p" + fmt(i))
        p.translation = [i * third, 0]
        p.width = third : p.height = m.h
        p.loadDisplayMode = "scaleToZoom"
        p.loadWidth = third : p.loadHeight = m.h
        if i = 1 then p.opacity = 1.0 else p.opacity = 0.75
        m.posters.Push(p)
    end for

    ' The §13.3 gradient over the montage so the copy sits on darkness.
    m.fade = m.top.FindNode("fade")
    m.fade.uri = "pkg:/images/hero_scrim_v.png"
    m.fade.width = m.w : m.fade.height = m.h
    m.fade.loadDisplayMode = "scaleToFill"

    m.rule = m.top.FindNode("rule")
    m.rule.translation = [30, 207] : m.rule.width = 48 : m.rule.height = 6

    m.count = m.top.FindNode("count")
    m.count.font = m.t.uMeta : m.count.color = m.t.textSec
    m.count.translation = [90, 198]

    m.title = m.top.FindNode("title")
    m.title.font = m.t.uScreen : m.title.color = m.t.textPri
    m.title.translation = [30, 225] : m.title.width = m.w - 60
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.blurb = m.top.FindNode("blurb")
    m.blurb.font = m.t.uBody : m.blurb.color = m.t.textSec
    m.blurb.translation = [30, 282] : m.blurb.width = m.w - 60
    m.blurb.maxLines = 1 : m.blurb.ellipsizeOnBoundary = true

    ' §13.3 / §13.4 — rounded, and the ring lights on focus.
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
    AWFramePlace(m.frame, m.plate, false)
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.title.text = c.title
    acc = m.t.marquee
    if c.awAccent <> invalid and c.awAccent <> "" then acc = c.awAccent
    m.rule.color = acc
    ' With no art at all the card carries its accent at ~20%, never a bare
    ' grey plate.
    m.plate.color = Left(acc, 8) + "33"
    if c.awBlurb <> invalid then m.blurb.text = c.awBlurb else m.blurb.text = ""
    n = 0
    if c.awCount <> invalid then n = c.awCount
    ' The published index holds at most 120 members per collection, so the
    ' cap is stated as a floor rather than as a false total.
    if n >= 120
        m.count.text = "120+ titles"
    else
        m.count.text = AWPlural(n, "title")
    end if
    arts = c.awPosters
    for i = 0 to 2
        p = m.posters[i]
        p.uri = ""
        if arts <> invalid and i < arts.Count()
            p.uri = fmt(arts[i])
            p.visible = true
        else
            p.visible = false
        end if
    end for
end sub

sub onFocus()
    lit = (m.top.focusPercent > 0.5)
    AWFramePlace(m.frame, m.plate, lit)
end sub
