sub init()
    m.t = Theme()
    m.still = m.top.FindNode("still")
    m.num = m.top.FindNode("num")
    m.title = m.top.FindNode("title")
    m.blurb = m.top.FindNode("blurb")
    m.bar = m.top.FindNode("bar")

    ' 16:9 still, never reshaped (Decision 097 applies to episode art too).
    m.still.width = 240 : m.still.height = 135
    m.still.translation = [12, 12]
    m.still.loadDisplayMode = "scaleToFit"

    m.num.font = m.t.uMeta : m.num.color = m.t.textSec
    m.num.translation = [270, 18]

    m.title.font = m.t.uBody : m.title.color = m.t.textPri
    m.title.translation = [270, 48] : m.title.width = 720
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.blurb.font = m.t.uMeta : m.blurb.color = m.t.textSec
    m.blurb.translation = [270, 96] : m.blurb.width = 720
    m.blurb.maxLines = 1 : m.blurb.ellipsizeOnBoundary = true

    ' Resume progress for THIS episode — the shelf-level answer to "where was I"
    ' that a series with 39 episodes needs more than a film does.
    ' Clear of the blurb's descenders — at 132 it read as an underline of the
    ' text above it rather than as progress.
    m.bar.translation = [270, 141] : m.bar.height = 5 : m.bar.color = m.t.marquee
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    m.still.uri = c.HDPOSTERURL
    m.num.text = c.SHORTDESCRIPTIONLINE1
    m.title.text = c.title
    m.blurb.text = c.SHORTDESCRIPTIONLINE2
    posn = awGetProgress(c.id)
    dur = awGetDuration(c.id)
    if posn > 0 and dur > 0
        m.bar.visible = true
        w = Int(720 * posn / dur)
        if w < 6 then w = 6
        if w > 720 then w = 720
        m.bar.width = w
    else
        m.bar.visible = false
    end if
end sub

sub onFocus()
    if m.top.focusPercent > 0.5
        m.title.color = m.t.marquee
    else
        m.title.color = m.t.textPri
    end if
end sub
