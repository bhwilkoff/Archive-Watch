sub init()
    m.t = Theme()
    m.card = m.top.FindNode("card")
    m.cardText = m.top.FindNode("cardText")
    m.still = m.top.FindNode("still")
    m.num = m.top.FindNode("num")
    m.title = m.top.FindNode("title")
    m.blurb = m.top.FindNode("blurb")
    m.bar = m.top.FindNode("bar")

    ' 16:9 still, never reshaped (Decision 097 applies to episode art too).
    m.still.width = 208 : m.still.height = 117
    m.still.translation = [12, 12]
    m.still.loadDisplayMode = "scaleToFit"
    m.stillFrame = AWFrameBuild(m.top.FindNode("stillFrame"))
    m.still.ObserveField("loadStatus", "onStillLoaded")

    m.card.translation = [12, 12]
    m.card.width = 208 : m.card.height = 117
    m.card.color = "0x1C1C22FF"
    m.cardText.translation = [12, 48]
    m.cardText.width = 208
    m.cardText.horizAlign = "center"
    m.cardText.font = m.t.uRow
    m.cardText.color = "0x6B6B76FF"

    m.num.font = m.t.uMeta : m.num.color = m.t.textSec
    m.num.translation = [240, 12]

    m.title.font = m.t.uBody : m.title.color = m.t.textPri
    m.title.translation = [240, 42] : m.title.width = 870
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.blurb.font = m.t.uMeta : m.blurb.color = m.t.textSec
    m.blurb.translation = [240, 84] : m.blurb.width = 870
    m.blurb.maxLines = 1 : m.blurb.ellipsizeOnBoundary = true

    ' Resume progress for THIS episode — the shelf-level answer to "where was I"
    ' that a series with 39 episodes needs more than a film does.
    ' Clear of the blurb's descenders — at 132 it read as an underline of the
    ' text above it rather than as progress.
    m.bar.translation = [240, 126] : m.bar.height = 5 : m.bar.color = m.t.marquee
end sub

sub onStillLoaded()
    if m.still.loadStatus = "ready" then AWFramePlace(m.stillFrame, m.still, false)
end sub

sub onContent()
    c = m.top.itemContent
    if c = invalid then return
    art = fmt(c.HDPOSTERURL)
    m.still.uri = art
    ' Most spines here publish no episode stills. Rather than leave a hole,
    ' the card carries the episode number — and where the spine was never
    ' anchored and has no number either, the first letters of the episode
    ' name, which is the same title-card idiom the poster tiles use.
    m.card.visible = (art = "")
    m.cardText.visible = (art = "")
    if art = ""
        n = fmt(c.SHORTDESCRIPTIONLINE1)
        if n <> ""
            m.cardText.text = n
        else
            m.cardText.text = Left(UCase(fmt(c.title)), 12)
        end if
    end if
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
        m.title.color = m.t.textPri
    else
        m.title.color = m.t.textPri
    end if
end sub
