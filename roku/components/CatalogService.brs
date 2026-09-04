sub init()
    m.top.functionName = "run"
end sub

sub run()
    port = CreateObject("roMessagePort")
    ' queryId is the ONLY trigger. Observing every query field separately would
    ' recompute once per field on a multi-field change; the caller sets the
    ' fields and then bumps queryId exactly once.
    m.top.ObserveField("queryId", port)

    x = CreateObject("roUrlTransfer")
    x.SetUrl("https://archivewatch.org/catalog-index.json")
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("User-Agent", "ArchiveWatch-Roku/0.4 (+https://archivewatch.org)")
    x.EnableEncodings(true)
    body = x.GetToString()
    if body = ""
        print "AWSVC index fetch failed"
        return
    end if
    idx = ParseJson(body)
    body = ""
    if idx = invalid or idx.items = invalid
        print "AWSVC index parse failed"
        return
    end if
    m.items = idx.items
    m.collections = idx.collections
    ' The curated titles and blurbs ride in the package (see tools/roku.py),
    ' the MEMBERSHIP rides in the index. Neither is fetched twice.
    m.colMeta = []
    cm = ReadAsciiFile("pkg:/collections.json")
    if cm <> ""
        parsed = ParseJson(cm)
        if parsed <> invalid and parsed.collections <> invalid then m.colMeta = parsed.collections
    end if
    print "AWSVC ready items="; m.items.Count(); " collections="; m.colMeta.Count()
    m.top.ready = true

    while true
        msg = wait(0, port)
        if type(msg) = "roSGNodeEvent"
            if msg.GetField() = "queryId" then runQuery()
        end if
    end while
end sub

' Index row order (build_catalog_index.py fields):
'   0 id  1 title  2 year  3 contentType  4 poster  5 pro  6 search  7 backdrop
' One pass over 26,965 rows collecting only the ~3,100 ids the 26 curated
' collections name — the same shape HomeTask uses, and for the same reason:
' scanning once per collection would be 26 passes on the wrong thread.
sub buildCollections()
    span = CreateObject("roTimespan")
    span.Mark()
    if m.collections = invalid or m.colMeta.Count() = 0
        m.top.results = CreateObject("roSGNode", "ContentNode")
        m.top.total = 0
        return
    end if

    want = {}
    for each c in m.colMeta
        ids = m.collections[c.id]
        if ids <> invalid
            for each aid in ids
                want[aid] = true
            end for
        end if
    end for

    found = {}
    for each r in m.items
        aid = fmt(r[0])
        if want[aid] <> invalid then found[aid] = r
    end for

    root = CreateObject("roSGNode", "ContentNode")
    shown = 0
    for each c in m.colMeta
        ids = m.collections[c.id]
        if ids = invalid then continue for
        row = root.CreateChild("ContentNode")
        row.title = c.title
        row.AddField("awBlurb", "string", false)
        row.AddField("awAccent", "string", false)
        if c.blurb <> invalid then row.awBlurb = c.blurb
        if c.accent <> invalid then row.awAccent = BroadcastSafe(c.accent)
        n = 0
        for each aid in ids
            r = found[aid]
            if r <> invalid
                appendRow(row, r)
                n = n + 1
                if n >= 60 then exit for
            end if
        end for
        ' A collection thinner than a screenful is a gap in the data, not a
        ' shelf — the same minimum Home applies.
        if n < 6
            root.RemoveChild(row)
        else
            shown = shown + 1
        end if
    end for
    print "AWSVC collections rows="; shown; " of "; m.colMeta.Count(); " in "; span.TotalMilliseconds(); "ms"
    m.top.total = shown
    m.top.results = root
end sub

' Reservoir sampling: one pass, one row kept, no second array of 26,965
' candidates built only to throw all but one of them away.
sub pickRandom(spec as String)
    want = LCase(spec)
    anyType = (want = "" or want = "any")
    rnd = CreateObject("roDeviceInfo").GetRandomUUID()
    seen = 0
    keep = invalid
    for each r in m.items
        if not anyType
            t = LCase(fmt(r[3]))
            if t <> want then continue for
        end if
        ' Professional artwork only: a random pick is a RECOMMENDATION, and
        ' Decision 097 keeps frame grabs off surfaces that recommend.
        if r[5] <> 1 then continue for
        if Left(fmt(r[0]), 7) = "series:" then continue for
        seen = seen + 1
        if Rnd(seen) = 1 then keep = r
    end for
    root = CreateObject("roSGNode", "ContentNode")
    if keep <> invalid then appendRow(root, keep)
    print "AWSVC random type='"; want; "' pool="; seen; " picked="; root.GetChildCount()
    m.top.total = seen
    m.top.results = root
end sub

' One pass, results returned in the ORDER ASKED — a Continue Watching row is
' newest-first and must not be re-sorted into catalog order on the way back.
sub moreLike(spec as Object)
    want = LCase(fmt(spec.contentType))
    year = 0
    if spec.year <> invalid then year = Int(spec.year)
    hits = []
    for each r in m.items
        if fmt(r[0]) = spec.id then continue for
        if r[5] <> 1 then continue for
        if Left(fmt(r[0]), 7) = "series:" then continue for
        if want <> "" and LCase(fmt(r[3])) <> want then continue for
        if year > 0
            y = r[2]
            if y = invalid then continue for
            d = y - year
            if d < 0 then d = -d
            if d > 15 then continue for
        end if
        hits.Push(r)
    end for
    root = CreateObject("roSGNode", "ContentNode")
    ' Sampled, not sliced: taking the first 12 of a type would show the same
    ' twelve films on every 1950s drama in the catalog.
    n = hits.Count()
    take = 12
    if n < take then take = n
    used = {}
    got = 0
    guard = 0
    while got < take and guard < 400
        guard = guard + 1
        i = Rnd(n) - 1
        if used[fmt(i)] = invalid
            used[fmt(i)] = true
            appendRow(root, hits[i])
            got = got + 1
        end if
    end while
    print "AWSVC moreLike type='"; want; "' pool="; n; " shown="; root.GetChildCount()
    m.top.total = n
    m.top.results = root
end sub

sub resolveIds(ids as Object)
    want = {}
    for each i in ids
        want[fmt(i)] = true
    end for
    found = {}
    for each r in m.items
        aid = fmt(r[0])
        if want[aid] <> invalid then found[aid] = r
    end for
    root = CreateObject("roSGNode", "ContentNode")
    for each i in ids
        r = found[fmt(i)]
        if r <> invalid then appendRow(root, r)
    end for
    print "AWSVC resolveIds asked="; ids.Count(); " found="; root.GetChildCount()
    m.top.total = root.GetChildCount()
    m.top.results = root
end sub

sub appendRow(root as Object, r as Object)
    it = root.CreateChild("ContentNode")
    it.id = r[0]
    it.title = StripHTML(fmt(r[1]))
    it.HDPOSTERURL = r[4]
    it.SHORTDESCRIPTIONLINE1 = metaFor(r)
    it.AddField("awBackdrop", "string", false)
    it.AddField("awType", "string", false)
    if r[7] <> invalid then it.awBackdrop = r[7]
    if r[3] <> invalid then it.awType = r[3]
end sub

sub runQuery()
    span = CreateObject("roTimespan")
    span.Mark()

    if m.top.qCollections
        buildCollections()
        return
    end if

    if m.top.qRandomType <> ""
        pickRandom(m.top.qRandomType)
        return
    end if

    lk = m.top.qLike
    if lk <> invalid and lk.id <> invalid and lk.id <> ""
        moreLike(lk)
        return
    end if

    ids = m.top.qIds
    if ids <> invalid and ids.Count() > 0
        resolveIds(ids)
        return
    end if

    ' A deep link asks for ONE id and must not pay for a full scan-and-sort.
    wantId = m.top.qId
    if wantId <> ""
        root = CreateObject("roSGNode", "ContentNode")
        for each r in m.items
            if fmt(r[0]) = wantId
                appendRow(root, r)
                exit for
            end if
        end for
        print "AWSVC lookup "; wantId; " found="; root.GetChildCount()
        m.top.total = root.GetChildCount()
        m.top.results = root
        return
    end if
    wantType = LCase(m.top.qType)
    decade = m.top.qDecade
    text = LCase(m.top.qText)
    sort = m.top.qSort

    hits = []
    for each r in m.items
        if wantType <> "" and wantType <> "all"
            t = LCase(fmt(r[3]))
            ' TV browse shows SERIES, never loose episodes (Decision 036).
            if wantType = "tv-series"
                if t <> "tv-series" and t <> "tv-special" then goto_next = true else goto_next = false
            else
                goto_next = (t <> wantType)
            end if
            if goto_next then continue for
        end if
        if decade > 0
            y = r[2]
            if y = invalid then continue for
            if y < decade or y > decade + 9 then continue for
        end if
        if text <> ""
            ' Title first, then the prebuilt search blob — the index carries a
            ' keyword field precisely so a client does not have to fetch more.
            hay = LCase(fmt(r[1]))
            if Instr(1, hay, text) = 0
                blob = LCase(fmt(r[6]))
                if Instr(1, blob, text) = 0 then continue for
            end if
        end if
        hits.Push(r)
    end for

    ' §6.2 — professional posters lead. This is the Home gate (Decision 097)
    ' relaxed into an ORDERING for Browse, where hiding a film the viewer
    ' explicitly filtered for would be worse than showing a plain card.
    if sort = "popular"
        sorted = []
        for each r in hits
            if r[5] = 1 then sorted.Push(r)
        end for
        for each r in hits
            if r[5] <> 1 then sorted.Push(r)
        end for
        hits = sorted
    else if sort = "newest" or sort = "oldest"
        hits = sortByYear(hits, sort = "oldest")
    end if

    total = hits.Count()
    root = CreateObject("roSGNode", "ContentNode")
    n = total
    if n > 300 then n = 300          ' one screenful plus deep scroll
    for i = 0 to n - 1
        appendRow(root, hits[i])
    end for
    print "AWSVC query type="; wantType; " decade="; decade; " text='"; text; "' hits="; total; " in "; span.TotalMilliseconds(); "ms"
    m.top.total = total
    m.top.results = root
end sub

' Insertion sort is fine here: the filtered set is what gets sorted, not the
' whole catalog, and BrightScript has no stable sort for arrays of arrays.
function sortByYear(rows as Object, ascending as Boolean) as Object
    ' A year-less row sorts LAST either way. SQLite's NULL-first default is
    ' exactly the bug the Android TV audit found in Browse's "Oldest", where
    ' page one was year-less modern uploads instead of the oldest films.
    withYear = []
    without = []
    for each r in rows
        if r[2] = invalid then without.Push(r) else withYear.Push(r)
    end for
    n = withYear.Count()
    for i = 1 to n - 1
        cur = withYear[i]
        j = i - 1
        while j >= 0
            cmp = false
            if ascending then cmp = (withYear[j][2] > cur[2]) else cmp = (withYear[j][2] < cur[2])
            if not cmp then exit while
            withYear[j + 1] = withYear[j]
            j = j - 1
        end while
        withYear[j + 1] = cur
    end for
    for each r in without
        withYear.Push(r)
    end for
    return withYear
end function

function metaFor(r as Object) as String
    out = ""
    if r[2] <> invalid then out = fmt(r[2])
    if r[3] <> invalid and r[3] <> ""
        if out <> "" then out = out + "  ·  "
        out = out + prettyType(fmt(r[3]))
    end if
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
