sub init()
    m.t = Theme()
    m.rail = m.top.FindNode("rail")
    m.content = m.top.FindNode("content")
    m.loading = m.top.FindNode("loading")

    ' A Label's `font` takes a URI STRING. Assigning a Font NODE that carries
    ' a font: system URI renders NOTHING — no error, no warning, an empty
    ' screen with a healthy console. Proven by a three-way experiment on the
    ' device in tick 2 and the reason half this shell was invisible.
    brand = m.top.FindNode("brand")
    brand.font = m.t.uRow
    brand.text = "ARCHIVE WATCH"
    brand.color = m.t.marquee
    ' Clear the rail: the content column starts at railW, and the brand is
    ' content chrome, not rail chrome.
    brand.translation = [m.t.railW + m.t.safeX, 39]

    clock = m.top.FindNode("clock")
    clock.font = m.t.uMeta : clock.color = m.t.textSec
    clock.translation = [1560, 45]
    clock.text = nowString()

    ' §5.7 — the (*) indicator, shown because Options ARE available here.
    opt = m.top.FindNode("optHint")
    opt.font = m.t.uMeta : opt.color = m.t.textSec
    opt.translation = [1770, 45]
    opt.text = "(*)"

    m.loading.font = m.t.uBody : m.loading.color = m.t.textSec
    m.loading.translation = [m.t.railW + m.t.readX, 480]
    m.loading.text = "Loading the archive…"

    ' The home screen lives in the content column, right of the rail.
    m.home = m.content.CreateChild("HomeScreen")
    m.home.translation = [m.t.railW, 0]
    m.home.ObserveField("exitLeft", "focusRail")
    m.home.ObserveField("chosen", "onChosen")

    m.overlay = m.top.FindNode("overlay")
    m.route = "home"
    m.pendingDeepLink = ""
    m.queuedDeepLink = ""
    m.pendingCollections = false
    m.collectionsBuilt = false
    m.autoPlay = false

    m.rail.ObserveField("selected", "onRailSelected")

    m.svc = CreateObject("roSGNode", "CatalogService")
    m.svc.ObserveField("results", "onQueryResults")
    m.svc.ObserveField("ready", "onSvcReady")
    m.svc.control = "RUN"

    m.task = CreateObject("roSGNode", "HomeTask")
    m.task.ObserveField("status", "onStatus")
    m.task.control = "RUN"

    ' §1.4 / TV-DESIGN §3.1 — something is ALWAYS focused, or the remote does
    ' nothing at all and the viewer thinks the app has hung. Until content
    ' lands, the rail holds focus.
    focusRail()
    print "AWROKU scene ready"
end sub

sub onStatus()
    s = m.task.status
    print "AWROKU home status="; s
    if s = "ready"
        m.loading.visible = false
        m.home.rowsContent = filteredRows(m.task.rows)
        m.home.heroContent = m.task.hero
        ' Only claim focus if the viewer is still ON Home. A cold-start deep
        ' link opens Detail and can reach the PLAYER before the catalog
        ' finishes parsing, and this used to yank focus out of the running film
        ' the moment Home was ready.
        if m.route = "home" then focusContent()
    else if s = "error"
        m.loading.text = "Could not reach the archive. Check the network and try again."
    end if
end sub

sub focusRail()
    m.rail.focusOn = true
    m.home.focusOn = false
    m.rail.setFocus(true)
    print "AWFOCUS rail"
end sub

sub focusContent()
    m.rail.focusOn = false
    m.home.focusOn = true
    m.home.setFocus(true)
    print "AWFOCUS content"
end sub

sub onRailSelected()
    id = m.rail.selected
    print "AWROKU rail-select "; id
    if id = "home"
        closeBrowse()
        focusContent()
    else if id = "movies" or id = "tv"
        openBrowse(id)
    else if id = "search"
        openSearch()
    else if id = "library"
        openLibrary()
    else if id = "collections"
        openCollections()
    else
        ' A surface that does not exist yet SAYS so rather than swallowing the
        ' press — an inert rail item reads as a broken app.
        closeBrowse()
        m.loading.visible = true
        m.loading.text = titleFor(id) + " arrives in a later build."
        focusContent()
    end if
end sub

sub openBrowse(scope as String)
    if m.browse = invalid
        m.browse = m.overlay.CreateChild("BrowseScreen")
        m.browse.translation = [m.t.railW, 0]
        m.browse.service = m.svc
        m.browse.ObserveField("chosen", "onBrowseChosen")
        m.browse.ObserveField("exitLeft", "focusRail")
    end if
    closeLibrary()
    closeSearch()
    closeCollections()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.browse.visible = true
    m.browse.scope = scope
    m.rail.focusOn = false
    ' Do NOT setFocus on the BrowseScreen Group here. Setting focusOn hands
    ' focus to a real Button inside it; taking it back to the Group afterwards
    ' is why every chip press was swallowed — the Button never saw an OK, so
    ' buttonSelected never fired and the screen looked inert while rendering
    ' perfectly.
    m.browse.focusOn = true
    m.route = "browse"
    print "AWFOCUS browse "; scope
end sub

sub closeBrowse()
    if m.browse <> invalid
        m.browse.visible = false
        m.browse.focusOn = false
    end if
    m.content.visible = true
end sub

' Hide-watched is applied HERE rather than in the task: the task's rows are the
' catalog and must stay whole, because the setting can change at any time and
' re-fetching 6 MB to honour a toggle would be absurd.
function filteredRows(rows as Object) as Object
    if rows = invalid then return rows
    if not awGetSetting("hidewatched", false) then return rows
    watched = awWatchedIds()
    if watched.Count() = 0 then return rows
    out = CreateObject("roSGNode", "ContentNode")
    for i = 0 to rows.GetChildCount() - 1
        src = rows.GetChild(i)
        row = out.CreateChild("ContentNode")
        row.title = src.title
        kept = 0
        for j = 0 to src.GetChildCount() - 1
            it = src.GetChild(j)
            if not watched.DoesExist(it.id)
                row.AppendChild(it.Clone(false))
                kept = kept + 1
            end if
        end for
        ' A shelf emptied by the filter is removed, not shown as a bare label.
        if kept < 3 then out.RemoveChild(row)
    end for
    return out
end function

sub reapplyHomeFilter()
    if m.task <> invalid and m.task.status = "ready"
        m.home.rowsContent = filteredRows(m.task.rows)
    end if
end sub

sub openOptions()
    if m.options = invalid
        m.options = m.top.FindNode("options").CreateChild("OptionsPanel")
        m.options.ObserveField("closed", "onOptionsClosed")
        m.options.ObserveField("changed", "onOptionsChanged")
    end if
    m.options.callFunc("open")
end sub

' A screen claims focus through its focusOn field, and onChange only fires on
' a CHANGE — so writing true to a field that is already true does nothing at
' all. After an overlay steals focus, the field is still true while the actual
' focus is gone, and every key then falls through to the Scene: the remote goes
' dead with no error anywhere. Always toggle.
sub refocus(node as Object)
    if node = invalid then return
    node.focusOn = false
    node.focusOn = true
end sub

sub onOptionsClosed()
    ' Hand focus back to whatever the viewer was on — an overlay that closes
    ' onto nothing focused is the same dead remote as one that never opened.
    if m.route = "home"
        m.rail.focusOn = false
        refocus(m.home)
        print "AWFOCUS content"
    else if m.route = "detail"
        refocus(m.detail)
    else if m.route = "browse"
        refocus(m.browse)
    else if m.route = "search"
        refocus(m.search)
    else if m.route = "library"
        refocus(m.library)
    else if m.route = "collections"
        refocus(m.collections)
    else
        focusRail()
    end if
end sub

sub onOptionsChanged()
    ' Clearing progress while Library is open must be visible immediately,
    ' not on the next visit.
    if m.options.changed = "hidewatched" then reapplyHomeFilter()
    if m.options.changed = "progress" and m.route = "library" and m.library <> invalid
        m.library.callFunc("reload", m.task.rows)
    end if
end sub

sub openCollections()
    if m.collections = invalid
        m.collections = m.overlay.CreateChild("CollectionsScreen")
        m.collections.translation = [m.t.railW, 0]
        m.collections.ObserveField("chosen", "onCollectionChosen")
        m.collections.ObserveField("exitLeft", "focusRail")
    end if
    closeBrowse()
    closeSearch()
    closeLibrary()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.collections.visible = true
    m.rail.focusOn = false
    m.route = "collections"
    print "AWFOCUS collections"
    ' Built once per session: 26 rows over a 27,000-row index is a real scan,
    ' and the membership cannot change while the channel is open.
    if m.collectionsBuilt = true
        m.collections.focusOn = true
    else
        m.pendingCollections = true
        m.svc.qCollections = true
        m.svc.queryId = m.svc.queryId + 1
    end if
end sub

sub closeCollections()
    if m.collections <> invalid
        m.collections.visible = false
        m.collections.focusOn = false
    end if
    m.content.visible = true
end sub

sub onCollectionChosen()
    id = m.collections.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

sub openLibrary()
    if m.library = invalid
        m.library = m.overlay.CreateChild("LibraryScreen")
        m.library.translation = [m.t.railW, 0]
        m.library.ObserveField("chosen", "onLibraryChosen")
        m.library.ObserveField("exitLeft", "focusRail")
    end if
    closeBrowse()
    closeSearch()
    closeCollections()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.library.visible = true
    ' Rebuilt on every entry: the registry may have changed while the viewer
    ' was somewhere else in the app, and a stale Library is a lie about their
    ' own saves.
    m.library.callFunc("reload", m.task.rows)
    m.rail.focusOn = false
    m.library.focusOn = true
    m.route = "library"
    print "AWFOCUS library"
end sub

sub closeLibrary()
    if m.library <> invalid
        m.library.visible = false
        m.library.focusOn = false
    end if
    m.content.visible = true
end sub

sub onLibraryChosen()
    id = m.library.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

sub openSearch()
    if m.search = invalid
        m.search = m.overlay.CreateChild("SearchScreen")
        m.search.translation = [m.t.railW, 0]
        m.search.service = m.svc
        m.search.ObserveField("chosen", "onSearchChosen")
        m.search.ObserveField("door", "onSearchDoor")
        m.search.ObserveField("exitLeft", "focusRail")
    end if
    closeBrowse()
    closeLibrary()
    closeCollections()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.search.visible = true
    m.rail.focusOn = false
    m.search.focusOn = true
    m.search.callFunc("resetSearch")
    m.route = "search"
    print "AWFOCUS search"
end sub

sub closeSearch()
    if m.search <> invalid
        m.search.visible = false
        m.search.focusOn = false
    end if
    m.content.visible = true
end sub

sub onSearchChosen()
    id = m.search.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

' §6.4 — the doors. Four open Browse already scoped; Surprise opens a film.
sub onSearchDoor()
    d = m.search.door
    if d = invalid or d = "" then return
    print "AWROKU door "; d
    if d = "surprise"
        id = randomArchiveID()
        if id <> "" then openDetail(id)
        return
    end if
    closeSearch()
    if d = "tv-series" then openBrowse("tv") else openBrowse("movies")
end sub

' Surprise picks from the rows Home already holds, which are the professionally
' presented titles — a random pick that lands on a blank card is a bad door.
function randomArchiveID() as String
    rows = m.task.rows
    if rows = invalid or rows.GetChildCount() = 0 then return ""
    r = rows.GetChild(Rnd(rows.GetChildCount()) - 1)
    if r = invalid or r.GetChildCount() = 0 then return ""
    it = r.GetChild(Rnd(r.GetChildCount()) - 1)
    if it = invalid then return ""
    return it.id
end function

sub onQueryResults()
    ' A deep-link lookup borrows the same results field as Browse and Search,
    ' so it is claimed FIRST and consumed — otherwise a one-row result would
    ' repaint whichever of those happens to be visible.
    if m.pendingCollections = true
        m.pendingCollections = false
        m.svc.qCollections = false
        m.collectionsBuilt = true
        m.collections.callFunc("showResults", m.svc.results, m.svc.total)
        m.collections.focusOn = true
        return
    end if
    if m.pendingDeepLink <> invalid and m.pendingDeepLink <> ""
        id = m.pendingDeepLink
        m.pendingDeepLink = ""
        m.svc.qId = ""
        res = m.svc.results
        if res <> invalid and res.GetChildCount() > 0
            m.deepLinkItem = res.GetChild(0)
        else
            m.deepLinkItem = invalid
        end if
        startDeepLink(id)
        return
    end if
    if m.browse <> invalid and m.browse.visible
        m.browse.callFunc("showResults", m.svc.results, m.svc.total)
    end if
    if m.search <> invalid and m.search.visible
        m.search.callFunc("showResults", m.svc.results, m.svc.total)
    end if
end sub

sub onBrowseChosen()
    id = m.browse.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

' §2.5 — depth is at most 2: rail → surface → item. Detail and the player are
' overlays over the shell rather than a growing stack, which is what keeps
' Back's meaning simple (§2.6).
sub onChosen()
    id = m.home.chosen
    if id = invalid or id = "" then return
    openDetail(id)
end sub

sub openDetail(archiveID as String)
    m.cameFrom = m.route
    m.cameFromBrowse = (m.route = "browse")
    it = findItem(archiveID)
    if it = invalid and m.deepLinkItem <> invalid and m.deepLinkItem.id = archiveID
        it = m.deepLinkItem
    end if
    if m.detail = invalid
        m.detail = m.overlay.CreateChild("DetailScreen")
        m.detail.translation = [m.t.railW, 0]
        m.detail.ObserveField("play", "onPlay")
    end if
    ' The overlay must actually COVER: with Home still composited beneath it,
    ' Home's own hero title and rows read through the scrim as ghosts.
    m.content.visible = false
    if m.browse <> invalid then m.browse.visible = false
    if m.search <> invalid then m.search.visible = false
    if m.library <> invalid then m.library.visible = false
    if m.collections <> invalid then m.collections.visible = false
    m.detail.visible = true
    m.detail.item = it
    m.detail.detail = {}
    m.detail.focusOn = true
    m.home.focusOn = false
    m.rail.focusOn = false
    m.detail.setFocus(true)
    m.route = "detail"
    print "AWFOCUS detail "; archiveID

    if m.dtask = invalid
        m.dtask = CreateObject("roSGNode", "DetailTask")
        m.dtask.ObserveField("detail", "onDetailLoaded")
    end if
    m.dtask.archiveID = archiveID
    m.dtask.control = "RUN"
end sub

sub onDetailLoaded()
    if m.detail <> invalid then m.detail.detail = m.dtask.detail

    ' Direct-to-Play. Roku certification wants a deep link to land ON the
    ' content, not next to it, and the url only exists once the shard has
    ' answered — so the intent is held until here rather than fired at launch.
    if m.autoPlay = true
        m.autoPlay = false
        d = m.dtask.detail
        if d <> invalid and d.url <> invalid and d.url <> ""
            print "AWDEEP autoplay "; m.dtask.archiveID
            m.detail.play = d.url
        else
            print "AWDEEP autoplay ABANDONED — no playable url for "; m.dtask.archiveID
        end if
    end if
end sub

' ---- deep links -----------------------------------------------------------
'
' The catalog may not be parsed yet on a cold start, and a link that arrives
' first must not be dropped: it waits for the service and runs from onSvcReady.
sub onDeepLink()
    id = m.top.deepLinkContentId
    if id = invalid or id = "" then return
    print "AWDEEP contentId="; id; " mediaType="; m.top.deepLinkMediaType
    if m.svc = invalid or not m.svc.ready
        m.queuedDeepLink = id
        return
    end if
    m.pendingDeepLink = id
    m.svc.qId = id
    m.svc.queryId = m.svc.queryId + 1
end sub

sub onSvcReady()
    if m.queuedDeepLink <> invalid and m.queuedDeepLink <> ""
        id = m.queuedDeepLink
        m.queuedDeepLink = ""
        m.pendingDeepLink = id
        m.svc.qId = id
        m.svc.queryId = m.svc.queryId + 1
    end if
end sub

sub startDeepLink(id as String)
    ' A link can arrive at any moment, including mid-film. Tearing the player
    ' down first also writes the final bookmark, so the abandoned film is
    ' resumable rather than silently losing the last few seconds.
    if m.route = "player" then closePlayer()
    ' A film Roku has never heard of still opens: the shard is fetched by id,
    ' and an unknown id fails on the Detail screen with a reason rather than
    ' on a blank one.
    mt = LCase(m.top.deepLinkMediaType)
    m.autoPlay = (mt = "movie" or mt = "episode" or mt = "shortformvideo")
    openDetail(id)
end sub

' Walk the rows we already hold rather than re-querying: the Home content tree
' IS the model, and Detail is opened from it.
function findItem(archiveID as String) as Object
    rows = m.task.rows
    if rows = invalid then return invalid
    for i = 0 to rows.GetChildCount() - 1
        row = rows.GetChild(i)
        for j = 0 to row.GetChildCount() - 1
            it = row.GetChild(j)
            if it.id = archiveID then return it
        end for
    end for
    if m.svc <> invalid and m.svc.results <> invalid
        res = m.svc.results
        for i = 0 to res.GetChildCount() - 1
            it = res.GetChild(i)
            if it.id = archiveID then return it
        end for
    end if
    return invalid
end function

sub onPlay()
    url = m.detail.play
    if url = invalid or url = "" then return
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        m.player.translation = [m.t.railW, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
        m.player.ObserveField("failed", "onPlaybackFailed")
    end if
    m.player.visible = true
    m.detail.visible = false
    m.player.archiveID = m.detail.item.id
    m.player.startAt = m.detail.playFrom
    m.player.playTitle = m.detail.item.title
    m.player.playMeta = m.detail.item.SHORTDESCRIPTIONLINE1
    m.player.playUrl = url
    m.player.setFocus(true)
    m.route = "player"
    print "AWFOCUS player"
end sub

' §6.6 / §2.6 — the end of a film returns the viewer where they came from.
' Stranded on a dead screen is not a state.
sub onPlaybackFailed()
    msg = m.player.failed
    if msg = invalid or msg = "" then return
    print "AWPLAY failed-notice "; msg
    closePlayer()
    m.detail.toast = msg
end sub

sub onPlaybackEnded()
    if m.player <> invalid and m.player.ended then closePlayer()
end sub

sub closePlayer()
    if m.player = invalid then return
    m.player.callFunc("stopPlayback")
    m.player.visible = false
    m.detail.visible = true
    m.detail.callFunc("refresh")
    m.detail.focusOn = true
    m.detail.setFocus(true)
    m.route = "detail"
    print "AWFOCUS detail (from player)"
end sub

sub closeDetail()
    if m.detail <> invalid
        m.detail.visible = false
        m.detail.focusOn = false
    end if
    ' Back returns to the screen the viewer CAME FROM (§2.6), which is Browse
    ' when Detail was opened from a grid.
    if m.collections <> invalid and m.cameFrom = "collections"
        m.collections.visible = true
        m.collections.focusOn = true
        m.route = "collections"
        return
    end if
    if m.library <> invalid and m.cameFrom = "library"
        m.library.visible = true
        m.library.callFunc("reload", m.task.rows)
        m.library.focusOn = true
        m.route = "library"
        return
    end if
    if m.search <> invalid and m.cameFrom = "search"
        m.search.visible = true
        m.search.focusOn = true
        m.route = "search"
        return
    end if
    if m.browse <> invalid and m.cameFromBrowse = true
        m.browse.visible = true
        m.browse.focusOn = true
        m.browse.setFocus(true)
        m.route = "browse"
        return
    end if
    m.content.visible = true
    focusContent()
    m.route = "home"
end sub

function titleFor(id as String) as String
    if id = "movies" then return "Movies"
    if id = "tv" then return "TV"
    if id = "channels" then return "Channels"
    if id = "collections" then return "Collections"
    if id = "search" then return "Search"
    if id = "library" then return "Library"
    return "Home"
end function

function nowString() as String
    d = CreateObject("roDateTime")
    d.ToLocalTime()
    h = d.GetHours()
    ampm = "AM"
    if h >= 12 then ampm = "PM"
    if h > 12 then h = h - 12
    if h = 0 then h = 12
    mn = d.GetMinutes()
    mm = fmt(mn)
    if mn < 10 then mm = "0" + mm
    return fmt(h) + ":" + mm + " " + ampm
end function

' §2.6 — Back is sacred. It is NOT trapped here: returning false lets Roku
' close the channel from Home, which is the platform convention and a
' certification requirement.
' §2.6 — Back is sacred. It pops one level; from Home it is NOT consumed, so
' Roku closes the channel, which is the platform convention and a
' certification requirement.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    print "AWKEY "; key; " route="; m.route
    ' `*` opens Options everywhere EXCEPT playback, where Roku reserves the
    ' key for its own transport overlay (ROKU-DESIGN §3.1) — a channel that
    ' takes it there fails certification.
    if key = "options" and m.route <> "player"
        openOptions()
        return true
    end if
    if key = "back"
        if m.route = "player"
            closePlayer()
            return true
        else if m.route = "detail"
            closeDetail()
            return true
        else if m.route = "browse"
            closeBrowse()
            focusContent()
            m.route = "home"
            return true
        else if m.route = "search"
            closeSearch()
            focusContent()
            m.route = "home"
            return true
        else if m.route = "library"
            closeLibrary()
            focusContent()
            m.route = "home"
            return true
        else if m.route = "collections"
            closeCollections()
            focusContent()
            m.route = "home"
            return true
        end if
        return false
    end if
    return false
end function
