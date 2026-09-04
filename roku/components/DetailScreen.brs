sub onToast()
    msg = m.top.toast
    if msg = invalid or msg = "" then return
    ' The toast field was being SET by the save path and rendered by nothing,
    ' so every confirmation and every refusal was invisible. A state the app
    ' knows about and does not show is the same to the viewer as no state.
    m.toastText.text = msg
    m.toastText.visible = true
    m.toastPlate.visible = true
    m.toastTimer.control = "start"
end sub

sub onToastDone()
    m.toastText.visible = false
    m.toastPlate.visible = false
end sub

sub init()
    m.t = Theme()

    m.toastPlate = m.top.FindNode("toastPlate")
    m.toastText = m.top.FindNode("toastText")
    m.toastTimer = m.top.FindNode("toastTimer")
    m.toastTimer.ObserveField("fire", "onToastDone")
    ' Bottom of the reading column, inside the title-safe inset (§4.3).
    m.toastPlate.translation = [m.t.readX, 900]
    m.toastPlate.width = 1200 : m.toastPlate.height = 96
    m.toastPlate.color = "0x1C1C22FF"
    m.toastText.translation = [m.t.readX + 24, 924]
    m.toastText.width = 1152 : m.toastText.wrap = true
    m.toastText.maxLines = 2
    m.toastText.font = m.t.uBody
    m.toastText.color = m.t.textPri
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
    addButton("play", "Play", 0, 396)
    addButton("save", "Save", 420, 210)
    addButton("more", "More", 654, 210)
    m.focusIndex = 0
    paintButtons()
end sub

function waitY() as Integer : return 456 : end function
function componentY() as Integer : return 420 : end function

sub addButton(id as String, label as String, dx as Integer, w = 234 as Integer)
    g = m.btns.CreateChild("Group")
    g.translation = [dx, 0]
    r = g.CreateChild("Rectangle")
    ' Play is wider than the others because its label carries the runtime or
    ' the resume position — "Resume · 83m left" was clipped at 234.
    r.width = w : r.height = 72 : r.color = "0x22222AFF"
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
    m.archiveID = it.id
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
    paintSave()
end sub

sub paintSave()
    if m.archiveID = invalid then return
    if awIsFavorite(m.archiveID)
        m.buttons[1].label.text = "Saved"
    else
        m.buttons[1].label.text = "Save"
    end if
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

    ' §6.5 — Play carries the runtime, or the RESUME position when the viewer
    ' has a bookmark. Roku certification wants bookmarking for anything over 15
    ' minutes kept for at least 30 days; the registry is where that lives.
    dur = 0
    if d.runtime <> invalid then dur = d.runtime
    m.runtime = dur
    m.top.runtimeSeconds = dur
    paintPlayLabel()
    m.playUrl = d.url

    ' Captions ride in the shard as [[lang, label, url], ...]. Only ~17% of the
    ' catalog has any, so the absence of a track is the normal case and must
    ' never look like a failure.
    m.top.captionUrl = ""
    if d.captions <> invalid and d.captions.Count() > 0
        for each tr in d.captions
            if tr.Count() >= 3 and LCase(fmt(tr[0])) = "en"
                m.top.captionUrl = fmt(tr[2])
                exit for
            end if
        end for
        if m.top.captionUrl = "" then m.top.captionUrl = fmt(d.captions[0][2])
    end if
end sub

sub onFocusOn()
    paintButtons()
end sub

' Returning from the player must recompute the Play label: the bookmark was
' written while this screen sat behind the video, and nothing about the detail
' record changed, so no observer fires on its own.
sub refresh()
    paintSave()
    paintPlayLabel()
    paintButtons()
end sub

sub paintPlayLabel()
    if m.archiveID = invalid then return
    dur = 0
    if m.runtime <> invalid then dur = m.runtime
    posn = awGetProgress(m.archiveID)
    if posn > 0 and awIsResumable(posn, dur)
        left = Int((dur - posn) / 60)
        m.buttons[0].label.text = "Resume  ·  " + fmt(left) + "m left"
        m.top.playFrom = posn
    else if dur > 0
        mins = Int(dur / 60)
        m.buttons[0].label.text = "Play  ·  " + fmt(mins) + "m"
        m.top.playFrom = 0
    end if
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
        else if b.id = "save"
            r = awToggleFavorite(m.archiveID)
            if r = invalid
                ' §7.2 — the 32 KB budget is real, and a full library says so
                ' rather than dropping the request on the floor.
                m.top.toast = "Your library is full. Remove something in Library first."
            else
                paintSave()
                if r then m.top.toast = "Saved to your library." else m.top.toast = "Removed from your library."
            end if
        else if b.id = "more"
            m.top.showMore = true
        end if
        return true
    end if
    return false
end function
