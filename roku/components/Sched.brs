' Channel scheduling — the SAME algorithm the Apple, Android and web clients
' run (FNV-1a 64 + SplitMix64 + a 6 AM-local broadcast day), so a viewer who
' walks from the Apple TV to the Roku finds the same programme on the same
' channel at the same minute. Getting that wrong is not a cosmetic difference:
' "tune in" means nothing if every device runs its own listings.
'
' BrightScript has no dependable 64-bit integer arithmetic — `LongInteger`
' exists but its overflow behaviour on multiply is not specified, and these
' hashes are DEFINED by wraparound. So a u64 is carried here as four 16-bit
' limbs in an array, little-endian, and every operation is written out. It is
' more code than it looks like it should be; it is also the only way the
' numbers come out identical to the other four platforms.

function u64(l0 as Integer, l1 as Integer, l2 as Integer, l3 as Integer) as Object
    return [l0, l1, l2, l3]
end function

function uAdd(a as Object, b as Object) as Object
    out = [0, 0, 0, 0]
    carry = 0
    for i = 0 to 3
        s = a[i] + b[i] + carry
        out[i] = s and 65535
        carry = Int(s / 65536)
    end for
    return out
end function

' Schoolbook multiply, keeping only the low 64 bits. Each partial product is at
' most 65535*65535 (~4.29e9), which exceeds a 32-bit signed Integer — so the
' accumulator is a Double, whose 53-bit mantissa holds it exactly.
function uMul(a as Object, b as Object) as Object
    out = [0, 0, 0, 0]
    for i = 0 to 3
        if a[i] <> 0
            carry# = 0.0
            for j = 0 to 3 - i
                p# = a[i] * 1.0 * b[j] + out[i + j] + carry#
                out[i + j] = Int(p#) and 65535
                carry# = Int(p# / 65536.0)
            end for
        end if
    end for
    return out
end function

' BrightScript has no `xor` operator; (a OR b) - (a AND b) is exact for
' non-negative integers and is used throughout this project for the same
' reason (see DetailTask's shard hash).
function uXor(a as Object, b as Object) as Object
    out = [0, 0, 0, 0]
    for i = 0 to 3
        out[i] = (a[i] or b[i]) - (a[i] and b[i])
    end for
    return out
end function

function uShr(a as Object, n as Integer) as Object
    ' Whole-limb shift first, then the remainder — a single bit loop over 64
    ' positions would run per hash and this is called thousands of times.
    limbs = Int(n / 16)
    bits = n - limbs * 16
    t = [0, 0, 0, 0]
    for i = 0 to 3
        src = i + limbs
        if src <= 3 then t[i] = a[src]
    end for
    if bits = 0 then return t
    out = [0, 0, 0, 0]
    for i = 0 to 3
        v = Int(t[i] / (2 ^ bits))
        if i < 3
            hi = t[i + 1] and (2 ^ bits - 1)
            v = v + hi * (2 ^ (16 - bits))
        end if
        out[i] = Int(v) and 65535
    end for
    return out
end function

function uHex(a as Object) as String
    d = "0123456789abcdef"
    s = ""
    for i = 3 to 0 step -1
        v = a[i]
        for k = 3 to 0 step -1
            nib = Int(v / (16 ^ k)) and 15
            s = s + Mid(d, nib + 1, 1)
        end for
    end for
    return s
end function

' u64 modulo a small positive integer, limb by limb from the top.
function uMod(a as Object, m as Integer) as Integer
    if m <= 0 then return 0
    r = 0
    for i = 3 to 0 step -1
        r = (r * 65536 + a[i]) mod m
    end for
    return r
end function

function fnv1a64(s as String) as Object
    h = u64(&H2325, &H8422, &H9CE4, &HCBF2)      ' 0xcbf29ce484222325
    prime = u64(&H01B3, &H0000, &H0001, &H0000)  ' 0x100000001b3
    for i = 0 to Len(s) - 1
        b = Asc(Mid(s, i + 1, 1)) and 255
        h = uXor(h, [b, 0, 0, 0])
        h = uMul(h, prime)
    end for
    return h
end function

' Returns an object holding the generator state; call smNext(g) for each draw.
function smNew(seed as Object) as Object
    return { state: seed }
end function

function smNext(g as Object) as Object
    g.state = uAdd(g.state, u64(&H7C15, &H7F4A, &H79B9, &H9E37))
    z = g.state
    z = uMul(uXor(z, uShr(z, 30)), u64(&HE5B9, &H1CE4, &H476D, &HBF58))
    z = uMul(uXor(z, uShr(z, 27)), u64(&H11EB, &H3331, &H49BB, &H94D0))
    return uXor(z, uShr(z, 31))
end function

' The broadcast day starts at 6 AM LOCAL, which is why this uses ToLocalTime
' rather than the UTC roDateTime: a schedule anchored to UTC would start the
' viewer's day at whatever hour their offset happens to make it.
function dayAnchorParts() as Object
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    y = dt.GetYear() : mo = dt.GetMonth() : da = dt.GetDayOfMonth()
    if dt.GetHours() < 6
        ' Before 6 AM belongs to YESTERDAY's broadcast day.
        prev = CreateObject("roDateTime")
        prev.ToLocalTime()
        prev.FromSeconds(prev.AsSeconds() - 86400)
        ' FromSeconds resets to UTC semantics, so re-derive in local terms.
        da = da - 1
        if da < 1
            mo = mo - 1
            if mo < 1
                mo = 12 : y = y - 1
            end if
            da = daysIn(mo, y)
        end if
    end if
    return { year: y, month: mo, day: da }
end function

function daysIn(mo as Integer, y as Integer) as Integer
    if mo = 2
        if (y mod 4 = 0 and y mod 100 <> 0) or (y mod 400 = 0) then return 29
        return 28
    end if
    if mo = 4 or mo = 6 or mo = 9 or mo = 11 then return 30
    return 31
end function

' Seconds since the epoch for the current broadcast day's 6 AM local anchor.
function dayAnchorSeconds() as Integer
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    secsToday = dt.GetHours() * 3600 + dt.GetMinutes() * 60 + dt.GetSeconds()
    nowLocal = dt.AsSeconds()
    anchor = nowLocal - secsToday + 6 * 3600
    if nowLocal < anchor then anchor = anchor - 86400
    return anchor
end function

' Runtime rules, identical to the other clients: the pool's own runtime when it
' is credible, otherwise a per-type default. A 3-hour cap keeps one mis-tagged
' 12-hour upload from owning a whole channel.
function runtimeSec(prog as Object) as Integer
    run = prog[2]
    if run <> invalid and run > 120
        if run > 10800 then return 10800
        return Int(run)
    end if
    t = LCase(fmt(prog[4]))
    if t = "feature-film" or t = "silent-film" then return 5400
    if t = "tv-special" or t = "documentary" then return 3000
    if t = "short-film" or t = "animation" or t = "newsreel" or t = "ephemeral" then return 720
    return 3600
end function

' [{prog, startS, endS}] from the day's anchor through now + 26h.
function buildSchedule(channelID as String, programs as Object, nowS as Integer) as Object
    slots = []
    if programs = invalid or programs.Count() = 0 then return slots
    a = dayAnchorParts()
    key = channelID + fmt(a.year) + "-" + fmt(a.month) + "-" + fmt(a.day)
    g = smNew(fnv1a64(key))

    pool = []
    for each p in programs
        pool.Push(p)
    end for
    ' Fisher-Yates, drawing exactly as the other clients do so the order matches.
    for i = pool.Count() - 1 to 1 step -1
        j = uMod(smNext(g), i + 1)
        tmp = pool[i] : pool[i] = pool[j] : pool[j] = tmp
    end for

    cursor = dayAnchorSeconds()
    until_ = nowS + 26 * 3600
    i = 0
    while cursor < until_ and slots.Count() < 2000
        prog = pool[i mod pool.Count()]
        endS = cursor + runtimeSec(prog)
        slots.Push({ prog: prog, startS: cursor, endS: endS })
        cursor = endS + 120        ' the same 2-minute inter-programme buffer
        i = i + 1
    end while
    return slots
end function

' Known-answer test against values computed independently in Python (and
' matching watch.js's BigInt implementation). There is no offline BrightScript
' runner, so this is the only place the limb arithmetic can be PROVEN right —
' it costs one log line per channel load and it is worth every character.
function SchedSelfTest() as String
    cases = [
        { key: "drama2026-9-4",
          fnv: "b7047bdb76357985", r1: "c0f76137e662e55c", r2: "315b72a0853b4404" },
        { key: "comedy2026-9-4",
          fnv: "9b699c23e1754373", r1: "5bf9eca6c5f187c3", r2: "3655068303013af7" }
    ]
    bad = 0
    for each c in cases
        h = fnv1a64(c.key)
        if uHex(h) <> c.fnv then bad = bad + 1 : print "SCHED fnv MISMATCH "; c.key; " got "; uHex(h); " want "; c.fnv
        g = smNew(h)
        a1 = uHex(smNext(g))
        a2 = uHex(smNext(g))
        if a1 <> c.r1 then bad = bad + 1 : print "SCHED r1 MISMATCH "; c.key; " got "; a1; " want "; c.r1
        if a2 <> c.r2 then bad = bad + 1 : print "SCHED r2 MISMATCH "; c.key; " got "; a2; " want "; c.r2
    end for
    if bad = 0 then return "SCHED selftest PASS (6/6 vectors)"
    return "SCHED selftest FAIL (" + fmt(bad) + " mismatches) — this device's listings will NOT match the other platforms"
end function

' Local wall-clock seconds — the SAME clock buildSchedule anchors to, so a slot
' can be compared to "now" without either side re-applying a timezone offset.
function nowLocalSeconds() as Integer
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    return dt.AsSeconds()
end function

function clockLabel(localSeconds as Integer) as String
    s = localSeconds mod 86400
    if s < 0 then s = s + 86400
    h = Int(s / 3600)
    mi = Int((s - h * 3600) / 60)
    ap = "AM"
    if h >= 12 then ap = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    mm = fmt(mi)
    if mi < 10 then mm = "0" + mm
    return fmt(h12) + ":" + mm + " " + ap
end function
