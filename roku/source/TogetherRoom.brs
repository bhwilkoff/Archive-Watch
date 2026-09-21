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

' Read a room. Returns invalid when there is none, so a caller can tell "no
' such room" from "the film is paused at zero".
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
    if msg.GetResponseCode() <> 200 then return invalid
    o = ParseJson(msg.GetString())
    if o = invalid or o.filmID = invalid then return invalid
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
function awRoomExpectedPosition(room as Object) as Float
    if room = invalid then return 0
    if room.paused = true then return room.position
    serverNow = awNowSeconds() + room.awOffset
    elapsed = serverNow - room.atServerTime
    if elapsed < 0 then elapsed = 0
    return room.position + elapsed * room.rate
end function

function awNowSeconds() as Float
    d = CreateObject("roDateTime")
    return d.AsSeconds() + d.GetMilliseconds() / 1000.0
end function
