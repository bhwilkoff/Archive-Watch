sub init()
    m.t = Theme()
    m.wash = m.top.FindNode("wash")
    m.scrim = m.top.FindNode("scrim")
    m.title = m.top.FindNode("title")
    m.meta = m.top.FindNode("meta")
    m.overview = m.top.FindNode("overview")
    m.seasons = m.top.FindNode("seasons")
    m.episodes = m.top.FindNode("episodes")
    m.empty = m.top.FindNode("empty")

    m.wash.translation = [0, 0]
    m.wash.width = 1836 : m.wash.height = 480
    m.wash.loadDisplayMode = "scaleToFill"
    m.wash.opacity = 0.18

    m.scrim.translation = [0, 0]
    m.scrim.width = 1836 : m.scrim.height = 480
    m.scrim.color = "0x0B0B0CCC"

    m.title.font = m.t.uScreen : m.title.color = m.t.textPri
    m.title.translation = [42, 126] : m.title.width = 1300
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.meta.font = m.t.uMeta : m.meta.color = m.t.textSec
    m.meta.translation = [42, 192]

    m.overview.font = m.t.uMeta : m.overview.color = m.t.textSec
    m.overview.translation = [42, 234] : m.overview.width = 1300
    m.overview.wrap = true : m.overview.maxLines = 2

    m.seasons.translation = [42, 342]
    m.seasons.itemSize = [252, 60]
    m.seasons.itemSpacing = [0, 12]
    m.seasons.numRows = 9
    m.seasons.font = m.t.uBody
    m.seasons.color = m.t.textPri
    m.seasons.focusedColor = m.t.marquee
    m.seasons.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.seasons.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.seasons.drawFocusFeedbackOnTop = true
    m.seasons.vertFocusAnimationStyle = "fixedFocusWrap"
    m.seasons.ObserveField("itemFocused", "onSeasonFocused")

    m.episodes.translation = [342, 342]
    m.episodes.itemComponentName = "EpisodeRow"
    m.episodes.itemSize = [1020, 159]
    m.episodes.itemSpacing = [0, 12]
    m.episodes.numRows = 4
    m.episodes.focusBitmapUri = "pkg:/images/focus_ring.9.png"
    m.episodes.focusFootprintBitmapUri = "pkg:/images/focus_footprint.9.png"
    m.episodes.drawFocusFeedbackOnTop = true
    m.episodes.vertFocusAnimationStyle = "fixedFocusWrap"
    m.episodes.ObserveField("itemSelected", "onEpisodeSelected")

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [150, 420] : m.empty.width = 1200 : m.empty.wrap = true

    m.col = 0
    m.series = invalid
end sub

sub showSeries(d as Object)
    if d = invalid or d.seasons = invalid or d.seasons.Count() = 0
        m.empty.visible = true
        m.empty.text = "This series' episode list could not be loaded. Check the network and try again."
        return
    end if
    m.empty.visible = false
    m.series = d
    m.title.text = fmt(d.title)

    bits = []
    if d.yearStart <> invalid
        span = fmt(d.yearStart)
        if d.yearEnd <> invalid and d.yearEnd <> d.yearStart then span = span + "–" + fmt(d.yearEnd)
        bits.Push(span)
    end if
    if d.networks <> invalid and d.networks.Count() > 0 then bits.Push(fmt(d.networks[0]))
    ' The HONEST episode count: how many we can actually play, against how many
    ' the show has. A series page that claims 39 and holds 18 is a promise the
    ' archive cannot keep.
    have = 0
    for each s in d.seasons
        if s.episodes <> invalid then have = have + s.episodes.Count()
    end for
    total = have
    if d.canonicalEpisodesCount <> invalid then total = Int(d.canonicalEpisodesCount)
    if total > have
        bits.Push(fmt(have) + " of " + fmt(total) + " episodes here")
    else
        bits.Push(fmt(have) + " episodes")
    end if
    m.meta.text = joinStr(bits, "   ·   ")
    if d.overview <> invalid then m.overview.text = fmt(d.overview)
    if d.backdropURL <> invalid and d.backdropURL <> ""
        m.wash.uri = fmt(d.backdropURL)
    else if d.posterURL <> invalid
        m.wash.uri = fmt(d.posterURL)
    end if

    root = CreateObject("roSGNode", "ContentNode")
    for each s in d.seasons
        n = root.CreateChild("ContentNode")
        ' A season with no number is real in this data — archive uploads that
        ' could not be placed. "Season " with nothing after it reads as a bug;
        ' naming it does not.
        if s.seasonNumber = invalid or fmt(s.seasonNumber) = "" or Int(s.seasonNumber) = 0
            n.title = "Unsorted"
        else
            n.title = "Season " + fmt(s.seasonNumber)
        end if
    end for
    m.seasons.content = root
    m.seasons.jumpToItem = 0
    paintSeason(0)
end sub

function joinStr(items as Object, sep as String) as String
    out = ""
    for i = 0 to items.Count() - 1
        if i > 0 then out = out + sep
        out = out + items[i]
    end for
    return out
end function

sub onSeasonFocused()
    paintSeason(m.seasons.itemFocused)
end sub

sub paintSeason(idx as Integer)
    if m.series = invalid or idx < 0 or idx >= m.series.seasons.Count() then return
    s = m.series.seasons[idx]
    root = CreateObject("roSGNode", "ContentNode")
    if s.episodes <> invalid
        for each e in s.episodes
            n = root.CreateChild("ContentNode")
            n.id = fmt(e.archiveID)
            n.title = fmt(e.title)
            n.SHORTDESCRIPTIONLINE1 = "S" + fmt(e.seasonNumber) + " · E" + fmt(e.episodeNumber)
            if e.overview <> invalid then n.SHORTDESCRIPTIONLINE2 = fmt(e.overview)
            if e.stillURL <> invalid then n.HDPOSTERURL = fmt(e.stillURL)
        end for
    end if
    m.episodes.content = root
    m.episodes.jumpToItem = 0
end sub

' Re-read the registry so a resume bar updates the moment the viewer comes back
' from watching an episode.
sub refreshProgress()
    paintSeason(m.seasons.itemFocused)
end sub

sub onEpisodeSelected()
    i = m.episodes.itemSelected
    if m.episodes.content = invalid then return
    n = m.episodes.content.GetChild(i)
    if n = invalid then return
    ' The whole season travels with the request so the player can advance to
    ' the next episode without coming back here for it.
    ids = []
    titles = []
    for j = 0 to m.episodes.content.GetChildCount() - 1
        c = m.episodes.content.GetChild(j)
        ids.Push(c.id)
        titles.Push(c.title)
    end for
    m.top.playEpisode = { id: n.id, title: n.title,
                          meta: fmt(m.series.title) + "  ·  " + n.SHORTDESCRIPTIONLINE1,
                          queue: ids, queueTitles: titles, index: i }
end sub

sub onFocusOn()
    if m.top.focusOn
        if m.col = 1 then m.episodes.setFocus(true) else m.seasons.setFocus(true)
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if m.col = 0
        if key = "right" or key = "OK"
            if m.episodes.content <> invalid and m.episodes.content.GetChildCount() > 0
                m.col = 1 : m.episodes.setFocus(true)
            end if
            return true
        else if key = "left"
            m.top.exitLeft = true
            return true
        end if
    else
        if key = "left"
            m.col = 0 : m.seasons.setFocus(true)
            return true
        end if
    end if
    return false
end function
