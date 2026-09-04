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
    brand.translation = [m.t.railW + m.t.readX, 39]

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
    m.pendingEpisode = invalid
    m.episodeQueue = invalid
    m.pendingRandom = false
    m.pendingMarathon = false
    m.lineup = invalid
    m.pendingUserItems = false
    m.userItems = invalid
    m.pendingLike = ""
    m.idLineup = invalid
    m.moreMode = "detail"
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
        requestUserItems()
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
    else if id = "channels"
        openChannels()
    else if id = "surprise"
        openSurprise()
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
    closeChannels()
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
' Continue Watching LEADS Home when there is anything in it — the same place
' tvOS puts it, and for the same reason: the most likely thing a viewer wants
' is the film they did not finish. Built from the registry against the rows the
' task already holds, so it costs a lookup and no fetch.
' The viewer's OWN items, resolved against the whole index rather than against
' Home's shelves. Requested once per launch and refreshed whenever the registry
' changes under a surface that shows them.
' Library resolves against BOTH: the shelves it already has, and the viewer's
' own resolved items. Wrapping them in one node keeps LibraryScreen's lookup
' unchanged.
function userCatalog() as Object
    out = CreateObject("roSGNode", "ContentNode")
    if m.userItems <> invalid
        row = out.CreateChild("ContentNode")
        for i = 0 to m.userItems.GetChildCount() - 1
            row.AppendChild(m.userItems.GetChild(i).Clone(false))
        end for
    end if
    if m.task <> invalid and m.task.rows <> invalid
        for i = 0 to m.task.rows.GetChildCount() - 1
            out.AppendChild(m.task.rows.GetChild(i).Clone(true))
        end for
    end if
    return out
end function

sub requestUserItems()
    ids = []
    for each e in awContinueWatching()
        ids.Push(e.id)
    end for
    for each f in awFavorites()
        ids.Push(f)
    end for
    for each p in awPlaylists()
        for each a in p.ids
            ids.Push(a)
        end for
    end for
    if ids.Count() = 0 then return
    m.pendingUserItems = true
    m.svc.qIds = ids
    m.svc.queryId = m.svc.queryId + 1
end sub

sub onUserItemsResolved()
    m.pendingUserItems = false
    m.svc.qIds = []
    m.userItems = m.svc.results
    ' Home was painted before these arrived, so repaint it now that the row can
    ' actually be built.
    if m.task <> invalid and m.task.status = "ready"
        m.home.rowsContent = filteredRows(m.task.rows)
    end if
    if m.route = "library" and m.library <> invalid
        m.library.callFunc("reload", m.userItems)
    end if
end sub

function withContinueWatching(rows as Object) as Object
    if rows = invalid then return rows
    cw = awContinueWatching()
    if cw.Count() = 0 then return rows
    byId = {}
    for i = 0 to rows.GetChildCount() - 1
        row = rows.GetChild(i)
        for j = 0 to row.GetChildCount() - 1
            it = row.GetChild(j)
            byId[it.id] = it
        end for
    end for
    ' Anything resolved from the full index wins: it is the same item, and it
    ' is present for films Home's shelves never name.
    if m.userItems <> invalid
        for i = 0 to m.userItems.GetChildCount() - 1
            it = m.userItems.GetChild(i)
            byId[it.id] = it
        end for
    end if
    out = CreateObject("roSGNode", "ContentNode")
    lead = out.CreateChild("ContentNode")
    lead.title = "Continue Watching"
    n = 0
    for each e in cw
        src = byId[e.id]
        if src <> invalid
            lead.AppendChild(src.Clone(false))
            n = n + 1
        end if
    end for
    ' A row of one is still worth showing here: it is THE film they left.
    if n = 0
        out.RemoveChild(lead)
    end if
    for i = 0 to rows.GetChildCount() - 1
        out.AppendChild(rows.GetChild(i).Clone(true))
    end for
    return out
end function

function filteredRows(rows as Object) as Object
    if rows = invalid then return rows
    if not awGetSetting("hidewatched", false) then return withContinueWatching(rows)
    watched = awWatchedIds()
    if watched.Count() = 0 then return withContinueWatching(rows)
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
    return withContinueWatching(out)
end function

sub reapplyHomeFilter()
    if m.task <> invalid and m.task.status = "ready"
        m.home.rowsContent = filteredRows(m.task.rows)
    end if
end sub

' The More button's menu. Built fresh each time because every entry depends on
' the CURRENT state of this film — a menu that offers "Mark as watched" for a
' film already watched is the same dead control in a new costume.
' Add-to-playlist, in two steps because Roku has no menu-with-inline-text:
' pick an existing list, or open the platform keyboard to name a new one.
' `*` in Library is contextual: it acts on the row the viewer is standing in.
' Roku reserves `*` for options, and the option a viewer wants here is about
' THIS playlist, not about the app.
sub openLibraryOptions()
    if m.more = invalid
        m.more = m.top.FindNode("options").CreateChild("OptionsList")
        m.more.ObserveField("chosen", "onMorePicked")
        m.more.ObserveField("closed", "onMoreClosed")
    end if
    plID = m.library.focusedPlaylist
    opts = [{ id: "playall", label: "Play all in this row" }]
    if plID <> ""
        opts.Push({ id: "removeitem", label: "Remove this film from the playlist" })
        opts.Push({ id: "deletelist", label: "Delete this playlist" })
    end if
    opts.Push({ id: "settings", label: "App settings…" })
    opts.Push({ id: "cancel", label: "Done" })
    m.moreMode = "library"
    m.more.callFunc("open", { title: "Options", options: opts })
end sub

sub onLibraryOptionPicked(pick as String)
    plID = m.library.focusedPlaylist
    if pick = "playall"
        ids = m.library.callFunc("focusedRowIDs")
        if ids <> invalid and ids.Count() > 0 then startIDLineup(ids)
        return
    else if pick = "removeitem" and plID <> ""
        awRemoveFromPlaylist(plID, m.library.focusedItem)
        m.library.callFunc("reload", userCatalog())
    else if pick = "deletelist" and plID <> ""
        awDeletePlaylist(plID)
        m.library.callFunc("reload", userCatalog())
    else if pick = "settings"
        openOptions()
        return
    end if
    refocus(m.library)
end sub

' Play All over a list of archiveIDs. Each url is resolved one at a time as the
' queue advances, because a playlist of 100 films must not fetch 100 shards to
' start the first one.
sub startIDLineup(ids as Object)
    m.idLineup = { ids: ids, index: 0 }
    playIDLineup()
end sub

sub playIDLineup()
    l = m.idLineup
    if l = invalid or l.index >= l.ids.Count()
        m.idLineup = invalid
        closePlayer()
        return
    end if
    m.pendingEpisode = { id: l.ids[l.index], title: "", meta: "Playlist  ·  " + fmt(l.index + 1) + " of " + fmt(l.ids.Count()),
                         queue: l.ids, queueTitles: l.ids, index: l.index, fromLibrary: true }
    if m.dtask = invalid
        m.dtask = CreateObject("roSGNode", "DetailTask")
        m.dtask.ObserveField("detail", "onDetailLoaded")
    end if
    m.dtask.archiveID = l.ids[l.index]
    m.dtask.control = "RUN"
end sub

sub openAddToPlaylist()
    if m.more = invalid
        m.more = m.top.FindNode("options").CreateChild("OptionsList")
        m.more.ObserveField("chosen", "onMorePicked")
        m.more.ObserveField("closed", "onMoreClosed")
    end if
    opts = []
    for each p in awPlaylists()
        opts.Push({ id: "pl:" + p.id, label: p.name + "   (" + fmt(p.ids.Count()) + ")" })
    end for
    opts.Push({ id: "pl:new", label: "New playlist…" })
    opts.Push({ id: "cancel", label: "Done" })
    m.moreMode = "playlist"
    m.more.callFunc("open", { title: "Add to playlist", options: opts })
end sub

' Roku's own keyboard. TWO things are not optional and neither is obvious:
'
'  * A dialog is presented by assigning it to the SCENE's `dialog` field.
'    Declaring a <KeyboardDialog> child and setting visible = true renders
'    nothing at all — no error, no dialog, and the press that opened it looks
'    like a dead control.
'  * Without `buttons` there is a keyboard to type into and NOTHING to confirm
'    with: `buttonSelected` never fires and the only exit is Back.
sub openNamer()
    k = CreateObject("roSGNode", "KeyboardDialog")
    k.title = "Name this playlist"
    k.buttons = ["Save", "Cancel"]
    k.ObserveField("buttonSelected", "onNamerButton")
    ' A dialog dismissed with Back closes itself; without this the Scene keeps
    ' a dead dialog assigned and every later key goes to it.
    k.ObserveField("wasClosed", "onNamerClosed")
    m.namer = k
    m.top.dialog = k
end sub

sub onNamerClosed()
    m.top.dialog = invalid
    m.namer = invalid
    refocus(m.detail)
end sub

sub onNamerButton()
    k = m.namer
    if k = invalid then return
    print "AWPL namer button="; k.buttonSelected; " text='"; k.text; "'"
    ' Button 0 is OK, 1 is Cancel on Roku's own dialog.
    if k.buttonSelected = 0
        id = awCreatePlaylist(k.text)
        if id = invalid
            m.detail.toast = "You have the maximum number of playlists. Delete one in Library first."
        else
            awAddToPlaylist(id, m.detail.item.id)
            m.detail.toast = "Added to " + awSanitizeName(k.text) + "."
        end if
    end if
    m.top.dialog = invalid
    m.namer = invalid
    refocus(m.detail)
end sub

sub onWantLike()
    spec = m.detail.wantLike
    if spec = invalid or spec.id = invalid then return
    m.pendingLike = spec.id
    m.svc.qLike = spec
    m.svc.queryId = m.svc.queryId + 1
end sub

' Selecting from "more like this" opens that film — which means Detail replaces
' itself. cameFrom is left alone so Back still returns where the viewer
' originally came from rather than walking a chain of Details.
sub onDetailChosen()
    id = m.detail.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

sub onDetailMore()
    if m.more = invalid
        m.more = m.top.FindNode("options").CreateChild("OptionsList")
        m.more.ObserveField("chosen", "onMorePicked")
        m.more.ObserveField("closed", "onMoreClosed")
    end if
    id = m.detail.item.id
    opts = []
    if awIsWatched(id)
        opts.Push({ id: "unwatch", label: "Mark as not watched" })
    else
        opts.Push({ id: "watch", label: "Mark as watched" })
    end if
    if awGetProgress(id) > 0
        opts.Push({ id: "restart", label: "Start from the beginning" })
    end if
    if awIsFavorite(id)
        opts.Push({ id: "unsave", label: "Remove from Library" })
    else
        opts.Push({ id: "save", label: "Save to Library" })
    end if
    opts.Push({ id: "playlist", label: "Add to playlist" })
    opts.Push({ id: "cancel", label: "Done" })
    m.moreMode = "detail"
    m.more.callFunc("open", { title: "More", options: opts })
end sub

sub onMoreClosed()
    if m.moreMode = "library"
        refocus(m.library)
    else
        refocus(m.detail)
    end if
end sub

sub onPlaylistPicked(pick as String)
    if pick = "pl:new"
        openNamer()
        return
    end if
    if Left(pick, 3) = "pl:"
        plID = Mid(pick, 4)
        if awAddToPlaylist(plID, m.detail.item.id)
            m.detail.toast = "Added to your playlist."
        else
            m.detail.toast = "That playlist is full."
        end if
    end if
    refocus(m.detail)
end sub

sub onMorePicked()
    pick = m.more.chosen
    if m.moreMode = "playlist"
        onPlaylistPicked(pick)
        return
    end if
    if m.moreMode = "library"
        onLibraryOptionPicked(pick)
        return
    end if
    id = m.detail.item.id
    if pick = "playlist"
        openAddToPlaylist()
        return
    end if
    if pick = "watch"
        awMarkWatched(id, m.detail.runtimeSeconds)
        m.detail.toast = "Marked as watched."
    else if pick = "unwatch"
        awClearProgressFor(id)
        m.detail.toast = "Marked as not watched."
    else if pick = "restart"
        awClearProgressFor(id)
        m.detail.toast = "Next play starts from the beginning."
    else if pick = "save" or pick = "unsave"
        r = awToggleFavorite(id)
        if r = invalid
            m.detail.toast = "Your library is full. Remove something in Library first."
        else if r
            m.detail.toast = "Saved to your library."
        else
            m.detail.toast = "Removed from your library."
        end if
    end if
    m.detail.callFunc("refresh")
    refocus(m.detail)
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
    else if m.route = "channels"
        refocus(m.channels)
    else if m.route = "series"
        refocus(m.series)
    else if m.route = "surprise"
        refocus(m.surprise)
    else
        focusRail()
    end if
end sub

sub onOptionsChanged()
    ' Clearing progress while Library is open must be visible immediately,
    ' not on the next visit.
    if m.options.changed = "hidewatched" then reapplyHomeFilter()
    if m.options.changed = "progress" and m.route = "library" and m.library <> invalid
        m.library.callFunc("reload", userCatalog())
    end if
end sub

' Every surface hidden in ONE place. Adding the eighth screen to seven separate
' open* functions is how a stale surface ends up composited under a new one —
' it already happened twice in this build.
sub hideAllSurfaces()
    closeBrowse()
    closeSearch()
    closeLibrary()
    closeCollections()
    closeChannels()
    closeSeries()
    if m.surprise <> invalid then m.surprise.visible = false
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
end sub

sub openBrowseFiltered(wantType as String, decade as Integer)
    openBrowse("movies")
    m.browse.callFunc("applyFilter", { type: wantType, decade: decade })
    m.cameFrom = "surprise"
end sub

' A marathon is a QUEUE, not a channel: it starts at the beginning of the first
' cartoon rather than joining one in progress, and it never writes resume
' progress — the same rule Channels follows, for the same reason.
sub startCartoonMarathon()
    if m.chtask = invalid
        m.chtask = CreateObject("roSGNode", "ChannelsTask")
        m.chtask.ObserveField("status", "onChannelsLoaded")
        m.pendingMarathon = true
        m.chtask.control = "RUN"
        return
    end if
    buildMarathon()
end sub

sub buildMarathon()
    data = m.chtask.channels
    if data = invalid or data.list = invalid then return
    pool = invalid
    for each c in data.list
        if LCase(fmt(c.id)) = "cartoon" then pool = c.programs
    end for
    if pool = invalid or pool.Count() = 0
        print "AWSURP no cartoon pool"
        return
    end if
    urls = [] : titles = []
    ' Shuffled so a marathon is different every time it is started.
    idx = []
    for i = 0 to pool.Count() - 1
        idx.Push(i)
    end for
    for i = idx.Count() - 1 to 1 step -1
        j = Rnd(i + 1) - 1
        t = idx[i] : idx[i] = idx[j] : idx[j] = t
    end for
    n = 0
    for each i in idx
        p = pool[i]
        if p[3] <> invalid and p[3] <> ""
            urls.Push(fmt(p[3]))
            titles.Push(fmt(p[1]))
            n = n + 1
            if n >= 40 then exit for
        end if
    end for
    if urls.Count() = 0 then return
    m.lineup = { urls: urls, titles: titles, index: 0 }
    playLineup()
end sub

sub playLineup()
    l = m.lineup
    if l = invalid or l.index >= l.urls.Count()
        m.lineup = invalid
        closePlayer()
        return
    end if
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        m.player.translation = [0, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
        m.player.ObserveField("failed", "onPlaybackFailed")
    end if
    hideAllSurfaces()
    m.player.visible = true
    m.player.archiveID = ""
    m.player.startAt = 0
    m.player.playTitle = l.titles[l.index]
    m.player.playMeta = "Cartoon Marathon  ·  " + fmt(l.index + 1) + " of " + fmt(l.urls.Count())
    m.player.captionUrl = ""
    setChromeVisible(false)
    m.player.playUrl = l.urls[l.index]
    m.player.setFocus(true)
    m.cameFrom = "surprise"
    m.route = "player"
    print "AWSURP marathon "; l.index + 1; "/"; l.urls.Count()
end sub

sub openSurprise()
    if m.surprise = invalid
        m.surprise = m.overlay.CreateChild("SurpriseScreen")
        m.surprise.translation = [m.t.railW, 0]
        m.surprise.ObserveField("action", "onSurpriseAction")
        m.surprise.ObserveField("exitLeft", "focusRail")
    end if
    hideAllSurfaces()
    m.surprise.visible = true
    m.rail.focusOn = false
    m.route = "surprise"
    refocus(m.surprise)
    print "AWFOCUS surprise"
end sub

sub closeSurprise()
    if m.surprise <> invalid
        m.surprise.visible = false
        m.surprise.focusOn = false
    end if
    m.content.visible = true
end sub

sub onSurpriseAction()
    a = m.surprise.action
    if a = invalid or a = "" then return
    print "AWSURP "; a
    if Left(a, 5) = "type:"
        ' The service picks; the results observer routes. A door that re-rolls
        ' has to go back to the service every press, which is why this is not
        ' cached anywhere.
        m.pendingRandom = true
        m.svc.qRandomType = Mid(a, 6)
        m.svc.queryId = m.svc.queryId + 1
    else if a = "browse:decade"
        ' A decade is a place to wander, not a single film.
        d = 1900 + Rnd(8) * 10
        openBrowseFiltered("", d)
    else if a = "cartoons"
        startCartoonMarathon()
    end if
end sub

sub onRandomPicked()
    m.pendingRandom = false
    m.pendingMarathon = false
    m.lineup = invalid
    m.pendingUserItems = false
    m.userItems = invalid
    m.pendingLike = ""
    m.idLineup = invalid
    m.moreMode = "detail"
    m.svc.qRandomType = ""
    res = m.svc.results
    if res = invalid or res.GetChildCount() = 0
        print "AWSURP nothing matched"
        return
    end if
    it = res.GetChild(0)
    m.deepLinkItem = it
    openDetail(it.id)
end sub

sub openSeries(slug as String)
    if m.series = invalid
        m.series = m.overlay.CreateChild("SeriesScreen")
        m.series.translation = [m.t.railW, 0]
        m.series.ObserveField("playEpisode", "onPlayEpisode")
        m.series.ObserveField("exitLeft", "focusRail")
    end if
    m.cameFromSeries = m.route
    closeBrowse()
    closeSearch()
    closeLibrary()
    closeCollections()
    closeChannels()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.series.visible = true
    m.rail.focusOn = false
    m.route = "series"
    print "AWFOCUS series "; slug

    if m.stask = invalid
        m.stask = CreateObject("roSGNode", "SeriesTask")
        m.stask.ObserveField("status", "onSeriesLoaded")
    end if
    m.stask.slug = slug
    m.stask.control = "RUN"
end sub

sub onSeriesLoaded()
    if m.stask.status = "ready"
        m.series.callFunc("showSeries", m.stask.series)
        if m.route = "series" then refocus(m.series)
    else
        m.series.callFunc("showSeries", invalid)
    end if
end sub

sub closeSeries()
    if m.series <> invalid
        m.series.visible = false
        m.series.focusOn = false
    end if
    m.content.visible = true
end sub

' An episode's playable url lives in its own detail shard, exactly like a film's
' — the series spine carries identity and artwork, never a file.
sub onPlayEpisode()
    e = m.series.playEpisode
    if e = invalid or e.id = invalid then return
    m.pendingEpisode = e
    if m.dtask = invalid
        m.dtask = CreateObject("roSGNode", "DetailTask")
        m.dtask.ObserveField("detail", "onDetailLoaded")
    end if
    m.dtask.archiveID = e.id
    m.dtask.control = "RUN"
end sub

sub playPendingEpisode(d as Object)
    e = m.pendingEpisode
    m.pendingEpisode = invalid
    if d = invalid or d.url = invalid or d.url = ""
        print "AWSER queued item has no playable url: "; e.id
        ' A dead item must not end the whole queue — skip to the next.
        if m.idLineup <> invalid
            m.idLineup.index = m.idLineup.index + 1
            playIDLineup()
            return
        end if
        if m.series <> invalid then m.series.visible = true
        return
    end if
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        m.player.translation = [0, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
        m.player.ObserveField("failed", "onPlaybackFailed")
    end if
    m.episodeQueue = e
    m.player.visible = true
    m.series.visible = false
    m.player.archiveID = e.id
    m.player.startAt = awGetProgress(e.id)
    t = e.title
    if t = "" and d.canonicalTitle <> invalid then t = fmt(d.canonicalTitle)
    if t = "" then t = e.id
    m.player.playTitle = t
    m.player.playMeta = e.meta
    m.player.captionUrl = ""
    setChromeVisible(false)
    m.player.playUrl = d.url
    m.player.setFocus(true)
    if e.fromLibrary = true then m.cameFrom = "library" else m.cameFrom = "series"
    m.route = "player"
    print "AWFOCUS player (queued "; e.id; ")"
end sub

sub openChannels()
    if m.channels = invalid
        m.channels = m.overlay.CreateChild("ChannelsScreen")
        m.channels.translation = [m.t.railW, 0]
        m.channels.ObserveField("tune", "onTune")
        m.channels.ObserveField("chosen", "onChannelItemChosen")
        m.channels.ObserveField("exitLeft", "focusRail")
    end if
    closeBrowse()
    closeSearch()
    closeLibrary()
    closeCollections()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.channels.visible = true
    m.rail.focusOn = false
    m.route = "channels"
    print "AWFOCUS channels"
    if m.chtask = invalid
        m.chtask = CreateObject("roSGNode", "ChannelsTask")
        m.chtask.ObserveField("status", "onChannelsLoaded")
        m.chtask.control = "RUN"
    else
        refocus(m.channels)
    end if
end sub

sub onChannelsLoaded()
    if m.pendingMarathon = true
        m.pendingMarathon = false
        if m.chtask.status = "ready" then buildMarathon()
        return
    end if
    if m.chtask.status = "ready"
        m.channels.callFunc("showChannels", m.chtask.channels)
        if m.route = "channels" then refocus(m.channels)
    else
        m.channels.callFunc("showChannels", invalid)
    end if
end sub

sub closeChannels()
    if m.channels <> invalid
        m.channels.visible = false
        m.channels.focusOn = false
    end if
    m.content.visible = true
end sub

sub onChannelItemChosen()
    id = m.channels.chosen
    if id <> invalid and id <> "" then openDetail(id)
end sub

' A channel plays through the SAME player, but it must never write a resume
' position: a channel is a clock, and "continue watching" a clock is nonsense.
sub onTune()
    t = m.channels.tune
    if t = invalid or t.url = invalid or t.url = "" then return
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        m.player.translation = [0, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
        m.player.ObserveField("failed", "onPlaybackFailed")
    end if
    m.player.visible = true
    m.channels.visible = false
    m.player.archiveID = ""
    m.player.startAt = t.startAt
    m.player.playTitle = t.title
    m.player.playMeta = t.meta
    m.player.captionUrl = ""
    setChromeVisible(false)
    m.player.playUrl = t.url
    m.player.setFocus(true)
    m.cameFrom = "channels"
    m.route = "player"
    print "AWFOCUS player (channel, join at "; t.startAt; "s)"
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
    closeChannels()
    m.content.visible = false
    m.loading.visible = false
    if m.detail <> invalid then m.detail.visible = false
    m.library.visible = true
    ' Rebuilt on every entry: the registry may have changed while the viewer
    ' was somewhere else in the app, and a stale Library is a lie about their
    ' own saves.
    requestUserItems()
    m.library.callFunc("reload", userCatalog())
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
    closeChannels()
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
    if m.pendingLike <> invalid and m.pendingLike <> ""
        m.pendingLike = ""
        m.svc.qLike = {}
        if m.detail <> invalid then m.detail.callFunc("showLike", m.svc.results)
        return
    end if
    if m.pendingUserItems = true
        onUserItemsResolved()
        return
    end if
    if m.pendingRandom = true
        onRandomPicked()
        return
    end if
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

' A `series:` id names a show, not a file. Routing one to the film Detail
' screen produced a page with no url and a Play button that could not work —
' the TV surface dead-ended there for its whole existence.
sub openDetail(archiveID as String)
    if Left(archiveID, 7) = "series:"
        openSeries(Mid(archiveID, 8))
        return
    end if
    if m.route <> "detail" then m.cameFrom = m.route
    m.cameFromBrowse = (m.route = "browse")
    it = findItem(archiveID)
    if it = invalid and m.deepLinkItem <> invalid and m.deepLinkItem.id = archiveID
        it = m.deepLinkItem
    end if
    if m.detail = invalid
        m.detail = m.overlay.CreateChild("DetailScreen")
        m.detail.translation = [m.t.railW, 0]
        m.detail.ObserveField("play", "onPlay")
        m.detail.ObserveField("showMore", "onDetailMore")
        m.detail.ObserveField("wantLike", "onWantLike")
        m.detail.ObserveField("chosen", "onDetailChosen")
    end if
    ' The overlay must actually COVER: with Home still composited beneath it,
    ' Home's own hero title and rows read through the scrim as ghosts.
    m.content.visible = false
    if m.browse <> invalid then m.browse.visible = false
    if m.search <> invalid then m.search.visible = false
    if m.library <> invalid then m.library.visible = false
    if m.collections <> invalid then m.collections.visible = false
    if m.channels <> invalid then m.channels.visible = false
    if m.series <> invalid then m.series.visible = false
    if m.surprise <> invalid then m.surprise.visible = false
    m.detail.visible = true
    m.detail.item = it
    m.detail.detail = {}
    m.home.focusOn = false
    m.rail.focusOn = false
    ' refocus(), never `focusOn = true`. On the SECOND visit the field is
    ' already true, onChange does not fire, and `setFocus` on a Group does
    ' nothing — so Detail draws with its buttons unreachable and every press
    ' falls through to the Scene. Silent failure #18, in a path that predates
    ' the helper.
    refocus(m.detail)
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
    ' The episode path borrows the same task, so it is claimed FIRST and
    ' consumed — otherwise an episode's payload would repaint the film Detail
    ' screen sitting behind it.
    if m.pendingEpisode <> invalid
        playPendingEpisode(m.dtask.detail)
        return
    end if
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
    if id = "selftest:store"
        print awStoreSelfTest()
        return
    end if
    if id = "selftest:layout"
        ' Audits whatever is on screen right now, so the harness can walk the
        ' app and measure each surface as it arrives at it.
        print awAuditLayout(m.top, m.route)
        return
    end if
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

' The film owns the screen. Leaving the rail and the overhang composited over
' playback is the same defect Decision 103 records on Android, where the tab
' bar rode into the PiP tile: chrome that is right for browsing is never right
' over a picture.
sub setChromeVisible(on as Boolean)
    m.rail.visible = on
    m.top.FindNode("overhang").visible = on
    m.top.FindNode("brand").visible = on
    m.top.FindNode("clock").visible = on
    m.top.FindNode("optHint").visible = on
end sub

sub onPlay()
    url = m.detail.play
    if url = invalid or url = "" then return
    if m.player = invalid
        m.player = m.overlay.CreateChild("PlayerScreen")
        ' Full-bleed: the player is NOT inset by the rail, because the rail is
        ' not on screen while it plays.
        m.player.translation = [0, 0]
        m.player.ObserveField("ended", "onPlaybackEnded")
        m.player.ObserveField("failed", "onPlaybackFailed")
    end if
    m.player.visible = true
    m.detail.visible = false
    m.player.archiveID = m.detail.item.id
    m.player.startAt = m.detail.playFrom
    m.player.playTitle = m.detail.item.title
    m.player.playMeta = m.detail.item.SHORTDESCRIPTIONLINE1
    m.player.captionUrl = m.detail.captionUrl
    setChromeVisible(false)
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
    if m.player = invalid or not m.player.ended then return
    if m.lineup <> invalid
        m.lineup.index = m.lineup.index + 1
        playLineup()
        return
    end if
    if m.idLineup <> invalid
        m.idLineup.index = m.idLineup.index + 1
        playIDLineup()
        return
    end if
    q = m.episodeQueue
    if q <> invalid and awGetSetting("autoplay", true)
        nxt = q.index + 1
        if nxt < q.queue.Count()
            print "AWSER autoplay next episode "; q.queue[nxt]
            m.pendingEpisode = { id: q.queue[nxt], title: q.queueTitles[nxt],
                                 meta: q.meta, queue: q.queue,
                                 queueTitles: q.queueTitles, index: nxt }
            m.dtask.archiveID = q.queue[nxt]
            m.dtask.control = "RUN"
            return
        end if
    end if
    closePlayer()
end sub

sub closePlayer()
    if m.player = invalid then return
    m.episodeQueue = invalid
    m.lineup = invalid
    m.idLineup = invalid
    m.player.callFunc("stopPlayback")
    m.player.visible = false
    setChromeVisible(true)

    ' A channel has no Detail screen to go back to. Returning to one anyway
    ' left the viewer on a BLANK screen with the rail focused — nothing hidden
    ' was ever shown again. Where the player was entered from decides where
    ' Back lands, which is the same rule every other surface here follows.
    if m.cameFrom = "library" and m.library <> invalid
        m.library.visible = true
        m.library.callFunc("reload", userCatalog())
        refocus(m.library)
        m.route = "library"
        return
    end if
    if m.cameFrom = "series" and m.series <> invalid
        m.series.visible = true
        m.series.callFunc("refreshProgress")
        refocus(m.series)
        m.route = "series"
        print "AWFOCUS series (from player)"
        return
    end if
    if m.cameFrom = "channels" and m.channels <> invalid
        m.channels.visible = true
        refocus(m.channels)
        m.route = "channels"
        print "AWFOCUS channels (from player)"
        return
    end if

    if m.detail = invalid
        focusContent()
        m.route = "home"
        print "AWFOCUS home (from player, no detail)"
        return
    end if
    m.detail.visible = true
    m.detail.callFunc("refresh")
    refocus(m.detail)
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
    if m.surprise <> invalid and m.cameFrom = "surprise"
        m.surprise.visible = true
        refocus(m.surprise)
        m.route = "surprise"
        return
    end if
    if m.channels <> invalid and m.cameFrom = "channels"
        m.channels.visible = true
        refocus(m.channels)
        m.route = "channels"
        return
    end if
    if m.collections <> invalid and m.cameFrom = "collections"
        m.collections.visible = true
        m.collections.focusOn = true
        m.route = "collections"
        return
    end if
    if m.library <> invalid and m.cameFrom = "library"
        m.library.visible = true
        m.library.callFunc("reload", userCatalog())
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
    if key = "options" and m.route = "library" and m.library <> invalid
        openLibraryOptions()
        return true
    end if
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
        else if m.route = "channels"
            closeChannels()
            focusContent()
            m.route = "home"
            return true
        else if m.route = "series"
            closeSeries()
            focusContent()
            m.route = "home"
            return true
        else if m.route = "surprise"
            closeSurprise()
            focusContent()
            m.route = "home"
            return true
        end if
        return false
    end if
    return false
end function
