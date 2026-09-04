sub onToast()
    msg = m.top.toast
    if msg = invalid or msg = "" then return
    ' The toast field was being SET by the save path and rendered by nothing,
    ' so every confirmation and every refusal was invisible. A state the app
    ' knows about and does not show is the same to the viewer as no state.
    print "AWTOAST "; msg
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

    m.cast = m.top.FindNode("cast")
    m.cast.font = m.t.uMeta : m.cast.color = m.t.textSec
    m.cast.width = 1000 : m.cast.maxLines = 1
    m.cast.ellipsizeOnBoundary = true
    ' Below the buttons, not above them: the synopsis is variable-height and
    ' anything placed between it and the buttons collides on a long one.
    ' The vertical budget below the synopsis is real and small: buttons at 738,
    ' a row of tiles must end above 1080, and a cast line has to sit between
    ' the synopsis and the buttons without touching either. Every one of these
    ' numbers was moved after seeing them collide on the glass.
    m.cast.translation = [378, 834]

    m.likeLabel = m.top.FindNode("likeLabel")
    m.likeLabel.font = m.t.uRow : m.likeLabel.color = m.t.textPri
    m.likeLabel.translation = [42, 882]
    m.likeLabel.text = "More like this"

    ' A single short row at the foot of the screen. Tiles are smaller than a
    ' shelf's because this is a footnote to the film, not a shelf in its own
    ' right, and the buttons above it must stay the obvious thing to press.
    m.like = m.top.FindNode("like")
    m.like.translation = [42, 927]
    m.like.itemComponentName = "MiniTile"
    m.like.numRows = 1
    m.like.rowFocusAnimationStyle = "floatingFocus"
    ' 108x162 keeps the row's bottom at 1056 on a 1080 screen — a taller tile
    ' runs off the bottom, which is invisible in code and obvious on a TV.
    m.like.itemSize = [1740, 144]
    m.like.rowItemSize = [[90, 135]]
    m.like.rowItemSpacing = [[18, 0]]
    m.like.showRowLabel = [false]
    ' The TILE rings its own art (ROKU-DESIGN §5.4a). An explicitly transparent
    ' 9-patch is required: with no bitmap the list draws its own grey box.
    m.like.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.like.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.like.drawFocusFeedbackOnTop = true
    m.like.ObserveField("rowItemSelected", "onLikeSelected")

    m.toastPlate = m.top.FindNode("toastPlate")
    m.toastText = m.top.FindNode("toastText")
    m.toastTimer = m.top.FindNode("toastTimer")
    m.toastTimer.ObserveField("fire", "onToastDone")
    ' Bottom of the reading column, inside the title-safe inset (§4.3).
    ' A bar across the foot of the screen. It sits OVER the shelf rather than
    ' beside it, because a message the viewer must read cannot be laid out
    ' around content whose height varies.
    m.toastPlate.translation = [0, 972]
    m.toastPlate.width = 1836 : m.toastPlate.height = 96
    m.toastPlate.color = "0x14141AFF"
    m.toastText.translation = [m.t.readX, 996]
    m.toastText.width = 1600 : m.toastText.wrap = true
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

    ' §13.7 — the backdrop is the top 60% of the screen at full brightness,
    ' with the tvOS gradient (clear, clear, .45, .9, black) over it so the copy
    ' sits on darkness at the seam. The previous build washed it to 0.22
    ' behind an opaque scrim: a picture nobody could see, next to a form.
    m.wash.width = 2070 : m.wash.height = 648
    m.wash.translation = [-150, 0]
    m.wash.loadDisplayMode = "scaleToZoom"
    m.wash.opacity = 1.0
    m.fade = m.top.FindNode("fade")
    m.fade.uri = "pkg:/images/hero_scrim_v.png"
    m.fade.width = 2070 : m.fade.height = 648
    m.fade.translation = [-150, 0]
    m.fade.loadDisplayMode = "scaleToFill"
    ' A film with no backdrop gets a category-accent FIELD (as the hero
    ' does), never a stretched poster.
    m.field = m.top.FindNode("field")
    m.field.width = 2070 : m.field.height = 648
    m.field.translation = [-150, 0]

    ' Decision 097 — the poster FITTED at its own aspect, inset over the seam
    ' lower-left, with the rounded frame every tile carries.
    m.art.translation = [42, 318]
    m.art.width = 288 : m.art.height = 432
    m.art.loadDisplayMode = "scaleToFit"
    m.artFrame = AWFrameBuild(m.top.FindNode("artFrame"))
    m.art.ObserveField("loadStatus", "onArtLoaded")

    ' Copy to the right of the poster. x = 42 + 288 + 48.
    x = 378
    m.kind = m.top.FindNode("kind")
    m.kind.font = m.t.uEyebrow
    m.kind.translation = [x, 318]

    m.title.font = m.t.uTitle : m.title.color = m.t.textPri
    m.title.translation = [x, 348] : m.title.width = 1380
    m.title.maxLines = 2 : m.title.wrap = true

    ' "Also known as" in the tagline voice — Fraunces italic, the way tvOS
    ' sets it.
    m.aka.font = m.t.uTagline : m.aka.color = m.t.textSec
    m.aka.translation = [x, 498] : m.aka.width = 1380
    m.aka.maxLines = 1

    m.meta.font = m.t.uMeta : m.meta.color = m.t.textSec
    m.meta.translation = [x, 546]

    ' Synopsis under the pill row, three lines, then cast.
    m.syn.font = m.t.uBody : m.syn.color = m.t.textPri
    m.syn.translation = [x, 690] : m.syn.width = 1140
    m.syn.wrap = true : m.syn.maxLines = 3
    m.syn.lineSpacing = 6
    m.syn.ellipsizeOnBoundary = true

    ' The old accent rule + slug chip is retired: the eyebrow IS the category.
    m.chip.visible = false
    m.chipText.visible = false

    ' §13.5 — the pill row sits at the seam, right of the poster.
    m.btns.translation = [x, 606]
    m.buttons = []
    addButton("play", "Play")
    addButton("save", "Save")
    addButton("more", "More")
    layoutButtons()
    m.focusIndex = 0
    paintButtons()
end sub

function waitY() as Integer : return 456 : end function
function componentY() as Integer : return 420 : end function

' Buttons are laid out by MEASURING their text, not by guessing a width. Three
' fixed slabs of 396/210/210 left "Save" and "More" swimming in empty plate
' while "Resume · 83m left" was clipped — blocky and badly proportioned at the
' same time.
sub layoutButtons()
    if m.buttons = invalid then return
    x = 0
    for i = 0 to m.buttons.Count() - 1
        b = m.buttons[i]
        tw = b.label.boundingRect().width
        if tw <= 0 then tw = 120
        w = Int(tw) + 72
        if w < 150 then w = 150
        ' Divisible by 3 (§4.2).
        w = Int(w / 3) * 3
        AWPillLayout(b.pill, 0, 0, w)
        b.group.translation = [x, 0]
        b.label.translation = [Int((w - tw) / 2), 12]
        x = x + w + 18
    end for
end sub

' §13.5 — a button is a PILL, never a flat plate.
sub addButton(id as String, label as String)
    g = m.btns.CreateChild("Group")
    pill = AWPillBuild(g)
    l = g.CreateChild("Label")
    l.font = m.t.uRow : l.color = m.t.textPri
    l.text = label
    m.buttons.Push({ id: id, pill: pill, label: l, group: g })
end sub

' Focus is the pill going solid light with dark type; the primary (Play) is
' marquee when focused and outlined-light at rest, so there is one orange
' thing on the screen and it is the thing that plays the film.
sub paintButtons()
    for i = 0 to m.buttons.Count() - 1
        b = m.buttons[i]
        lit = (i = m.focusIndex and m.top.focusOn)
        if b.id = "play"
            if lit
                AWPillStyle(b.pill, "marquee")
                b.label.color = m.t.textPri
            else
                AWPillStyle(b.pill, "outline")
                b.label.color = m.t.textPri
            end if
        else if lit
            AWPillStyle(b.pill, "focus")
            b.label.color = m.t.canvas
        else
            AWPillStyle(b.pill, "rest")
            b.label.color = m.t.textPri
        end if
    end for
end sub

sub onArtLoaded()
    if m.art.loadStatus <> "ready" then return
    ' If the only art is LANDSCAPE it is a still, and a still inset beside
    ' the same still full-bleed is the picture twice. Hide the inset and let
    ' the copy take the column from the title-safe edge.
    landscape = (m.art.bitmapWidth > m.art.bitmapHeight)
    m.art.visible = not landscape
    for each p in m.artFrame.corners
        p.visible = not landscape
    end for
    layoutCopy(not landscape)
    if not landscape then AWFramePlace(m.artFrame, m.art, false)
end sub

' The copy column starts right of the poster, or at the title-safe edge when
' there is no poster to stand beside.
sub layoutCopy(withPoster as Boolean)
    x = 378
    if not withPoster then x = 42
    m.kind.translation = [x, 318]
    m.title.translation = [x, 348]
    ' Stack under the title's RENDERED height. Fixed positions left a 170 px
    ' hole between a one-line title and its meta; a two-line title needs the
    ' room a one-line title must not reserve.
    th = 72
    r = m.title.boundingRect()
    if r <> invalid and r.height > 0 then th = Int(r.height)
    y = 348 + th + 18
    if m.aka.text <> ""
        m.aka.translation = [x, y]
        y = y + 48
    end if
    m.meta.translation = [x, y]
    y = y + 60
    ' The pill row never rises above the seam, so the layout below it is
    ' stable whatever the title did.
    if y < 606 then y = 606
    m.btns.translation = [x, y]
    m.syn.translation = [x, y + 84]
    m.cast.translation = [x, y + 228]
end sub

sub onItem()
    it = m.top.item
    if it = invalid then return
    m.archiveID = it.id
    m.title.text = it.title
    m.meta.text = it.SHORTDESCRIPTIONLINE1
    layoutCopy(true)
    ' §13.7 — the backdrop is the SCENE; the poster is the INSET. They were
    ' both being set to the backdrop, so the inset was the same still twice.
    ' A film with only a poster gets that poster zoomed behind the copy as an
    ' ambient wash at 0.6 — the Apple TV app's treatment for poster-only
    ' titles — which on the glass read better than a flat accent field.
    m.art.visible = true
    if it.awBackdrop <> invalid and it.awBackdrop <> ""
        m.wash.uri = it.awBackdrop
        m.wash.opacity = 1.0
        if it.HDPOSTERURL <> invalid and it.HDPOSTERURL <> ""
            m.art.uri = it.HDPOSTERURL
        else
            m.art.uri = ""
            m.art.visible = false
            layoutCopy(false)
        end if
    else if it.HDPOSTERURL <> invalid and it.HDPOSTERURL <> ""
        m.wash.uri = it.HDPOSTERURL
        m.wash.opacity = 0.6
        m.art.uri = it.HDPOSTERURL
    else
        m.wash.uri = ""
        m.art.uri = ""
        m.art.visible = false
        layoutCopy(false)
    end if
    if it.awType <> invalid
        m.chip.color = AccentFor(it.awType)
        m.kind.text = AWTracked(UCase(KindLabel(fmt(it.awType))))
        m.kind.color = AccentFor(fmt(it.awType))
        m.chipText.color = AccentFor(it.awType)
    end if
    m.aka.text = ""
    m.syn.text = ""
    m.cast.text = ""
    m.like.visible = false
    m.likeLabel.visible = false
    m.likeRow = false
    paintSave()
end sub

sub paintSave()
    if m.archiveID = invalid then return
    if awIsFavorite(m.archiveID)
        m.buttons[1].label.text = "Saved"
    else
        m.buttons[1].label.text = "Save"
    end if
    layoutButtons()
end sub

sub onDetail()
    d = m.top.detail
    if d = invalid then return
    if d.synopsis <> invalid then m.syn.text = StripHTML(fmt(d.synopsis))

    ' Decision 100 — show the other release title, never reconcile it. The
    ' comparison folds case and accents on the other platforms; here the shard
    ' has already decided the two titles differ materially.
    if d.canonicalTitle <> invalid and d.canonicalTitle <> "" and LCase(d.canonicalTitle) <> LCase(m.title.text)
        m.aka.text = "Also known as " + d.canonicalTitle
        layoutCopy(m.art.visible)
    end if

    ' §6.5 — Play carries the runtime, or the RESUME position when the viewer
    ' has a bookmark. Roku certification wants bookmarking for anything over 15
    ' minutes kept for at least 30 days; the registry is where that lives.
    dur = 0
    if d.runtime <> invalid then dur = d.runtime
    m.runtime = dur
    m.top.runtimeSeconds = dur
    paintPlayLabel()
    layoutButtons()
    m.playUrl = d.url

    ' Cast as one honest line rather than a row of faces: the shard carries
    ' TMDb profile paths, but a row of six portraits under a 1959 Argentine
    ' drama pushes the synopsis off the screen for information nobody came for.
    if d.cast <> invalid and d.cast.Count() > 0
        names = []
        for each c in d.cast
            if c.Count() > 0 and names.Count() < 5 then names.Push(fmt(c[0]))
        end for
        if names.Count() > 0
            line = "With "
            for i = 0 to names.Count() - 1
                if i > 0 then line = line + ", "
                line = line + names[i]
            end for
            m.cast.text = line
        end if
    end if

    ' Ask the Scene for similar films once the type and year are known.
    yr = 0
    if m.top.item <> invalid and m.top.item.SHORTDESCRIPTIONLINE1 <> invalid
        yr = Int(Val(Left(m.top.item.SHORTDESCRIPTIONLINE1, 4)))
    end if
    ct = ""
    if m.top.item <> invalid and m.top.item.awType <> invalid then ct = m.top.item.awType
    m.top.wantLike = { id: m.archiveID, contentType: ct, year: yr }

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
    ' The component CLAIMS focus itself, the way every other screen here does.
    ' It used to rely on the Scene calling setFocus after setting focusOn, so
    ' converting the Scene to refocus() (which only toggles the field) left
    ' Detail painted but unfocused — the buttons drew correctly and every press
    ' went straight past them to Home underneath.
    if m.top.focusOn
        m.inLike = false
        ' Every Detail opens on Play. focusIndex was set once in init() and
        ' then survived for the life of the channel, so a viewer who had used
        ' the More menu once landed on More for every film afterwards — and a
        ' Select meant to start the film opened a menu instead. Seen in a
        ' depth-2 sweep: "press Select to play" opened the options panel.
        m.focusIndex = 0
        if m.like <> invalid then m.like.opacity = 0.55
        m.top.setFocus(true)
    end if
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

function iif(c as Boolean, a as String, b as String) as String
    if c then return a
    return b
end function

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if press then print "AWDETAIL key="; key; " zone="; iif(m.inLike = true, "like", "buttons"); " btn="; m.focusIndex
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
    else if key = "down"
        if m.likeRow = true and m.inLike <> true
            m.inLike = true
            m.like.opacity = 1.0
            m.like.setFocus(true)
            return true
        end if
        return false
    else if key = "up"
        if m.inLike = true
            m.inLike = false
            ' A RowList item keeps focusPercent = 1 after the LIST loses focus,
            ' so its ring stays lit and the screen shows two focus rings at
            ' once. Roku treats that lit item as the focus FOOTPRINT, which is
            ' right — but it must read as a footprint, not as focus, so the
            ' whole row dims when it is not the active zone.
            m.like.opacity = 0.55
            m.top.setFocus(true)
            paintButtons()
            return true
        end if
        return false
    else if key = "OK"
        if m.inLike = true then return false
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


sub showLike(items as Object)
    if items = invalid or items.GetChildCount() = 0
        m.like.visible = false
        m.likeLabel.visible = false
        m.likeRow = false
        return
    end if
    ' A RowList's content is ROWS OF ITEMS, not items. Handing it the flat
    ' result list made it render one row — the first film, which has no
    ' children — as an empty box with a focus ring around it.
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    for i = 0 to items.GetChildCount() - 1
        row.AppendChild(items.GetChild(i).Clone(false))
    end for
    m.like.content = root
    m.like.visible = true
    m.likeLabel.visible = true
    m.likeRow = true
end sub

sub onLikeSelected()
    idx = m.like.rowItemSelected
    if m.like.content = invalid then return
    row = m.like.content.GetChild(idx[0])
    if row = invalid then return
    it = row.GetChild(idx[1])
    if it <> invalid then m.top.chosen = it.id
end sub
