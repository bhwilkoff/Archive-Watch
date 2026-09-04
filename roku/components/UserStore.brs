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
            rows.Push({ id: parts[0], posn: Int(Val(parts[1])), dur: Int(Val(parts[2])) })
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
sub awSetProgress(id as String, posn as Integer, dur as Integer)
    rows = awProgressRows()
    out = [{ id: id, posn: posn, dur: dur }]
    for each r in rows
        if r.id <> id and out.Count() < awMaxProgress() then out.Push(r)
    end for
    lines = []
    for each r in out
        lines.Push(r.id + "|" + fmt(r.posn) + "|" + fmt(r.dur))
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
    return Len(awReadKey("fav")) + Len(awReadKey("prog"))
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
