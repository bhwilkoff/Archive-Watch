sub init()
    m.top.functionName = "run"
end sub

function getJson(url as String) as Object
    x = CreateObject("roUrlTransfer")
    x.SetUrl(url)
    ' HTTPS needs the cert bundle named explicitly; without these two lines the
    ' transfer fails silently and returns "".
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.2 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = "" then return invalid
    return ParseJson(body)
end function

sub run()
    span = CreateObject("roTimespan")
    span.Mark()
    m.top.status = "loading"

    featured = getJson("https://archivewatch.org/featured.json")
    index = getJson("https://archivewatch.org/catalog-index.json")
    if index = invalid or index.items = invalid
        m.top.status = "error"
        print "AWROKU home: index unavailable"
        return
    end if
    fetchMs = span.TotalMilliseconds()

    ' Shelf order and titles come from featured.json, which is the same
    ' editorial source every other platform reads — so the shelf ORDER cannot
    ' drift between Roku and the rest.
    order = []
    titles = {}
    subtitles = {}
    if featured <> invalid and featured.shelves <> invalid
        for each sh in featured.shelves
            if sh.id <> invalid
                order.Push(sh.id)
                titles[sh.id] = sh.title
                if sh.subtitle <> invalid then subtitles[sh.id] = sh.subtitle
            end if
        end for
    end if
    ' Any shelf the index publishes that featured.json does not name still gets
    ' shown, after the curated ones, rather than silently dropped.
    for each k in index.shelves
        if titles[k] = invalid
            order.Push(k)
            titles[k] = titleCase(k)
        end if
    end for

    ' ---- collect the ids the shelves name, then ONE pass over the catalog ----
    MAX_PER_ROW = 20
    wanted = {}
    plan = []
    for each id in order
        ids = index.shelves[id]
        if ids <> invalid and ids.Count() > 0
            take = []
            n = ids.Count()
            if n > MAX_PER_ROW then n = MAX_PER_ROW
            for i = 0 to n - 1
                take.Push(ids[i])
                wanted[ids[i]] = true
            end for
            plan.Push({ id: id, ids: take })
        end if
    end for

    span.Mark()
    found = {}
    for each row in index.items
        aid = row[0]
        if wanted[aid] <> invalid
            found[aid] = row
        end if
    end for
    scanMs = span.TotalMilliseconds()

    ' ---- build the ContentNode tree ----
    root = CreateObject("roSGNode", "ContentNode")
    heroPool = CreateObject("roSGNode", "ContentNode")
    rowCount = 0

    for each p in plan
        kids = []
        for each aid in p.ids
            r = found[aid]
            if r <> invalid
                ' ROKU-DESIGN §6.2 — Home shows professional posters only
                ' (Decision 097). A shelf that cannot field six hides rather
                ' than padding itself with frame grabs.
                if r[5] = 1 and r[4] <> invalid and r[4] <> ""
                    kids.Push(r)
                end if
            end if
        end for
        if kids.Count() >= 6
            rowNode = root.CreateChild("ContentNode")
            rowNode.title = titles[p.id]
            if subtitles[p.id] <> invalid then rowNode.SHORTDESCRIPTIONLINE2 = subtitles[p.id]
            for each r in kids
                it = rowNode.CreateChild("ContentNode")
                fillItem(it, r)
            end for
            rowCount = rowCount + 1
            ' The hero pool is drawn from items that carry a real backdrop, so
            ' the hero is never a 2:3 poster stretched into a wide box.
            for each r in kids
                if r[7] <> invalid and r[7] <> "" and heroPool.GetChildCount() < 12
                    h = heroPool.CreateChild("ContentNode")
                    fillItem(h, r)
                end if
            end for
        end if
    end for

    stats = {
        fetchMs: fetchMs, scanMs: scanMs, totalMs: 0,
        rows: rowCount, items: index.items.Count(),
        hero: heroPool.GetChildCount()
    }
    print "AWROKU home rows="; rowCount; " heroPool="; heroPool.GetChildCount(); " fetchMs="; fetchMs; " scanMs="; scanMs

    m.top.hero = heroPool
    m.top.rows = root
    m.top.stats = stats
    m.top.status = "ready"
end sub

' ContentNode has a FIXED set of metadata fields. Assigning one it does not
' declare — BACKGROUNDIMAGEURL was the mistake here — silently does nothing:
' no error, and the reader gets `invalid`. Our own keys are added explicitly.
sub fillItem(n as Object, r as Object)
    n.id = r[0]
    n.title = r[1]
    n.HDPOSTERURL = r[4]
    n.SHORTDESCRIPTIONLINE1 = metaLine(r)
    n.AddField("awBackdrop", "string", false)
    n.AddField("awType", "string", false)
    if r[7] <> invalid then n.awBackdrop = r[7]
    if r[3] <> invalid then n.awType = r[3]
end sub

function metaLine(r as Object) as String
    parts = []
    if r[2] <> invalid then parts.Push(fmt(r[2]))
    if r[3] <> invalid and r[3] <> "" then parts.Push(prettyType(r[3]))
    out = ""
    for i = 0 to parts.Count() - 1
        if i > 0 then out = out + "  ·  "
        out = out + parts[i]
    end for
    return out
end function

function prettyType(t as String) as String
    if t = "feature-film" then return "Feature Film"
    if t = "silent-film" then return "Silent Era"
    if t = "short-film" then return "Short Film"
    if t = "tv-series" then return "Classic TV"
    if t = "tv-special" then return "TV"
    if t = "tv-episode" then return "Episode"
    if t = "animation" then return "Animation"
    if t = "newsreel" then return "Newsreel"
    if t = "documentary" then return "Documentary"
    if t = "ephemeral" then return "Ephemeral"
    if t = "commercial" then return "Commercial"
    return t
end function

function titleCase(slug as String) as String
    out = ""
    up = true
    for i = 0 to Len(slug) - 1
        c = Mid(slug, i + 1, 1)
        if c = "-" or c = "_"
            out = out + " " : up = true
        else
            if up then out = out + UCase(c) else out = out + c
            up = false
        end if
    end for
    return out
end function
