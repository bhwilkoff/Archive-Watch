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
    m.likeLabel.visible = false

    ' F12 — More Like This is a SHELF, the same PosterTile row Home draws,
    ' with its own row label. The 90 px MiniTile strip at the foot of the
    ' screen read as "rectangles shoved together"; the owner was right. At
    ' rest the row's posters peek above the bottom edge, which says there is
    ' more; Down brings the page up so the shelf sits where the title was.
    m.page = m.top.FindNode("page")
    m.pageAnim = m.top.FindNode("pageAnim")
    m.pageInterp = m.top.FindNode("pageInterp")
    m.pageY = 0
    m.likeY = 900
    m.like = m.top.FindNode("like")
    m.like.translation = [42, m.likeY]
    m.like.itemComponentName = "PosterTile"
    m.like.numRows = 1
    m.like.rowFocusAnimationStyle = "floatingFocus"
    m.like.vertFocusAnimationStyle = "fixedFocus"
    m.like.itemSize = [1740, m.t.posterFH + 232]
    m.like.rowItemSize = [[m.t.posterFW, m.t.posterFH]]
    m.like.rowItemSpacing = [[m.t.gutter, 0]]
    m.like.rowLabelOffset = [[0, 0]]
    m.like.showRowLabel = [true]
    m.like.rowLabelFont = m.t.uRow
    m.like.rowLabelColor = m.t.textPri
    ' The TILE rings its own art (ROKU-DESIGN §5.4a). An explicitly transparent
    ' 9-patch is required: with no bitmap the list draws its own grey box.
    m.like.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.like.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.like.drawFocusFeedbackOnTop = false
    m.like.ObserveField("rowItemSelected", "onLikeSelected")

    ' F4 — the community section: built per film from the shard's `community`
    ' record, laid out below the shelf. Zone order down the page: pills →
    ' More Like This → reviews.
    m.community = m.top.FindNode("community")
    m.communityY = m.likeY + m.t.posterFH + 232 + 24
    m.community.translation = [42, m.communityY]
    m.reviews = []
    m.revIndex = 0
    m.inCommunity = false
    m.revFrame = AWFrameBuild(m.community)

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
    ' The ambient blur base: decode the source at ~200 px, then let the
    ' compositor scale that tiny texture up to fill the whole 2070x648 band.
    ' The bilinear upscale IS the blur (Roku has no shader stage), so a 2:3
    ' poster in a 3.19:1 band reads as a soft wash of the film's own colour
    ' rather than a hard slice cropped from its middle and pixelated 4x.
    m.washBlur = m.top.FindNode("washBlur")
    m.washBlur.width = 2070 : m.washBlur.height = 648
    m.washBlur.translation = [-150, 0]
    m.washBlur.loadDisplayMode = "scaleToZoom"
    ' 96x54: a 10x-plus upscale to the band, heavy enough that even a poster
    ' with large title text dissolves into pure colour atmosphere rather than
    ' staying semi-legible behind the copy. Measured at 200 the tablet text on
    ' The Ten Commandments was still readable; at 96 it is a soft field.
    m.washBlur.loadWidth = 64 : m.washBlur.loadHeight = 36
    m.washBlur.opacity = 1.0

    ' The SHARP layer, on top of the blur: only ever a real 16:9 backdrop
    ' (w1280 -> ~1920 on screen, ~1.5x, crisp). A poster never renders here.
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

    ' A low uniform scrim over the band: the vertical gradient darkens the
    ' seam, but a colourful poster blur can still be bright up top where the
    ' eyebrow and title sit. 30% black tames it without dimming a backdrop
    ' into mud.
    m.scrim.width = 2070 : m.scrim.height = 648
    m.scrim.translation = [-150, 0]
    m.scrim.color = "0x0A0A0A4D"
    m.scrim.visible = true

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
    m.reading = false
    ' §13.12 — the reading header: the title in the row voice, shown only
    ' while the synopsis is expanded and the scene above it has slid away.
    m.readTitle = m.page.CreateChild("Label")
    m.readTitle.font = m.t.uRow : m.readTitle.color = m.t.textSec
    m.readTitle.visible = false
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
    m.artShown = not landscape
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


' A tiny rendition of an image URL, for the ambient blur base only. Roku
' caches a decoded bitmap per URL, so the blur node reusing the inset poster's
' URL got the inset's LARGE decode and loadWidth was ignored — the background
' stayed semi-sharp. A distinct small URL forces a distinct small decode, which
' is what actually produces the heavy blur. Hosts without a size lever fall
' through and lean on loadWidth + the scrim.
function blurSrc(url as String) as String
    if url = "" then return ""
    if Instr(1, url, "image.tmdb.org") > 0
        ' /t/p/w780/hash.jpg or /t/p/original/hash.jpg -> /t/p/w92/hash.jpg
        r = CreateObject("roRegex", "/(w\d+|original)/", "")
        return r.ReplaceAll(url, "/w92/")
    end if
    if Instr(1, url, "commons.wikimedia.org") > 0 or Instr(1, url, "upload.wikimedia.org") > 0
        if Instr(1, url, "width=") > 0
            r = CreateObject("roRegex", "width=\d+", "")
            return r.ReplaceAll(url, "width=120")
        end if
        if Instr(1, url, "?") > 0 then return url + "&width=120"
        return url + "?width=120"
    end if
    if Instr(1, url, "m.media-amazon.com") > 0
        r = CreateObject("roRegex", "_S[XY]\d+", "")
        return r.ReplaceAll(url, "_SX120")
    end if
    ' Every other host (archive.org frame covers, tvdb, upload.wikimedia): there
    ' is no size lever in the URL, and Roku's per-URL decode cache hands this
    ' node the inset's FULL decode, so loadWidth is ignored and the "blur" is a
    ' near-sharp crop — the owner: "a pixelated crop of a screenshot". A query
    ' string the host ignores makes the cache key distinct, so this node's own
    ' tiny loadWidth finally applies.
    if Instr(1, url, "?") > 0 then return url + "&aw=blur"
    return url + "?aw=blur"
end function

sub onItem()
    it = m.top.item
    if it = invalid then return
    m.archiveID = it.id
    m.title.text = it.title
    m.meta.text = it.SHORTDESCRIPTIONLINE1
    ' The audience's rating rides the meta line, as on tvOS — only when a
    ' real audience produced it (100+ votes; the item carries none otherwise).
    if it.HasField("awRating")
        if it.awRating > 0
            m.meta.text = m.meta.text + "  ·  " + AWStar() + " " + Left(fmt(it.awRating / 10.0), 3)
        end if
    end if
    exitReading()
    layoutCopy(true)
    ' §13.7 — the backdrop is the SCENE; the poster is the INSET. They were
    ' both being set to the backdrop, so the inset was the same still twice.
    ' A film with only a poster gets that poster zoomed behind the copy as an
    ' ambient wash at 0.6 — the Apple TV app's treatment for poster-only
    ' titles — which on the glass read better than a flat accent field.
    m.art.visible = true
    hasBd = (it.awBackdrop <> invalid and it.awBackdrop <> "")
    hasPoster = (it.HDPOSTERURL <> invalid and it.HDPOSTERURL <> "")

    ' The ambient blur base exists ONLY under a true backdrop.
    '
    ' It used to be drawn from the poster too, and that is the "pixelated
    ' blurry graphic" the owner reported on The Little Princess (1939): its
    ' art is a 600px Commons STILL, and stretching that across a 1920-wide
    ' band cannot look like anything else. 188 of the 250 curated films with
    ' professional art have no backdrop, so this was the common case, not the
    ' edge one. A poster-only film now gets a DESIGNED field in the film's
    ' own category accent — always sharp, because it is not a bitmap.
    if hasBd
        m.washBlur.uri = blurSrc(it.awBackdrop)
        m.washBlur.opacity = 1.0
    else
        m.washBlur.uri = ""
        m.washBlur.opacity = 0.0
    end if

    ' The sharp layer is ONLY a true 16:9 backdrop. A poster never renders as a
    ' hard background (Decision 097) — it is the inset, and its colour lives in
    ' the blur behind. The accent field shows only when there is no image at all.
    if hasBd
        m.wash.uri = it.awBackdrop
        m.wash.visible = true
        m.field.visible = false
        ' A true backdrop is the hero — keep the scrim light so it stays vivid.
        m.scrim.color = "0x0A0A0A33"
    else
        m.wash.uri = ""
        m.wash.visible = false
        ' The accent field is the treatment for EVERY film without a real
        ' backdrop, whether or not it has a poster — a colour field the app
        ' designed beats an upscale of a small image it did not.
        m.field.visible = true
        ' The field carries its own weight, so the scrim only needs to keep
        ' the copy legible rather than hide a bad picture.
        m.scrim.color = "0x0A0A0A40"
    end if
    m.wash.opacity = 1.0

    if hasPoster
        m.art.uri = it.HDPOSTERURL
    else
        m.art.uri = ""
        m.art.visible = false
        layoutCopy(false)
    end if
    ' Remembered for reading mode, which hides the scene and must restore
    ' exactly what this decided.
    m.artShown = m.art.visible
    m.washOpacity = m.wash.opacity
    m.washBlurOpacity = m.washBlur.opacity
    if it.awType <> invalid
        m.chip.color = AccentFor(it.awType)
        m.kind.text = AWTracked(UCase(KindLabel(fmt(it.awType))))
        m.kind.color = AccentFor(fmt(it.awType))
        m.chipText.color = AccentFor(it.awType)
        ' The field carries the category accent over black, so a Detail with
        ' no backdrop still reads as "a silent film" / "a newsreel" rather
        ' than a blank rectangle. It is the whole background now, not a
        ' fallback for the imageless case, so it is deepened accordingly —
        ' the accent is the design, and it is never blurry.
        acc = AccentFor(fmt(it.awType))
        m.field.color = Left(acc, 8) + "3D"
    end if
    m.aka.text = ""
    m.syn.text = ""
    m.syn.color = m.t.textPri
    m.cast.text = ""
    m.like.visible = false
    m.likeRow = false
    m.inLike = false
    m.inCommunity = false
    m.community.visible = false
    m.hasCommunity = false
    slidePage(0)
    paintSave()
end sub

' F4 — archive.org's viewers: a stats line and up to six reviews as cards.
' Stars ride the meta voice; a review body is capped at six lines and Select
' on the card opens the rest, the tvOS ReviewCard contract.
sub buildCommunity(cm as Object)
    while m.community.GetChildCount() > 0
        m.community.RemoveChildIndex(0)
    end while
    m.revFrame = AWFrameBuild(m.community)
    m.reviews = []
    m.hasCommunity = false
    if cm = invalid then return
    stats = ""
    if cm.r <> invalid and cm.r > 0
        stats = AWStar() + " " + Left(fmt(cm.r), 3) + " on archive.org"
    end if
    if cm.v <> invalid and cm.v > 0
        if stats <> "" then stats = stats + "  ·  "
        stats = stats + AWGroup(Int(cm.v)) + " views"
    end if
    if cm.f <> invalid and cm.f > 0
        if stats <> "" then stats = stats + "  ·  "
        stats = stats + AWPlural(Int(cm.f), "favorite")
    end if
    rv = cm.rv
    if stats = "" and (rv = invalid or rv.Count() = 0) then return
    head = m.community.CreateChild("Label")
    head.font = m.t.uRow : head.color = m.t.textPri
    head.translation = [0, 0]
    head.text = "From archive.org viewers"
    y = 48
    if stats <> ""
        sl = m.community.CreateChild("Label")
        sl.font = m.t.uMeta : sl.color = m.t.textSec
        sl.translation = [0, y]
        sl.text = stats
        y = y + 48
    end if
    if rv <> invalid
        for each r in rv
            if r.Count() >= 3 and m.reviews.Count() < 6
                card = m.community.CreateChild("Group")
                plate = card.CreateChild("Rectangle")
                plate.width = 1740
                plate.color = "0x131317FF"
                ' The heading line: stars, then the review's title.
                line = ""
                if r[0] <> invalid and r[0] > 0
                    for k = 1 to 5
                        if k <= Int(r[0]) then line = line + AWStar() else line = line + "☆"
                    end for
                end if
                if r[1] <> invalid and fmt(r[1]) <> ""
                    if line <> "" then line = line + "   "
                    line = line + StripHTML(fmt(r[1]))
                end if
                hl = card.CreateChild("Label")
                hl.font = m.t.uItem : hl.color = m.t.textPri
                hl.translation = [24, 18] : hl.width = 1692
                hl.maxLines = 1 : hl.ellipsizeOnBoundary = true
                hl.text = line
                body = card.CreateChild("Label")
                body.font = m.t.uBody : body.color = m.t.textSec
                body.translation = [24, 60] : body.width = 1692
                body.wrap = true : body.maxLines = 6 : body.lineSpacing = 4
                body.ellipsizeOnBoundary = true
                body.text = StripHTML(fmt(r[2]))
                by = ""
                if r.Count() > 3 and r[3] <> invalid and fmt(r[3]) <> "" then by = "— " + fmt(r[3])
                if r.Count() > 4 and r[4] <> invalid and fmt(r[4]) <> ""
                    if by <> "" then by = by + ", "
                    by = by + Left(fmt(r[4]), 10)
                end if
                bl = card.CreateChild("Label")
                bl.font = m.t.uMeta : bl.color = m.t.textSec
                bl.translation = [24, 0]
                bl.text = by
                m.reviews.Push({ card: card, plate: plate, body: body, byline: bl, expanded: false })
            end if
        end for
    end if
    m.hasCommunity = true
    layoutCommunity()
    m.community.visible = true
end sub

' Cards stack under one another at their RENDERED heights, so an expanded
' review pushes the ones below it down rather than over them.
sub layoutCommunity()
    y = 48
    if m.community.GetChildCount() > 1
        second = m.community.GetChild(1)
        if second.subtype() = "Label" then y = 96
    end if
    for each rv in m.reviews
        rv.card.translation = [0, y]
        bh = 0
        r = rv.body.boundingRect()
        if r <> invalid then bh = Int(r.height)
        if rv.body.text = "" then bh = 0
        by = 60 + bh + 12
        rv.byline.translation = [24, by]
        h = by + 48
        rv.plate.height = h
        y = y + h + 18
    end for
    m.communityH = y
end sub

sub enterCommunity()
    if m.hasCommunity <> true or m.reviews.Count() = 0 then return
    m.inCommunity = true
    m.inLike = false
    ' The shelf above would leave its captions peeking at the top of the
    ' screen once the page has scrolled to the reviews; it goes with the scene.
    m.like.opacity = 0.0
    m.like.setFocus(false)
    m.top.setFocus(true)
    m.revIndex = 0
    scrollToReview()
    print "AWDETAIL zone=community"
end sub

sub leaveCommunity()
    m.inCommunity = false
    for each p in m.revFrame.ring
        p.visible = false
    end for
    m.like.opacity = 0.55
    if m.likeRow = true
        enterLike()
    else
        slidePage(0)
        m.cast.opacity = 1.0
        m.syn.opacity = 1.0
        paintButtons()
    end if
end sub

sub scrollToReview()
    rv = m.reviews[m.revIndex]
    ' The section heading sits at the heading line for the first card; later
    ' cards sit a little below it so the one above stays in view.
    top = m.communityY + rv.card.translation[1]
    if m.revIndex = 0
        slidePage(-(m.communityY - 132))
    else
        slidePage(-(top - 300))
    end if
    for each p in m.revFrame.ring
        p.visible = false
    end for
    AWFramePlace(m.revFrame, rv.plate, true)
    ' AWFramePlace offsets by the plate's translation, which is 0 inside the
    ' card; the ring lives in the section group, so shift it to the card.
    ct = rv.card.translation
    for each p in m.revFrame.ring
        t = p.translation
        p.translation = [t[0] + ct[0], t[1] + ct[1]]
    end for
    for each p in m.revFrame.corners
        p.visible = false
    end for
end sub

sub toggleReview()
    rv = m.reviews[m.revIndex]
    if rv.body.isTextEllipsized <> true and rv.expanded <> true then return
    rv.expanded = not rv.expanded
    if rv.expanded then rv.body.maxLines = 40 else rv.body.maxLines = 6
    layoutCommunity()
    scrollToReview()
end sub

' The page slides as one Group, the way Home's hero does (one animation, so
' nothing can drift out of register).
sub slidePage(y as Integer)
    if m.pageY = y then return
    m.pageAnim.control = "stop"
    m.pageInterp.keyValue = [[0, m.pageY], [0, y]]
    m.pageAnim.control = "start"
    m.pageY = y
end sub

sub enterLike()
    m.inLike = true
    m.like.opacity = 1.0
    ' The row label lands at the screen heading line (132), the posters
    ' under it, the scene above scrolled away.
    slidePage(-(m.likeY - 132))
    ' The cast line would sit alone above the row label once the scene has
    ' scrolled off — one orphaned sentence at the top of the screen. Hide it
    ' with the scene; it returns with it.
    m.cast.opacity = 0.0
    m.syn.opacity = 0.0
    m.like.setFocus(true)
    print "AWDETAIL zone=like likeFocus="; m.like.hasFocus()
end sub

sub leaveLike()
    m.inLike = false
    ' A RowList item keeps focusPercent = 1 after the LIST loses focus, so
    ' its ring stays lit. Roku treats that lit item as the focus FOOTPRINT,
    ' which is right — but it must read as a footprint, so the row dims.
    m.like.opacity = 0.55
    slidePage(0)
    m.cast.opacity = 1.0
    m.syn.opacity = 1.0
    ' Lesson 98: the RowList holds focus here, and claiming the Group over
    ' it is a silent no-op — release the row first.
    m.like.setFocus(false)
    m.top.setFocus(true)
    paintButtons()
    print "AWDETAIL zone=buttons topFocus="; m.top.hasFocus(); " likeFocus="; m.like.hasFocus()
end sub

function synopsisCut() as Boolean
    return (m.syn.isTextEllipsized = true)
end function

sub readSynopsis()
    enterReading()
end sub

sub paintSave()
    if m.archiveID = invalid then return
    if awIsFavorite(m.archiveID)
        m.buttons[1].label.text = "Saved"
        layoutButtons()
    else
        m.buttons[1].label.text = "Save"
        layoutButtons()
    end if
    layoutButtons()
end sub

sub onDetail()
    d = m.top.detail
    if d = invalid then return
    ' The Scene assigns {} to reset the screen before the shard answers. That
    ' placeholder used to run this whole handler — including a "more like
    ' this" request — so two requests raced on the service and the results
    ' handler's clear wiped the second: the trace showed a bare full-catalog
    ' scan after every Detail open.
    if d.Count() = 0 then return
    if d.synopsis <> invalid then m.syn.text = StripHTML(fmt(d.synopsis))
    ' A film with no synopsis left a 300 px void under the pills. Say so,
    ' quietly — the honest line about this archive, in the secondary voice.
    if m.syn.text = ""
        m.syn.text = "The archive holds no synopsis for this copy."
        m.syn.color = m.t.textSec
    end if

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

    buildCommunity(d.community)

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
        if m.like <> invalid
            m.like.opacity = 0.55
            m.like.setFocus(false)
        end if
        m.inLike = false
        m.inCommunity = false
        if m.revFrame <> invalid
            for each p in m.revFrame.ring
                p.visible = false
            end for
        end if
        slidePage(0)
        m.cast.opacity = 1.0
        m.syn.opacity = 1.0
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
    ' F6 — a longer label ("Resume · 83m left") in a pill measured for
    ' "Play · 91m" overflowed its ends; re-measure after every text change.
    layoutButtons()
end sub


function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if press then print "AWDETAIL key="; key; " zone="; iif(m.inLike = true, "like", "buttons"); " btn="; m.focusIndex
    if not m.top.focusOn then return false
    if m.inCommunity = true
        if key = "down"
            if m.revIndex < m.reviews.Count() - 1
                m.revIndex = m.revIndex + 1
                scrollToReview()
            end if
            return true
        else if key = "up"
            if m.revIndex > 0
                m.revIndex = m.revIndex - 1
                scrollToReview()
            else
                leaveCommunity()
            end if
            return true
        else if key = "OK"
            toggleReview()
            return true
        else if key = "back"
            leaveCommunity()
            return true
        else if key = "left"
            m.top.exitLeft = true
            return true
        end if
        return true
    end if
    if key = "right"
        if m.focusIndex < m.buttons.Count() - 1
            m.focusIndex = m.focusIndex + 1 : paintButtons() : return true
        end if
        return true
    else if key = "left"
        if m.focusIndex > 0
            m.focusIndex = m.focusIndex - 1 : paintButtons() : return true
        end if
        if m.inLike <> true and m.reading <> true
            m.top.exitLeft = true
            return true
        end if
        if m.inLike = true
            idx = m.like.rowItemFocused
            if idx <> invalid and idx[1] = 0
                m.top.exitLeft = true
                return true
            end if
        end if
        return false
    else if key = "down"
        if m.reading = true
            exitReading()
            return true
        end if
        ' F12 — Down goes to More Like This, and nowhere else. The reading
        ' stop ("Down just highlights the description") is gone from this
        ' path; a cut synopsis is read from the More menu.
        if m.likeRow = true and m.inLike <> true
            enterLike()
            return true
        end if
        if m.inLike = true and m.hasCommunity = true and m.reviews.Count() > 0
            enterCommunity()
            return true
        end if
        if m.inLike <> true and m.likeRow <> true and m.hasCommunity = true and m.reviews.Count() > 0
            enterCommunity()
            return true
        end if
        return false
    else if key = "back"
        if m.reading = true
            exitReading()
            return true
        end if
        return false
    else if key = "up"
        if m.reading = true
            exitReading()
            return true
        end if
        if m.inLike = true
            leaveLike()
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
    ' Fewer than four is a coincidence of the catalog, not a shelf.
    if items = invalid or items.GetChildCount() < 4
        m.like.visible = false
        m.likeRow = false
        return
    end if
    ' A RowList's content is ROWS OF ITEMS, not items. Handing it the flat
    ' result list made it render one row — the first film, which has no
    ' children — as an empty box with a focus ring around it.
    root = CreateObject("roSGNode", "ContentNode")
    row = root.CreateChild("ContentNode")
    row.title = "More like this"
    for i = 0 to items.GetChildCount() - 1
        row.AppendChild(items.GetChild(i).Clone(false))
    end for
    m.like.content = root
    m.like.opacity = 0.55
    m.like.visible = true
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

' §13.12 — reading mode. The scene dims to an ambient wash, the copy above
' the synopsis leaves, and the synopsis takes the whole column from the
' title-safe top: 16 lines against the 3 it is cut to at rest. Nothing is
' narrated; Up or Back restores the page, Down continues to More Like This.
sub enterReading()
    if m.reading = true then return
    m.reading = true
    print "AWDETAIL reading on"
    for each n in [m.kind, m.title, m.aka, m.meta, m.btns, m.cast, m.chip, m.chipText, m.art, m.like]
        if n <> invalid then n.visible = false
    end for
    for each p in m.artFrame.corners
        p.visible = false
    end for
    m.wash.opacity = 0.18
    m.washBlur.opacity = 0.10
    m.readTitle.text = m.title.text
    m.readTitle.translation = [42, 150]
    m.readTitle.visible = true
    m.syn.translation = [42, 232]
    m.syn.width = 1500
    m.syn.maxLines = 16
end sub

sub exitReading()
    if m.reading <> true then return
    m.reading = false
    print "AWDETAIL reading off"
    m.readTitle.visible = false
    m.syn.width = 1140
    m.syn.maxLines = 3
    for each n in [m.kind, m.title, m.meta, m.btns, m.cast, m.chip, m.chipText]
        if n <> invalid then n.visible = true
    end for
    m.aka.visible = (m.aka.text <> "")
    m.like.visible = m.likeRow = true
    m.art.visible = m.artShown = true
    for each p in m.artFrame.corners
        p.visible = (m.artShown = true and m.art.loadStatus = "ready")
    end for
    m.wash.opacity = m.washOpacity
    m.washBlur.opacity = m.washBlurOpacity
    layoutCopy(m.artShown = true)
end sub
