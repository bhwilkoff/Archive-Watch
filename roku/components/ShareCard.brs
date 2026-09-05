sub init()
    m.t = Theme()
    m.dim = m.top.FindNode("dim")
    m.plate = m.top.FindNode("plate")
    m.head = m.top.FindNode("head")
    m.code = m.top.FindNode("code")
    m.url = m.top.FindNode("url")
    m.title = m.top.FindNode("title")

    m.dim.width = 1920 : m.dim.height = 1080 : m.dim.color = "0x000000BB"
    pw = 720 : ph = 690
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
    m.code.translation = [px + Int((pw - 392) / 2), py + 150]
    m.code.width = 392 : m.code.height = 392
    m.code.loadDisplayMode = "scaleToFit"

    m.url.font = m.t.uBody : m.url.color = m.t.textPri
    m.url.translation = [px + 48, py + 570] : m.url.width = pw - 96
    m.url.maxLines = 2 : m.url.wrap = true
    m.url.horizAlign = "center"
end sub

sub open(payload as Object)
    id = fmt(payload.id)
    link = "https://archivewatch.org/item/" + id
    m.title.text = fmt(payload.title)
    m.url.text = "archivewatch.org/item/" + id
    path = AWQRPng(link, 8)
    if path = "" then path = AWQRPng("https://archivewatch.org", 8)
    m.code.uri = path
    m.top.visible = true
    m.top.setFocus(true)
    print "AWSHARE open "; link
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
