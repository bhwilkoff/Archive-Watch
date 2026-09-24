' Watch Together rooms on Roku — SHAREPLAY §11.
'
' THE FIFTH IMPLEMENTATION OF ONE RULE (Swift, the Worker's JavaScript,
' Kotlin, the browser, and now BrightScript). A code is read aloud on a call
' and typed on another device, so if this one disagrees about what a heard
' "oh" means, a viewer who types exactly what they heard reaches a different
' room and nothing says why. `tools/test_room_alphabet_parity.py` pins the
' ALPHABET and the LENGTH across all five — it cannot execute BrightScript,
' so it guards the constant that would actually drift rather than pretending
' to test the logic.
'
' Decision 119 is why a CODE is the right shape here at all: a television
' hands over a link as a code, because typing a URL with a remote is
' miserable and four characters is not.

function awRoomAlphabet() as String
    ' Crockford Base32: no I, L, O or U — I and L confusable with 1, O with 0,
    ' and U dropped so a random code cannot spell something unfortunate. 0 and
    ' 1 REMAIN, which is what makes the mapping below possible at all.
    return "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
end function

function awRoomCodeLength() as Integer
    return 4
end function

' What a person typed, in the one canonical form — or "" if it is not a code.
'
' Forgiving on purpose, because the input arrives BY EAR: case is ignored,
' spaces and dashes are ignored (people group what they read aloud), and the
' confusable glyphs are MAPPED rather than refused. Somebody who hears "oh"
' and types O meant zero, and being told "invalid code" for that is a bad way
' to start a film.
function awRoomNormalize(typed as Dynamic) as String
    if typed = invalid then return ""
    s = UCase(fmt(typed))
    alphabet = awRoomAlphabet()
    out = ""
    for i = 0 to Len(s) - 1
        ch = Mid(s, i + 1, 1)
        if ch = " " or ch = "-" or ch = "_"
            ' grouping, not content
        else if ch = "I" or ch = "L"
            out = out + "1"
        else if ch = "O"
            out = out + "0"
        else if ch = "U"
            return ""
        else if Instr(1, alphabet, ch) > 0
            out = out + ch
        else
            return ""
        end if
    end for
    if Len(out) <> awRoomCodeLength() then return ""
    return out
end function

function awRoomOrigin() as String
    ' NOT archivewatch.org — that host is GitHub Pages. The Worker answers at
    ' its own origin, the one the privacy counter posts to.
    return "https://archivewatch-pulse.benwilkoff.workers.dev"
end function

'
' Read a room. Returns the room, `{ ended: true }` when the room is GONE (404
' or 410 — the host ended it), or invalid for a poll that merely FAILED. The
' two used to be one `invalid`, so a single dropped request told a Roku guest
' "The room has ended." and stopped following a room that was still running.
function awRoomRead(code as String) as Object
    if code = "" then return invalid
    port = CreateObject("roMessagePort")
    x = CreateObject("roUrlTransfer")
    x.SetMessagePort(port)
    x.SetUrl(awRoomOrigin() + "/together/" + code)
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.EnableEncodings(true)
    sentAt = awNowSeconds()
    if not x.AsyncGetToString() then return invalid
    msg = wait(8000, port)
    if type(msg) <> "roUrlEvent" then
        x.AsyncCancel()
        return invalid
    end if
    receivedAt = awNowSeconds()
    status = msg.GetResponseCode()
    if status = 404 or status = 410 then return { ended: true }
    if status <> 200 then return invalid
    body = msg.GetString()
    o = ParseJson(body)
    if o = invalid or o.filmID = invalid then return invalid
    ' The two epoch times are ~1.8e9 s. Whatever numeric type ParseJson picks,
    ' a Float holds that in 128-second steps, so they are read from the TEXT
    ' into Doubles here rather than trusted to the parser.
    o.serverTime = awJsonSeconds(body, "serverTime")
    o.atServerTime = awJsonSeconds(body, "atServerTime")
    ' The state AND the server's clock in one response (§11.6), so the round
    ' trip measured around this very request is the clock sample — the poll IS
    ' the sync, and a second endpoint would double the traffic for nothing.
    o.awSentAt = sentAt
    o.awReceivedAt = receivedAt
    ' Cristian's algorithm; the error bound is half the round trip.
    o.awOffset = o.serverTime - (sentAt + receivedAt) / 2
    o.awError = (receivedAt - sentAt) / 2
    return o
end function

' Where the film should be, on this box's clock. A PAUSED film does not
' advance — the thing an elapsed-time formula gets wrong the moment it forgets
' to ask.
function awRoomExpectedPosition(room as Object) as Double
    if room = invalid then return 0
    if room.paused = true then return room.position
    serverNow = awNowSeconds() + room.awOffset
    elapsed = serverNow - room.atServerTime
    if elapsed < 0 then elapsed = 0
    return room.position + elapsed * room.rate
end function

' A DOUBLE. This was `as Float`, and a 32-bit float at today's epoch
' (~1.8e9 s) resolves in 128-second steps — every elapsed-time and clock
' computation built on it was off by up to two minutes (launch audit C).
function awNowSeconds() as Double
    d = CreateObject("roDateTime")
    return CDbl(d.AsSeconds()) + CDbl(d.GetMilliseconds()) / 1000#
end function

' A seconds value read from the JSON TEXT as a Double: "key":1790000000.123
' -> 1790000000.123#. The integer and fraction are parsed separately, because
' Val() on the whole string may round through a Float.
function awJsonSeconds(body as String, key as String) as Double
    rx = CreateObject("roRegex", Chr(34) + key + Chr(34) + "\s*:\s*(\d+)(?:\.(\d+))?", "")
    m = rx.Match(body)
    if m.Count() < 2 then return 0#
    ' DIGIT BY DIGIT into a Double. Val() returns a single-precision Float,
    ' which resolves today's epoch in 128-second steps — so atServerTime and
    ' the clock offset were wrong, elapsed time clamped to zero, and a guest
    ' seeked back to the host's last published position on every poll
    ' (Streaming Stick 4K, 2026-09-24: seeks at 910, 921, 931, 942 ...).
    whole = 0#
    digits = m[1]
    for i = 1 to Len(digits)
        whole = whole * 10# + CDbl(Asc(Mid(digits, i, 1)) - 48)
    end for
    frac = 0#
    if m.Count() > 2 and m[2] <> invalid and m[2] <> ""
        fd = Left(m[2], 6)
        frac = CDbl(Val(fd)) / (10# ^ Len(fd))
    end if
    return whole + frac
end function

' "I'm here", so the host's count includes a Roku guest. Best effort: a
' missed ping only makes the count lag. The token is fresh per join and tied
' to nothing (owner, 2026-09-23).
sub awRoomSayHere(code as String, token as String)
    if code = "" then return
    x = CreateObject("roUrlTransfer")
    x.SetUrl(awRoomOrigin() + "/together/" + code + "/here")
    x.SetCertificatesFile("common:/certs/ca-bundle.crt")
    x.InitClientCertificates()
    x.AddHeader("content-type", "application/json")
    x.PostFromString(FormatJson({ token: token }))
end sub
