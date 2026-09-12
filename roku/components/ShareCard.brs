sub init()
    m.t = Theme()
    m.dim = m.top.FindNode("dim")
    m.plate = m.top.FindNode("plate")
    m.head = m.top.FindNode("head")
    m.code = m.top.FindNode("code")
    m.url = m.top.FindNode("url")
    m.title = m.top.FindNode("title")

    m.dim.width = 1920 : m.dim.height = 1080 : m.dim.color = "0x000000BB"
    pw = 720 : ph = 820
    px = Int((1920 - pw) / 2) : py = Int((1080 - ph) / 2)
    m.plate.translation = [px, py]
    m.plate.width = pw : m.plate.height = ph
    m.plate.color = "0x121216FF"
    m.frame = AWFrameBuild(m.top.FindNode("frame"))
    AWFramePlace(m.frame, m.plate, false)

    m.head.font = m.t.uScreen : m.head.color = m.t.textPri
    m.head.translation = [px + 48, py + 42]
    m.head.text = "Watch it anywhere"

    m.title.font = m.t.uMeta : m.title.color = m.t.textSec
    m.title.translation = [px + 48, py + 105] : m.title.width = pw - 96
    m.title.maxLines = 1 : m.title.ellipsizeOnBoundary = true

    ' The code sits on a light field of its own: a QR needs its quiet zone
    ' to be the same white as its light modules.
    '
    ' The box is AWQRBox() and the encoder derives its pixel scale from it, so
    ' the PNG arrives at very close to its display size and Roku's bilinear
    ' scaler has almost nothing to do. A QR that is resampled is a QR with soft
    ' module edges, and a big one is exactly where that starts to cost reads.
    ' NOT `box` — Box() is a BrightScript builtin (it boxes an intrinsic), so a
    ' local of that name is a compile error, in the same family as `rem` being
    ' the comment keyword. It fails at COMPILE time, which is the good case.
    qrBox = AWQRBox()
    m.code.translation = [px + Int((pw - qrBox) / 2), py + 150]
    m.code.width = qrBox : m.code.height = qrBox
    m.code.loadDisplayMode = "scaleToFit"

    m.url.font = m.t.uBody : m.url.color = m.t.textPri
    m.url.translation = [px + 48, py + 700] : m.url.width = pw - 96
    m.url.maxLines = 2 : m.url.wrap = true
    m.url.horizAlign = "center"
end sub

sub open(payload as Object)
    ' Two callers now. Detail passes an item id; the library passes a whole
    ' `link` because a shared PLAYLIST is not addressed by an id at all — the
    ' list travels inside the URL (docs/PLAYLIST-SHARING.md), so there is
    ' nothing here to rebuild it from.
    link = fmt(payload.link)
    if link <> ""
        label = link
        if Left(label, 8) = "https://" then label = Mid(label, 9)
    else
        id = fmt(payload.id)
        ' A series id carries a "series:" prefix and lives at a DIFFERENT share
        ' path on every other platform. Detail only ever holds a film today, so
        ' this is defensive — but the wrong URL would print into a QR code, where
        ' nobody can see it is wrong until they scan it.
        path = "item/" + id
        if Left(id, 7) = "series:" then path = "series/" + Mid(id, 8)
        link = "https://archivewatch.org/" + path
        label = "archivewatch.org/" + path
    end if
    m.title.text = fmt(payload.title)
    m.head.text = fmt(payload.head)
    if m.head.text = "" then m.head.text = "Watch it anywhere"

    ' A playlist link is ~1,700 characters of base64 — unreadable on a TV and
    ' impossible to key in with a remote, so past the point where a viewer
    ' could type it the card says what the code is for instead of printing it.
    ' The web-TV sheet draws the same conclusion at the same threshold.
    if Len(label) > 120 then label = "This link is too long to type — the code carries it."
    m.url.text = label

    ' The encoder refuses anything past a version-40 payload. A card with an
    ' empty frame where a code belongs tells the viewer nothing, so a refusal
    ' falls back to the site rather than to blank.
    png = AWQRPng(link, 0)
    if png = ""
        png = AWQRPng("https://archivewatch.org", 0)
        m.url.text = "Too long to put in a code — open archivewatch.org"
    end if
    m.code.uri = png
    m.top.visible = true
    m.top.setFocus(true)
    print "AWSHARE open len="; Len(link); " "; link
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.visible then return false
    if key = "back" or key = "OK"
        m.top.visible = false
        m.top.closed = true
        return true
    end if
    return true
end function
