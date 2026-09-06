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

    ' §13.7 — the backdrop is the scene, at full brightness under the tvOS
    ' gradient. It was a 0.10 wash behind an opaque scrim: a ghost of the
    ' title card that read as a rendering fault.
    m.wash.translation = [-150, 0]
    m.wash.width = 2070 : m.wash.height = 648
    m.wash.loadDisplayMode = "scaleToZoom"
    m.wash.opacity = 1.0
    m.fade = m.top.FindNode("fade")
    m.fade.uri = "pkg:/images/hero_scrim_v.png"
    m.fade.translation = [-150, 0]
    m.fade.width = 2070 : m.fade.height = 648
    m.fade.loadDisplayMode = "scaleToFill"

    ' Decision 097 — fitted at the art's OWN aspect, never cropped into a box.
    m.art = m.top.FindNode("art")
    m.art.translation = [42, 318]
    m.art.width = 288 : m.art.height = 432
    m.art.loadDisplayMode = "scaleToFit"
    m.art.visible = false
    m.artFrame = AWFrameBuild(m.top.FindNode("artFrame"))
    m.art.ObserveField("loadStatus", "onArtLoaded")
    m.kind = m.top.FindNode("kind")
    m.kind.font = m.t.uEyebrow : m.kind.color = AccentFor("tv-series")
    m.kind.translation = [378, 318]
    m.kind.text = AWTracked("TELEVISION")

    m.title.font = m.t.uTitle : m.title.color = m.t.textPri
    m.title.translation = [378, 348] : m.title.width = 1380
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    m.meta.font = m.t.uMeta : m.meta.color = m.t.textSec
    m.meta.translation = [378, 432]

    m.overview.font = m.t.uBody : m.overview.color = m.t.textPri
    m.overview.translation = [378, 480] : m.overview.width = 1140
    m.overview.wrap = true : m.overview.maxLines = 2
    m.overview.ellipsizeOnBoundary = true

    ' Seasons and episodes below the seam, right of the poster column.
    m.seasons.translation = [378, 606]
    m.seasons.itemSize = [252, 60]
    m.seasons.itemSpacing = [0, 12]
    m.seasons.numRows = 9
    m.seasons.font = m.t.uBody
    m.seasons.color = m.t.textPri
    m.seasons.focusedColor = m.t.marquee
    m.seasons.focusBitmapUri = "pkg:/images/ring_focus.9.png"
    m.seasons.focusFootprintBitmapUri = "pkg:/images/ring_footprint.9.png"
    m.seasons.drawFocusFeedbackOnTop = true
    ' NOT fixedFocusWrap: a wrapping list draws its own contents again below a
    ' divider, so a 7-season show showed "Season 18, 19, 23, Unsorted" and then
    ' "Season 1, Season 2" again underneath. Seven items do not need wrapping.
    m.seasons.vertFocusAnimationStyle = "floatingFocus"
    m.seasons.ObserveField("itemFocused", "onSeasonFocused")

    m.episodes.translation = [654, 606]
    m.episodes.itemComponentName = "EpisodeRow"
    ' Left of the poster, which starts at 1300.
    m.episodes.itemSize = [1140, 141]
    m.episodes.itemSpacing = [0, 12]
    m.episodes.numRows = 3
    m.episodes.focusBitmapUri = "pkg:/images/ring_focus.9.png"
    ' No persistent footprint box: at 1140 px wide the footprint outline read
    ' as a big empty container while the season column had focus. The active
    ' ring (when the list IS focused) plus the lit season pill are enough to
    ' say where the viewer is; a transparent 9-patch removes the box.
    m.episodes.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.episodes.drawFocusFeedbackOnTop = true
    m.episodes.vertFocusAnimationStyle = "floatingFocus"
    m.episodes.ObserveField("itemSelected", "onEpisodeSelected")

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    ' Below the episode list, clear of it, so a notice never covers the rows
    ' the viewer is choosing from.
    m.empty.translation = [654, 1002] : m.empty.width = 1200 : m.empty.wrap = true
    m.empty.maxLines = 2 : m.empty.color = m.t.marquee

    m.col = 0
    m.series = invalid
end sub

' An episode that cannot be resolved must SAY so. Pressing Select and having
' nothing happen is the single most expensive failure on this platform, and it
' is what a missing detail shard produced: the task set status="error" and the
' scene observed only `detail`, so the error reached nobody.
sub showNotice(msg as String)
    m.empty.visible = (msg <> "")
    m.empty.text = msg
end sub

sub onArtLoaded()
    if m.art.loadStatus = "ready" then AWFramePlace(m.artFrame, m.art, false)
end sub

sub showSeries(d as Object)
    if d = invalid or d.seasons = invalid or d.seasons.Count() = 0
        m.empty.visible = true
        m.empty.text = "This series' episode list could not be loaded. Check the network and try again."
        return
    end if
    m.empty.visible = false
    m.series = d
    m.top.seriesID = "series:" + fmt(d.seriesID)
    m.title.text = fmt(d.title)
    if d.posterURL <> invalid and fmt(d.posterURL) <> ""
        m.art.uri = fmt(d.posterURL)
        m.art.visible = true
    else
        m.art.visible = false
    end if

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
        bits.Push(AWPlural(have, "episode"))
    end if
    m.meta.text = joinStr(bits, "   ·   ")
    if d.overview <> invalid then m.overview.text = StripHTML(fmt(d.overview))
    if d.backdropURL <> invalid and d.backdropURL <> ""
        m.wash.uri = fmt(d.backdropURL)
        m.wash.opacity = 1.0
    else if d.posterURL <> invalid
        m.wash.uri = fmt(d.posterURL)
        m.wash.opacity = 0.6
    else
        m.wash.uri = ""
    end if

    root = CreateObject("roSGNode", "ContentNode")
    ' The tvOS label for an unnumbered season (Catalog.swift): "More Episodes"
    ' when it sits beside numbered seasons, and — Roku's own touch, cleaner
    ' for the many shows here that are ENTIRELY unnumbered — just "Episodes"
    ' when it is the only group. "Unsorted" read as a system word, not a shelf.
    only = (d.seasons.Count() = 1)
    for each s in d.seasons
        n = root.CreateChild("ContentNode")
        if s.seasonNumber = invalid or fmt(s.seasonNumber) = "" or Int(s.seasonNumber) = 0
            if only then n.title = "Episodes" else n.title = "More Episodes"
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

' An unanchored episode usually carries the SERIES title verbatim, so a
' season reads as the same line repeated and the viewer cannot tell one
' episode from another. The archive id is the only thing that distinguishes
' them, and it is usually the episode name: 13_demon_street_fever_1959 ->
' "Fever". Falls back to the original title when nothing is left over.
function episodeTitle(e as Object) as String
    t = StripHTML(fmt(e.title))
    aid = fmt(e.archiveID)
    if aid = "" then return t
    ' Only intervene when the title tells the viewer nothing.
    seriesT = ""
    if m.series <> invalid then seriesT = LCase(StripHTML(fmt(m.series.title)))
    if LCase(t) <> seriesT then return t

    words = []
    cur = ""
    for i = 1 to Len(aid)
        c = Mid(aid, i, 1)
        if c = "_" or c = "-" or c = "."
            if cur <> "" then words.Push(cur)
            cur = ""
        else
            cur = cur + c
        end if
    end for
    if cur <> "" then words.Push(cur)

    ' Drop the leading tokens the series title already accounts for, and a
    ' trailing year.
    seriesWords = {}
    cw = ""
    for i = 1 to Len(seriesT)
        c = Mid(seriesT, i, 1)
        if c = " " or c = "-" or c = ":"
            if cw <> "" then seriesWords[cw] = true
            cw = ""
        else
            cw = cw + c
        end if
    end for
    if cw <> "" then seriesWords[cw] = true

    kept = []
    for each w in words
        lw = LCase(w)
        if kept.Count() = 0 and seriesWords[lw] = true then continue for
        kept.Push(w)
    end for
    if kept.Count() > 1
        last = kept[kept.Count() - 1]
        if Len(last) = 4 and Val(last) > 1870 and Val(last) < 2100 then kept.Pop()
    end if
    if kept.Count() = 0 then return t

    outStr = ""
    for each w in kept
        head = UCase(Left(w, 1))
        tail = Mid(w, 2)
        if outStr = "" then outStr = head + tail else outStr = outStr + " " + head + tail
    end for
    return outStr
end function

sub paintSeason(idx as Integer)
    if m.series = invalid or idx < 0 or idx >= m.series.seasons.Count() then return
    s = m.series.seasons[idx]
    root = CreateObject("roSGNode", "ContentNode")
    if s.episodes <> invalid
        for each e in s.episodes
            n = root.CreateChild("ContentNode")
            n.id = fmt(e.archiveID)
            n.title = episodeTitle(e)
            ' A spine whose episodes were never anchored carries no season or
            ' episode number, and printing "S · E" with the numbers missing is
            ' noise pretending to be information. Say nothing instead — the
            ' honest answer, and the one the rest of this app already gives.
            if e.seasonNumber <> invalid and e.episodeNumber <> invalid
                n.SHORTDESCRIPTIONLINE1 = "S" + fmt(e.seasonNumber) + " · E" + fmt(e.episodeNumber)
            else
                n.SHORTDESCRIPTIONLINE1 = ""
            end if
            if e.overview <> invalid then n.SHORTDESCRIPTIONLINE2 = StripHTML(fmt(e.overview))
            if e.stillURL <> invalid then n.HDPOSTERURL = fmt(e.stillURL)
            ' The spine ALREADY carries the playable url for every episode.
            ' Carrying it here is what lets an episode play at all: the detail
            ' shards are built from the same gate as the index, which excludes
            ' episodes, so the shard lookup could never resolve one — measured
            ' 2026-09-06, 4,702 episodes across all 489 spines, none of them in
            ' a shard. Every one of them answered "not in the catalog yet".
            if e.downloadURL <> invalid then n.url = fmt(e.downloadURL)
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
    urls = []
    for j = 0 to m.episodes.content.GetChildCount() - 1
        c = m.episodes.content.GetChild(j)
        ids.Push(c.id)
        titles.Push(c.title)
        urls.Push(fmt(c.url))
    end for
    m.top.playEpisode = { id: n.id, title: n.title, url: fmt(n.url),
                          meta: fmt(m.series.title) + "  ·  " + n.SHORTDESCRIPTIONLINE1,
                          queue: ids, queueTitles: titles, queueUrls: urls, index: i }
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
