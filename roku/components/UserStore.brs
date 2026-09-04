' Local user state, in the ONLY durable storage a Roku channel has.
'
' ROKU-DESIGN §7.2: roRegistrySection is capped at 32 KB for the whole app and
' `cachefs:` is evictable, so there is no file store to fall back on. That cap
' is why Library is capacity-bounded by design and says so, rather than
' truncating silently — and why watch progress is the thing we would publish to
' Roku's own Continue Watching rather than hoard here.
'
' Encoding is deliberately terse: ids are ~25 bytes and the budget is small.
'   favorites  "id\nid\nid"
'   progress   "id|posn|dur\nid|posn|dur"   newest first
' NOTE: BrightScript has no `const`. That keyword is BrighterScript, and using
' it here produced four bare "Syntax Error" lines plus a cascading error in the
' next function — none of which name the keyword.
function awMaxFavorites() as Integer : return 200 : end function
function awMaxProgress() as Integer : return 200 : end function

function awSection() as Object
    return CreateObject("roRegistrySection", "archivewatch")
end function

function awReadKey(key as String) as String
    sec = awSection()
    if not sec.Exists(key) then return ""
    v = sec.Read(key)
    if v = invalid then return ""
    return v
end function

sub awWriteKey(key as String, value as String)
    sec = awSection()
    sec.Write(key, value)
    sec.Flush()
end sub

function awSplit(s as String, sep as String) as Object
    out = []
    if s = "" then return out
    ' BrightScript's Split is on roString; calling it on a return value is the
    ' error this platform keeps handing us, so the local comes first.
    str = s
    parts = str.Split(sep)
    for each p in parts
        if p <> "" then out.Push(p)
    end for
    return out
end function

' ---------------------------------------------------------------- favorites

function awFavorites() as Object
    return awSplit(awReadKey("fav"), Chr(10))
end function

function awIsFavorite(id as String) as Boolean
    for each f in awFavorites()
        if f = id then return true
    end for
    return false
end function

' Returns TRUE when the item is now a favorite. Returns invalid when the
' library is full, so the caller can say so — §7.2 forbids silent truncation.
function awToggleFavorite(id as String) as Dynamic
    favs = awFavorites()
    out = []
    found = false
    for each f in favs
        if f = id then found = true else out.Push(f)
    end for
    if not found
        if favs.Count() >= awMaxFavorites() then return invalid
        out.Unshift(id)
    end if
    awWriteKey("fav", awJoin(out, Chr(10)))
    return (not found)
end function

function awJoin(items as Object, sep as String) as String
    out = ""
    for i = 0 to items.Count() - 1
        if i > 0 then out = out + sep
        out = out + items[i]
    end for
    return out
end function

' ----------------------------------------------------------------- progress

function awProgressRows() as Object
    rows = []
    for each line in awSplit(awReadKey("prog"), Chr(10))
        parts = awSplit(line, "|")
        if parts.Count() >= 3
            ' A fourth field, added later, names the SERIES an episode belongs
            ' to. Older rows have three fields and parse exactly as before.
            own = ""
            if parts.Count() >= 4 then own = parts[3]
            rows.Push({ id: parts[0], posn: Int(Val(parts[1])), dur: Int(Val(parts[2])), owner: own })
        end if
    end for
    return rows
end function

function awGetProgress(id as String) as Integer
    for each r in awProgressRows()
        if r.id = id then return r.posn
    end for
    return 0
end function

function awGetDuration(id as String) as Integer
    for each r in awProgressRows()
        if r.id = id then return r.dur
    end for
    return 0
end function

' Newest first, so the oldest row is the one evicted when the budget runs out.
sub awSetProgress(id as String, posn as Integer, dur as Integer, owner = "" as String)
    rows = awProgressRows()
    ' An episode carries no poster of its own in the web index — measured:
    ' 26Men-TheRecruit and adam-12.-s-01 both have an EMPTY poster field, so
    ' Continue Watching drew two grey title cards where every other platform
    ' shows the series art. The series slug is remembered here, at ~20 bytes
    ' a row, and Home borrows that series' poster. Written once at the start
    ' of playback; the 5-second bookmark ticks must not erase it.
    own = owner
    if own = ""
        for each r in rows
            if r.id = id and r.owner <> "" then own = r.owner
        end for
    end if
    out = [{ id: id, posn: posn, dur: dur, owner: own }]
    for each r in rows
        if r.id <> id and out.Count() < awMaxProgress() then out.Push(r)
    end for
    lines = []
    for each r in out
        lines.Push(r.id + "|" + fmt(r.posn) + "|" + fmt(r.dur) + "|" + r.owner)
    end for
    awWriteKey("prog", awJoin(lines, Chr(10)))
end sub

' Resumable window matches every other platform: past 10s and short of 95%.
function awIsResumable(posn as Integer, dur as Integer) as Boolean
    if dur <= 0 then return false
    if posn <= 10 then return false
    return posn < (dur * 95) / 100
end function

function awContinueWatching() as Object
    out = []
    for each r in awProgressRows()
        if awIsResumable(r.posn, r.dur) then out.Push(r)
    end for
    return out
end function

' Returns a SET (associative array), not a list: every caller asks "is this id
' watched", and a linear scan per tile across 600 shelf items is work the
' render thread cannot afford.
function awWatchedIds() as Object
    out = {}
    for each r in awProgressRows()
        if r.dur > 0 and r.posn >= (r.dur * 95) / 100 then out[r.id] = true
    end for
    return out
end function

' How full the 32 KB budget is, so Library can tell the truth about it.
function awStorageUsed() as Integer
    return Len(awReadKey("fav")) + Len(awReadKey("prog")) + Len(awReadKey("pl")) + Len(awReadKey("uch"))
end function

' ---- settings -------------------------------------------------------------
' Booleans live as "1"/"0" so a missing key reads as the empty string and the
' caller decides the default — there is no tri-state to get wrong later.
function awGetSetting(key as String, dflt as Boolean) as Boolean
    v = awReadKey("s_" + key)
    if v = "" then return dflt
    return (v = "1")
end function

sub awSetSetting(key as String, on as Boolean)
    if on
        awWriteKey("s_" + key, "1")
    else
        awWriteKey("s_" + key, "0")
    end if
end sub

sub awClearProgress()
    awWriteKey("progress", "")
end sub

' Mark a film watched WITHOUT playing it, and un-mark it. Watched is expressed
' as a progress row at >=95% (awIsResumable's own threshold), so the Library,
' the hide-watched filter and the resume label all agree by construction rather
' than by a second flag that could drift out of step with them.
sub awMarkWatched(id as String, dur as Integer)
    d = dur
    if d <= 0 then d = 3600
    awSetProgress(id, d, d)
end sub

sub awClearProgressFor(id as String)
    rows = awProgressRows()
    out = []
    for each r in rows
        if r.id <> id then out.Push(r.id + "|" + fmt(r.posn) + "|" + fmt(r.dur))
    end for
    awWriteKey("prog", awJoin(out, Chr(10)))
end sub

function awIsWatched(id as String) as Boolean
    posn = awGetProgress(id)
    dur = awGetDuration(id)
    if dur <= 0 then return false
    return posn >= (dur * 95) / 100
end function

' ---- playlists ------------------------------------------------------------
'
' One registry key, one line per playlist: id <TAB> name <TAB> id,id,id
' Tab is the field separator because a film title can contain almost anything
' else and a viewer naming a playlist can type almost anything at all — the
' name is sanitised on the way in rather than trusted on the way out.
function awMaxPlaylists() as Integer : return 20 : end function
function awMaxPlaylistItems() as Integer : return 100 : end function

function awSanitizeName(s as String) as String
    out = ""
    for i = 0 to Len(s) - 1
        c = Mid(s, i + 1, 1)
        if c <> Chr(9) and c <> Chr(10) and c <> Chr(13) then out = out + c
    end for
    if Len(out) > 40 then out = Left(out, 40)
    return out
end function

function awPlaylists() as Object
    out = []
    for each line in awSplit(awReadKey("pl"), Chr(10))
        if line <> ""
            f = awSplit(line, Chr(9))
            if f.Count() >= 2
                ids = []
                if f.Count() >= 3 and f[2] <> ""
                    for each a in awSplit(f[2], ",")
                        if a <> "" then ids.Push(a)
                    end for
                end if
                out.Push({ id: f[0], name: f[1], ids: ids })
            end if
        end if
    end for
    return out
end function

sub awWritePlaylists(lists as Object)
    rows = []
    for each p in lists
        rows.Push(p.id + Chr(9) + p.name + Chr(9) + awJoin(p.ids, ","))
    end for
    awWriteKey("pl", awJoin(rows, Chr(10)))
end sub

' Returns the new playlist id, or invalid when the cap is reached — the caller
' must be able to SAY the library is full rather than silently doing nothing.
function awCreatePlaylist(name as String) as Dynamic
    lists = awPlaylists()
    if lists.Count() >= awMaxPlaylists() then return invalid
    clean = awSanitizeName(name)
    if clean = "" then clean = "Playlist " + fmt(lists.Count() + 1)
    ' A monotonic id from the clock: the registry has no autoincrement and two
    ' playlists sharing an id would silently merge.
    id = "p" + fmt(nowSecondsStore())
    for each p in lists
        if p.id = id then id = id + "x"
    end for
    lists.Push({ id: id, name: clean, ids: [] })
    awWritePlaylists(lists)
    return id
end function

function nowSecondsStore() as Integer
    dt = CreateObject("roDateTime")
    return dt.AsSeconds()
end function

function awAddToPlaylist(plID as String, aid as String) as Boolean
    lists = awPlaylists()
    for each p in lists
        if p.id = plID
            for each a in p.ids
                if a = aid then return true      ' already there; not an error
            end for
            if p.ids.Count() >= awMaxPlaylistItems() then return false
            p.ids.Push(aid)
            awWritePlaylists(lists)
            return true
        end if
    end for
    return false
end function

sub awRemoveFromPlaylist(plID as String, aid as String)
    lists = awPlaylists()
    for each p in lists
        if p.id = plID
            keep = []
            for each a in p.ids
                if a <> aid then keep.Push(a)
            end for
            p.ids = keep
        end if
    end for
    awWritePlaylists(lists)
end sub

sub awDeletePlaylist(plID as String)
    keep = []
    for each p in awPlaylists()
        if p.id <> plID then keep.Push(p)
    end for
    awWritePlaylists(keep)
end sub

' ---- self-test ------------------------------------------------------------
'
' A round-trip over the registry, triggered by the deep link
' `contentId=selftest:store`. There is no offline BrightScript runner and the
' registry cannot be read by any external tool, so this is the ONLY way to
' prove the persistence layer from outside the app — the same reason tvOS
' carries FunctionalAudit and Sched carries its known-answer vectors.
'
' It writes to REAL keys and restores what it found, because a test against a
' different key proves the test works and nothing else.
function awStoreSelfTest() as String
    savedFav = awReadKey("fav")
    savedProg = awReadKey("prog")
    savedPl = awReadKey("pl")
    fails = []

    awWriteKey("fav", "")
    awWriteKey("prog", "")
    awWriteKey("pl", "")

    if awToggleFavorite("aw_test_a") <> true then fails.Push("toggleFavorite did not add")
    if not awIsFavorite("aw_test_a") then fails.Push("favorite did not persist")
    if awToggleFavorite("aw_test_a") <> false then fails.Push("toggleFavorite did not remove")
    if awIsFavorite("aw_test_a") then fails.Push("favorite survived removal")

    awSetProgress("aw_test_b", 300, 1200)
    if awGetProgress("aw_test_b") <> 300 then fails.Push("progress position wrong")
    if awGetDuration("aw_test_b") <> 1200 then fails.Push("progress duration wrong")
    if awIsWatched("aw_test_b") then fails.Push("25% counted as watched")
    awMarkWatched("aw_test_b", 1200)
    if not awIsWatched("aw_test_b") then fails.Push("markWatched did not stick")
    awClearProgressFor("aw_test_b")
    if awGetProgress("aw_test_b") <> 0 then fails.Push("clearProgressFor left a row")

    id = awCreatePlaylist("Test " + Chr(9) + "List")
    if id = invalid
        fails.Push("createPlaylist refused")
    else
        lists = awPlaylists()
        if lists.Count() <> 1 then fails.Push("expected 1 playlist, got " + fmt(lists.Count()))
        ' The tab MUST be stripped: it is the field separator, and a name
        ' carrying one would split the record and corrupt every playlist after
        ' it in the file.
        if Instr(1, lists[0].name, Chr(9)) > 0 then fails.Push("tab survived sanitize — record separator corrupted")
        if not awAddToPlaylist(id, "aw_test_c") then fails.Push("addToPlaylist failed")
        if not awAddToPlaylist(id, "aw_test_c") then fails.Push("re-adding the same id should be a no-op, not a failure")
        if awPlaylists()[0].ids.Count() <> 1 then fails.Push("duplicate id was stored twice")
        awAddToPlaylist(id, "aw_test_d")
        if awPlaylists()[0].ids.Count() <> 2 then fails.Push("second id not stored")
        awRemoveFromPlaylist(id, "aw_test_c")
        if awPlaylists()[0].ids.Count() <> 1 then fails.Push("removeFromPlaylist did not remove")
        awDeletePlaylist(id)
        if awPlaylists().Count() <> 0 then fails.Push("deletePlaylist did not delete")
    end if

    savedUch = awReadKey("uch")
    awWriteKey("uch", "")
    uid = awCreateUserChannel("Test " + Chr(9) + "Channel", "silent-film", 1920)
    if uid = invalid
        fails.Push("createUserChannel refused")
    else
        ch = awUserChannels()
        if ch.Count() <> 1 then fails.Push("expected 1 user channel, got " + fmt(ch.Count()))
        if Instr(1, ch[0].name, Chr(9)) > 0 then fails.Push("tab survived sanitize in a channel name")
        if ch[0].type <> "silent-film" then fails.Push("channel type not stored")
        if ch[0].decade <> 1920 then fails.Push("channel decade not stored")
        awDeleteUserChannel(uid)
        if awUserChannels().Count() <> 0 then fails.Push("deleteUserChannel did not delete")
    end if
    awWriteKey("uch", savedUch)

    awSetSetting("aw_test_flag", true)
    if not awGetSetting("aw_test_flag", false) then fails.Push("setting did not persist")
    awSetSetting("aw_test_flag", false)
    if awGetSetting("aw_test_flag", true) then fails.Push("setting false read back as default")

    awWriteKey("fav", savedFav)
    awWriteKey("prog", savedProg)
    awWriteKey("pl", savedPl)

    if fails.Count() = 0 then return "AWPL selftest PASS (23 assertions)"
    out = "AWPL selftest FAIL:"
    for each f in fails
        out = out + Chr(10) + "   - " + f
    end for
    return out
end function

' ---- user channels --------------------------------------------------------
'
' A channel the viewer defined: a name plus the two facets the web index can
' actually answer (content type and decade). One line each, tab separated, in
' the same registry the rest of this file uses.
function awMaxUserChannels() as Integer : return 10 : end function

function awUserChannels() as Object
    out = []
    for each line in awSplit(awReadKey("uch"), Chr(10))
        if line <> ""
            f = awSplit(line, Chr(9))
            if f.Count() >= 4
                out.Push({ id: f[0], name: f[1], type: f[2], decade: Int(Val(f[3])) })
            end if
        end if
    end for
    return out
end function

function awCreateUserChannel(name as String, chType as String, decade as Integer) as Dynamic
    lists = awUserChannels()
    if lists.Count() >= awMaxUserChannels() then return invalid
    id = "u" + fmt(nowSecondsStore())
    for each c in lists
        if c.id = id then id = id + "x"
    end for
    lists.Push({ id: id, name: awSanitizeName(name), type: chType, decade: decade })
    rows = []
    for each c in lists
        rows.Push(c.id + Chr(9) + c.name + Chr(9) + c.type + Chr(9) + fmt(c.decade))
    end for
    awWriteKey("uch", awJoin(rows, Chr(10)))
    return id
end function

sub awDeleteUserChannel(chID as String)
    rows = []
    for each c in awUserChannels()
        if c.id <> chID
            rows.Push(c.id + Chr(9) + c.name + Chr(9) + c.type + Chr(9) + fmt(c.decade))
        end if
    end for
    awWriteKey("uch", awJoin(rows, Chr(10)))
end sub
