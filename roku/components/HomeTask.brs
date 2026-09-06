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
    index = getJson("https://archivewatch.org/catalog-index.json?t=" + fmt(CreateObject("roDateTime").AsSeconds()))
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
    ' Every id a shelf names is resolved, not the first 20 — the professional-
    ' poster gate below is applied to what comes back, and truncating first
    ' means judging a shelf on a slice of itself. Measured: Prelinger names 48
    ' ids of which 7 carry a professional poster and NONE is in the first 20,
    ' so the shelf was hidden entirely while qualifying for a full row. Same
    ' shape as Decision 049, where a contiguous slice of a priority list
    ' rendered a shelf nothing like the pool it came from.
    MAX_RESOLVE = 60
    wanted = {}
    plan = []
    for each id in order
        ids = index.shelves[id]
        if ids <> invalid and ids.Count() > 0
            take = []
            n = ids.Count()
            if n > MAX_RESOLVE then n = MAX_RESOLVE
            for i = 0 to n - 1
                take.Push(ids[i])
                wanted[ids[i]] = true
            end for
            plan.Push({ id: id, ids: take })
        end if
    end for

    span.Mark()
    found = {}
    byDirector = {}
    topRated = []
    pdDay = []
    heroCand = []
    ' Public Domain Day: the films entering the US public domain THIS year, which
    ' is the current year minus 95. Derived from the index rather than curated,
    ' so it is right on the 1st of January without anyone editing a file.
    dt = CreateObject("roDateTime")
    pdYear = dt.GetYear() - 95
    for each row in index.items
        aid = row[0]
        ' A director shelf recommends, so it takes professionally-presented
        ' films only (Decision 097) and never a series spine.
        if row[5] = 1 and Left(fmt(aid), 7) <> "series:"
            if row.Count() > 11 and row[10] <> invalid and row[11] <> invalid
                ' The same 1,000-vote floor Browse uses: without it a single
                ' 10/10 rating outranks Citizen Kane (Decision 050).
                if Int(row[11]) >= 1000 then topRated.Push({ s: Int(row[10]), r: row })
            end if
            if row[2] <> invalid and Int(row[2]) = pdYear and pdDay.Count() < 20 then pdDay.Push(row)

            ' F24 — the hero pool. The owner, twice: it must come from "a huge
            ' selection of popular films with great artwork", and it must be
            ' limited to "films that can fill up that big space with correctly
            ' proportioned high-resolution images".
            '
            ' Both are one test, because of a fact measured in the catalog:
            ' EVERY backdrop we hold is a TMDb w1280 — 1280x720, natively
            ' 16:9. So requiring a real backdrop guarantees the proportion and
            ' the resolution together, and nothing else has to be inspected.
            ' A poster must never qualify: 188 of the 250 curated films with
            ' professional art have no backdrop, and stretching a 2:3 poster
            ' (or, worse, a 600px Commons still) across the band is exactly
            ' the "absolutely terrible" the owner saw.
            '
            ' The popularity floor is Browse's own (Decision 050): 1,000 votes
            ' so a single 10/10 cannot outrank Citizen Kane, plus a 6.0 rating.
            ' It leaves 843 films — The Seventh Seal, Metropolis, M, Double
            ' Indemnity, Nosferatu, The General — and it is why the hero no
            ' longer needs the curated-shelf allow-list to stay respectable.
            if row[7] <> invalid and row[7] <> ""
                if row.Count() > 11 and row[10] <> invalid and row[11] <> invalid
                    if Int(row[11]) >= 1000 and Int(row[10]) >= 60 then heroCand.Push(row)
                end if
            end if
        end if
        if row.Count() > 12 and row[12] <> invalid and row[12] <> "" and row[5] = 1
            if Left(fmt(aid), 7) <> "series:"
                d = fmt(row[12])
                if byDirector[d] = invalid then byDirector[d] = []
                if byDirector[d].Count() < 20 then byDirector[d].Push(row)
            end if
        end if
        if wanted[aid] <> invalid
            found[aid] = row
        end if
    end for
    scanMs = span.TotalMilliseconds()

    ' ---- build the ContentNode tree ----
    root = CreateObject("roSGNode", "ContentNode")
    heroPool = CreateObject("roSGNode", "ContentNode")
    m.heroAnim = 0
    m.extraRows = 0
    rowCount = 0

    for each p in plan
        kids = []
        for each aid in p.ids
            if kids.Count() >= MAX_PER_ROW then exit for
            r = found[aid]
            if r <> invalid
                ' ROKU-DESIGN §6.2 — Home shows professional posters only
                ' (Decision 097). A shelf that cannot field six hides rather
                ' than padding itself with frame grabs. The cap is applied to
                ' the QUALIFYING items, above, not to the ids beforehand.
                if r[5] = 1 and r[4] <> invalid and r[4] <> ""
                    kids.Push(r)
                end if
            end if
        end for
        ' F2 — "no shelf should display as less than a full row": 7 tiles are
        ' visible across the content column, so 7 is the floor.
        if kids.Count() >= 7
            rowNode = root.CreateChild("ContentNode")
            rowNode.title = titles[p.id]
            if subtitles[p.id] <> invalid then rowNode.SHORTDESCRIPTIONLINE2 = subtitles[p.id]
            for each r in kids
                it = rowNode.CreateChild("ContentNode")
                fillItem(it, r)
            end for
            rowCount = rowCount + 1
            ' The hero pool needs a real backdrop (never a 2:3 poster stretched
            ' into a wide box) AND a shelf worth leading with. Drawing from
            ' every shelf put a 1971 sexploitation still at the top of Home —
            ' technically eligible, and not what "a warm introduction to the
            ' films" means. The hero comes from the CURATED shelves only, the
            ' ones featured.json names, which is the editorial judgement this
            ' project already keeps in one place.

        end if
    end for

    ' Draw the hero from the WHOLE candidate set, not the front of it.
    ' Fisher-Yates over the candidates, then take the first twelve that pass
    ' the composition rules. Deduped by id: the curated shelves overlap, and
    ' a film on three of them was three times as likely to lead and could
    ' appear twice in the same row.
    n = heroCand.Count()
    if n > 1
        for i = n - 1 to 1 step -1
            j = Rnd(i + 1) - 1
            if j <> i
                tmp = heroCand[i] : heroCand[i] = heroCand[j] : heroCand[j] = tmp
            end if
        end for
    end if
    taken = {}
    for each r in heroCand
        if heroPool.GetChildCount() >= 12 then exit for
        id = fmt(r[0])
        if taken[id] <> invalid then continue for
        ' F1 — the owner: "at most one animated feature" in the hero.
        ' Cartoons are short, bright and plentiful in the curated shelves, so
        ' unchecked they took half the row.
        isAnim = (fmt(r[3]) = "animation")
        if isAnim and m.heroAnim >= 1 then continue for
        taken[id] = true
        h = heroPool.CreateChild("ContentNode")
        fillItem(h, r)
        if isAnim then m.heroAnim = m.heroAnim + 1
    end for
    print "AWHERO candidates="; heroCand.Count(); " chosen="; heroPool.GetChildCount()

    stats = {
        fetchMs: fetchMs, scanMs: scanMs, totalMs: 0,
        rows: rowCount, items: index.items.Count(),
        hero: heroPool.GetChildCount()
    }
    ' Top Rated and Public Domain Day, both from the same single pass.
    topRated.SortBy("s", "r")
    addRankedRow(root, "Top Rated", topRated, 20)
    addPlainRow(root, "Public Domain Day " + fmt(pdYear + 95), pdDay)

    ' Director shelves, from index column 12 (schema 10). Built in the SAME
    ' pass that already walked every row — a second walk to count directors
    ' would double the 41ms scan for nothing.
    addDirectorRows(root, index.items, byDirector)
    rowCount = rowCount + m.directorRowsAdded + m.extraRows

    ' Cross-shelf dedup, LAST, so it sees every row: no title appears twice
    ' anywhere on Home. tvOS guarantees this and it is the difference between a
    ' page of shelves and the same twenty films arranged six ways.
    dropped = dedupeRows(root)
    print "AWROKU dedup dropped="; dropped
    ' Re-check the floor against what SURVIVED. Every shelf tests its own size
    ' before dedup runs, and dedup then removes any film already shown above —
    ' so a row that qualified with seven could be left with two, and nothing
    ' looked again. That is the owner's "multiple shelves with only a couple
    ' or a few items", and it is why the F2 floor appeared not to hold: it
    ' held at the moment it was measured, on a set that had not been culled
    ' yet.
    thin = pruneThinRows(root, 7)
    if thin > 0 then print "AWROKU pruned "; thin; " shelf/shelves left thin by dedup"

    ' Two navigation rows at the END, the way tvOS orders them: films first,
    ' then the doors into the rest of the catalog. They carry no artwork and
    ' route to Browse rather than to a Detail screen.
    addTileRow(root, "Browse by Category", [
        { id: "browse:type:feature-film", label: "Feature Films", acc: "feature-film" },
        { id: "browse:type:tv-series",    label: "Classic TV",    acc: "tv-series" },
        { id: "browse:type:silent-film",  label: "Silent Era",    acc: "silent-film" },
        { id: "browse:type:animation",    label: "Animation",     acc: "animation" },
        { id: "browse:type:short-film",   label: "Short Films",   acc: "short-film" },
        { id: "browse:type:newsreel",     label: "Newsreels",     acc: "newsreel" },
        { id: "browse:type:documentary",  label: "Documentary",   acc: "documentary" },
        { id: "browse:type:ephemeral",    label: "Ephemeral",     acc: "ephemeral" }
    ])
    eras = []
    for d = 1900 to 1970 step 10
        eras.Push({ id: "browse:decade:" + fmt(d), label: "The " + fmt(d) + "s", acc: "feature-film" })
    end for
    addTileRow(root, "Browse by Era", eras)
    rowCount = rowCount + 2

    print "AWROKU home rows="; rowCount; " heroPool="; heroPool.GetChildCount(); " fetchMs="; fetchMs; " scanMs="; scanMs
    ' Every row by name, so a shelf-set comparison against the other
    ' platforms (F3) reads from the console instead of from a scroll of shots.
    names = ""
    for i = 0 to root.GetChildCount() - 1
        names = names + root.GetChild(i).title + " | "
    end for
    print "AWROWS "; names

    kinds = ""
    for i = 0 to heroPool.GetChildCount() - 1
        kinds = kinds + fmt(heroPool.GetChild(i).awType) + " "
    end for
    print "AWHERO pool kinds="; kinds
    m.top.hero = heroPool
    m.top.rows = root
    m.top.stats = stats
    m.top.status = "ready"
end sub

' ContentNode has a FIXED set of metadata fields. Assigning one it does not
' declare — BACKGROUNDIMAGEURL was the mistake here — silently does nothing:
' no error, and the reader gets `invalid`. Our own keys are added explicitly.
' A row of typographic navigation tiles: no artwork, a label, and an accent
' that carries the category's meaning (Decision 013).
' The directors with the deepest professionally-presented shelves. Six films
' is the floor: fewer than that is a coincidence of the catalog, not a body of
' work worth a shelf of its own.
' Walks the rows IN ORDER and removes any item already shown above. Order
' matters: the first shelf to claim a film keeps it, so a curated row wins over
' a generated one simply by being higher.
' Drop any shelf left below the floor. Walked BACKWARDS because removing a
' child shifts every index after it — forwards, this skips the row that moves
' into the slot just vacated.
function pruneThinRows(root as Object, floor as Integer) as Integer
    removed = 0
    i = root.GetChildCount() - 1
    while i >= 0
        row = root.GetChild(i)
        n = row.GetChildCount()
        isNav = false
        if n > 0 then isNav = (Left(fmt(row.GetChild(0).id), 7) = "browse:")
        ' Navigation tile rows are a fixed set of doors, not a shelf of films,
        ' and Continue Watching / Favorites are built elsewhere (MainScene)
        ' so the viewer's own two-item row is never at risk here.
        if not isNav and n < floor
            print "AWROWS thin: "; row.title; " ("; n; ")"
            root.RemoveChildIndex(i)
            removed = removed + 1
        end if
        i = i - 1
    end while
    return removed
end function

function dedupeRows(root as Object) as Integer
    seen = {}
    dropped = 0
    for i = 0 to root.GetChildCount() - 1
        row = root.GetChild(i)
        keep = []
        for j = 0 to row.GetChildCount() - 1
            it = row.GetChild(j)
            id = fmt(it.id)
            ' Navigation tiles are not films and must never be deduped away.
            if Left(id, 7) = "browse:"
                keep.Push(it)
            else if seen[id] = invalid
                seen[id] = true
                keep.Push(it)
            else
                dropped = dropped + 1
            end if
        end for
        if keep.Count() <> row.GetChildCount()
            row.RemoveChildrenIndex(row.GetChildCount(), 0)
            for each k in keep
                row.AppendChild(k)
            end for
        end if
    end for
    return dropped
end function

sub addRankedRow(root as Object, title as String, ranked as Object, limit as Integer)
    if ranked.Count() < 6 then return
    row = root.CreateChild("ContentNode")
    row.title = title
    n = 0
    for each e in ranked
        fillItem(row.CreateChild("ContentNode"), e.r)
        n = n + 1
        if n >= limit then exit for
    end for
    m.extraRows = m.extraRows + 1
end sub

sub addPlainRow(root as Object, title as String, rows as Object)
    if rows.Count() < 6 then return
    row = root.CreateChild("ContentNode")
    row.title = title
    for each r in rows
        fillItem(row.CreateChild("ContentNode"), r)
    end for
    m.extraRows = m.extraRows + 1
end sub

sub addDirectorRows(root as Object, items as Object, byDirector as Object)
    m.directorRowsAdded = 0
    if byDirector = invalid then return
    ranked = []
    for each name in byDirector
        n = byDirector[name].Count()
        if n >= 6 then ranked.Push({ n: n, name: name })
    end for
    ranked.SortBy("n", "r")
    made = 0
    for each e in ranked
        row = root.CreateChild("ContentNode")
        row.title = "Directed by " + e.name
        for each r in byDirector[e.name]
            n = row.CreateChild("ContentNode")
            fillItem(n, r)
        end for
        made = made + 1
        if made >= 3 then exit for
    end for
    m.directorRowsAdded = made
    print "AWROKU director shelves="; made; " of "; ranked.Count(); " eligible directors"
end sub

sub addTileRow(root as Object, title as String, tiles as Object)
    row = root.CreateChild("ContentNode")
    row.title = title
    for each t in tiles
        n = row.CreateChild("ContentNode")
        n.id = t.id
        n.title = t.label
        n.AddField("awBackdrop", "string", false)
        n.AddField("awType", "string", false)
        n.AddField("awRating", "integer", false)
        n.awType = t.acc
    end for
end sub

sub fillItem(n as Object, r as Object)
    ' Custom fields are DECLARED before they are assigned. A set to an
    ' undeclared field on a ContentNode is silently dropped, so the earlier
    ' order (assign awRating, then AddField) left every rating 0 — the star
    ' was absent on Home cards' Detail while present on service-query cards,
    ' because only this builder had the two lines the wrong way round.
    n.AddField("awBackdrop", "string", false)
    n.AddField("awType", "string", false)
    n.AddField("awBif", "boolean", false)
    n.AddField("awRating", "integer", false)
    n.id = r[0]
    n.title = StripHTML(fmt(r[1]))
    n.HDPOSTERURL = r[4]
    n.SHORTDESCRIPTIONLINE1 = metaLine(r)
    if r.Count() > 11 and r[10] <> invalid and r[11] <> invalid
        if r[11] >= 100 then n.awRating = r[10]
    end if
    if r.Count() > 15 then n.awBif = (r[15] = 1)
    if r[7] <> invalid then n.awBackdrop = r[7]
    if r[3] <> invalid then n.awType = r[3]
end sub

function metaLine(r as Object) as String
    ' Year, then up to two genres. The content KIND is the eyebrow above the
    ' title on every hero and Detail (§13.7), so repeating it here put the
    ' same word twice within sixty pixels; genres are what the eyebrow does
    ' not say. The year stays FIRST — Detail parses it from this string.
    out = ""
    if r[2] <> invalid then out = fmt(r[2])
    g = ""
    if r.Count() > 13 and r[13] <> invalid then g = fmt(r[13])
    added = 0
    if g <> ""
        for each part in g.Split("|")
            ' The index mixes CANONICAL genres (Drama, Comedy, Film Noir —
            ' Title-Case) with lowercase TMDb descriptor tags ("comedy drama",
            ' "romantic comedy", "comedy of remarriage"). The descriptors read
            ' as clutter beside the real genre and duplicate it; keep only the
            ' Title-Case canon, at most two.
            if part <> "" and added < 2
                c0 = Left(part, 1)
                if c0 = UCase(c0) and c0 <> LCase(c0)
                    if out <> "" then out = out + "  ·  "
                    out = out + part
                    added = added + 1
                end if
            end if
        end for
    end if
    if added = 0 and r[3] <> invalid and r[3] <> "" and r[2] = invalid
        out = prettyType(fmt(r[3]))
    end if
    return out
end function

function prettyType(t as String) as String
    if t = "feature-film" then return "Feature Film"
    if t = "silent-film" then return "Silent Era"
    if t = "short-film" then return "Short Film"
    if t = "tv-series" then return "Classic TV"
    if t = "tv-special" then return "Television"
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
