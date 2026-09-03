sub init()
    m.t = Theme()
    m.wash = m.top.FindNode("wash")
    m.scrim = m.top.FindNode("scrim")
    m.art = m.top.FindNode("art")
    m.title = m.top.FindNode("title")
    m.aka = m.top.FindNode("aka")
    m.meta = m.top.FindNode("meta")
    m.syn = m.top.FindNode("synopsis")
    m.chip = m.top.FindNode("chip")
    m.chipText = m.top.FindNode("chipText")
    m.btns = m.top.FindNode("buttons")

    m.wash.width = 1920 : m.wash.height = 1080
    m.wash.translation = [-150, 0]
    m.wash.loadDisplayMode = "scaleToZoom"
    m.wash.opacity = 0.22
    m.scrim.width = 1920 : m.scrim.height = 1080
    m.scrim.translation = [-150, 0]
    m.scrim.color = "0x0B0B0CFF"

    ' Decision 097 — the art is FITTED at its own aspect. It sits right so the
    ' reading column on the left is never over a busy still.
    m.art.translation = [1002, 168]
    m.art.width = 636 : m.art.height = 750
    m.art.loadDisplayMode = "scaleToFit"

    ' §4.3 — prose the viewer READS starts at the title-safe inset.
    x = 42
    m.title.font = m.t.uMarquee : m.title.color = m.t.textPri
    m.title.translation = [x, 168] : m.title.width = 810
    m.title.maxLines = 2 : m.title.wrap = true

    m.aka.font = m.t.uMeta : m.aka.color = m.t.textSec
    m.aka.translation = [x, 318] : m.aka.width = 810
    m.aka.maxLines = 1

    m.meta.font = m.t.uMeta : m.meta.color = m.t.textSec
    m.meta.translation = [x, 366]

    m.syn.font = m.t.uBody : m.syn.color = m.t.textPri
    m.syn.translation = [x, waitY()] : m.syn.width = 810
    m.syn.wrap = true : m.syn.maxLines = 5

    ' §5.3 — the category chip is the ONLY semantic colour on this screen.
    m.chip.translation = [x, componentY()] : m.chip.height = 6 : m.chip.width = 96
    m.chipText.font = m.t.uMeta : m.chipText.translation = [x + 108, componentY() - 15]

    m.btns.translation = [x, 738]
    m.buttons = []
    addButton("play", "Play", 0)
    addButton("save", "Save", 258)
    addButton("more", "More", 456)
    m.focusIndex = 0
    paintButtons()
end sub

function waitY() as Integer : return 456 : end function
function componentY() as Integer : return 420 : end function

sub addButton(id as String, label as String, dx as Integer)
    g = m.btns.CreateChild("Group")
    g.translation = [dx, 0]
    r = g.CreateChild("Rectangle")
    r.width = 234 : r.height = 72 : r.color = "0x22222AFF"
    l = g.CreateChild("Label")
    l.font = m.t.uRow : l.color = m.t.textPri
    l.translation = [24, 18]
    l.text = label
    m.buttons.Push({ id: id, plate: r, label: l })
end sub

' §5.5 — focus is a ring plus a fill change. There is no scale transform on
' Roku and no shadow; the ring is the platform's grammar.
sub paintButtons()
    for i = 0 to m.buttons.Count() - 1
        b = m.buttons[i]
        if i = m.focusIndex and m.top.focusOn
            b.plate.color = m.t.marquee
            b.label.color = "0x0B0B0CFF"
        else
            b.plate.color = "0x22222AFF"
            b.label.color = m.t.textPri
        end if
    end for
end sub

sub onItem()
    it = m.top.item
    if it = invalid then return
    m.title.text = it.title
    m.meta.text = it.SHORTDESCRIPTIONLINE1
    if it.awBackdrop <> invalid and it.awBackdrop <> ""
        m.wash.uri = it.awBackdrop
        m.art.uri = it.awBackdrop
    else
        m.art.uri = it.HDPOSTERURL
        m.wash.uri = it.HDPOSTERURL
    end if
    if it.awType <> invalid
        m.chip.color = AccentFor(it.awType)
        m.chipText.text = UCase(it.awType)
        m.chipText.color = AccentFor(it.awType)
    end if
    m.aka.text = ""
    m.syn.text = ""
end sub

sub onDetail()
    d = m.top.detail
    if d = invalid then return
    if d.synopsis <> invalid then m.syn.text = d.synopsis

    ' Decision 100 — show the other release title, never reconcile it. The
    ' comparison folds case and accents on the other platforms; here the shard
    ' has already decided the two titles differ materially.
    if d.canonicalTitle <> invalid and d.canonicalTitle <> "" and LCase(d.canonicalTitle) <> LCase(m.title.text)
        m.aka.text = "Also known as " + d.canonicalTitle
    end if

    ' §6.5 — Play carries the runtime, or the resume position once bookmarks
    ' land. A button that says how long the film is answers the question the
    ' viewer actually has.
    if d.runtime <> invalid and d.runtime > 0
        mins = Int(d.runtime / 60)
        m.buttons[0].label.text = "Play  ·  " + fmt(mins) + "m"
    end if
    m.playUrl = d.url
end sub

sub onFocusOn()
    paintButtons()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if key = "right"
        if m.focusIndex < m.buttons.Count() - 1
            m.focusIndex = m.focusIndex + 1 : paintButtons() : return true
        end if
        return true
    else if key = "left"
        if m.focusIndex > 0
            m.focusIndex = m.focusIndex - 1 : paintButtons() : return true
        end if
        return false          ' let the Scene decide (rail / back)
    else if key = "OK"
        b = m.buttons[m.focusIndex]
        if b.id = "play"
            if m.playUrl <> invalid and m.playUrl <> ""
                m.top.play = m.playUrl
            else
                print "AWROKU detail: no playable url"
            end if
        else
            print "AWROKU detail: "; b.id; " not built yet"
        end if
        return true
    end if
    return false
end function
