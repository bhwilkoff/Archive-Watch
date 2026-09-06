' Geometry, all divisible by 3 where it shows (§4.2).
function gm() as Object
    return { railW: 384, gap: 12, rowH: 84, rowGap: 9, top: 258, rulerY: 210,
             windowMin: 180, timelineW: 1344, visibleRows: 8 }
end function

sub init()
    m.t = Theme()
    m.g = gm()
    m.heading = m.top.FindNode("heading")
    m.info = m.top.FindNode("info")
    m.ruler = m.top.FindNode("ruler")
    m.clip = m.top.FindNode("clip")
    m.rows = m.top.FindNode("rows")
    m.nowLine = m.top.FindNode("nowLine")
    m.ringG = m.top.FindNode("ring")
    m.empty = m.top.FindNode("empty")
    m.scrollAnim = m.top.FindNode("scrollAnim")
    m.scrollInterp = m.top.FindNode("scrollInterp")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 108]
    m.heading.text = "Channels"

    ' The focused programme, spelled out: a block sized to eleven minutes
    ' cannot carry a title, so the line above the ruler does.
    m.info.font = m.t.uBody : m.info.color = m.t.textSec
    m.info.translation = [42, 165] : m.info.width = 1740 : m.info.maxLines = 1
    m.info.ellipsizeOnBoundary = true

    m.ruler.translation = [42, m.g.rulerY]
    m.clip.translation = [42, m.g.top]
    m.rows.translation = [0, 0]
    m.scrollY = 0

    ' §13.3 — one ring, drawn by this component around whatever is focused.
    m.frame = AWFrameBuild(m.ringG)

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [42, 420] : m.empty.width = 1200 : m.empty.wrap = true

    m.channels = invalid
    m.grid = []          ' per channel: { rail: node, blocks: [ {node, slot, x, w, isNow} ] }
    m.row = 0
    m.col = -1           ' -1 = the channel name cell, else a block index
    m.offsetMin = 0      ' window start relative to now, in minutes (paging)
end sub

sub showChannels(payload as Object)
    if payload = invalid or payload.list = invalid or payload.list.Count() = 0
        ' CLEAR before saying so. Returning here left the PREVIOUS guide drawn
        ' underneath the error, so a failed reload read as a working guide
        ' with a warning over it — the same early-return shape that left a
        ' stale film on Detail (F28) and a stale series below.
        while m.rows.GetChildCount() > 0
            m.rows.RemoveChildIndex(0)
        end while
        m.grid = []
        m.row = 0 : m.col = -1
        hideRing()
        m.empty.visible = true
        m.empty.text = "The channel guide could not be loaded. Check the network and try again."
        return
    end if
    ' The viewer's own channels lead the list. They made them; ours are the
    ' default programming underneath.
    m.channels = []
    for each u in awUserChannels()
        m.channels.Push({ id: u.id, title: u.name, tagline: "Your channel",
                          accent: "#EB5531", programs: invalid,
                          userType: u.type, userDecade: u.decade })
    end for
    for each c in payload.list
        m.channels.Push(c)
    end for
    m.row = 0
    m.col = -1
    m.offsetMin = 0
    paintGrid()
end sub

' A channel that matches nothing must SAY so.
sub sayNoMatch(msg as String)
    m.info.text = msg
end sub

' ---------------------------------------------------------------- drawing --

sub clearGroup(g as Object)
    while g.GetChildCount() > 0
        g.RemoveChildIndex(0)
    end while
end sub

function windowStart() as Integer
    return nowLocalSeconds() + m.offsetMin * 60
end function

' The three-hour window laid out as blocks: each channel a row, each slot a
' block whose width is its minutes on the ruler. Rebuilt whenever the window
' moves; a schedule is cheap arithmetic and the day's listing is deterministic.
sub paintGrid()
    clearGroup(m.ruler)
    clearGroup(m.rows)
    m.grid = []
    if m.channels = invalid then return
    g = m.g
    nowS = nowLocalSeconds()
    winS = windowStart()
    winE = winS + g.windowMin * 60
    ppm = g.timelineW / g.windowMin
    x0 = g.railW + g.gap

    ' Ruler: a tick every half hour. The first reads NOW (marquee) when the
    ' window starts now; paged away, it reads the clock.
    ticks = g.windowMin / 30
    tickW = g.timelineW / ticks
    for i = 0 to ticks - 1
        tx = x0 + Int(i * tickW)
        line = m.ruler.CreateChild("Rectangle")
        line.translation = [tx, 0] : line.width = 1 : line.height = 36
        line.color = "0xFFFFFF1F"
        lab = m.ruler.CreateChild("Label")
        lab.font = m.t.uEyebrow
        lab.translation = [tx + 12, 6]
        if i = 0 and m.offsetMin = 0
            lab.text = "NOW" : lab.color = m.t.marquee
            line.width = 2 : line.color = "0xFFFFFF59"
        else
            lab.text = clockLabel(winS + i * 1800) : lab.color = m.t.textSec
        end if
    end for

    ' The now-line runs down the rows at the window's left edge only while
    ' the window starts now; paged away, there is no "now" on screen.
    m.nowLine.visible = (m.offsetMin = 0)
    m.nowLine.translation = [42 + x0, g.top]
    m.nowLine.width = 3 : m.nowLine.height = 830
    m.nowLine.color = Left(m.t.marquee, 8) + "99"

    for r = 0 to m.channels.Count() - 1
        c = m.channels[r]
        y = r * (g.rowH + g.rowGap)
        acc = m.t.marquee
        if c.accent <> invalid then acc = BroadcastSafe(c.accent)
        entry = { rail: invalid, blocks: [], accent: acc }

        ' The rail cell: the channel's name on its accent at 18%, its number.
        rail = m.rows.CreateChild("Group")
        rail.translation = [0, y]
        plate = rail.CreateChild("Rectangle")
        plate.width = g.railW : plate.height = g.rowH
        plate.color = Left(acc, 8) + "2E"
        roundPlate(rail, plate)
        name = rail.CreateChild("Label")
        name.font = m.t.uItem : name.color = m.t.textPri
        name.translation = [18, 12] : name.width = g.railW - 36
        name.maxLines = 2 : name.wrap = true : name.lineSpacing = -2
        name.text = fmt(c.title)
        num = rail.CreateChild("Label")
        num.font = m.t.uMeta : num.color = m.t.textSec
        num.translation = [g.railW - 84, g.rowH - 36]
        num.text = "CH " + fmt(r + 1)
        entry.rail = rail

        if c.programs = invalid
            ' A user channel is a QUERY, not a schedule: one block for the
            ' whole window saying what it plays.
            rec = makeBlock(y, x0, g.timelineW, "Plays " + describeFacets(c.userType, c.userDecade) + ", shuffled", "", false, acc)
            rec.slot = invalid : rec.x = x0 : rec.w = g.timelineW : rec.isNow = true : rec.userChannel = true
            entry.blocks.Push(rec)
        else
            slots = buildSchedule(fmt(c.id), c.programs, nowS)
            entry.slots = slots
            for i = 0 to slots.Count() - 1
                s = slots[i]
                if s.endS <= winS then continue for
                if s.startS >= winE then exit for
                vs = s.startS : if vs < winS then vs = winS
                ve = s.endS : if ve > winE then ve = winE
                bx = x0 + Int((vs - winS) / 60 * ppm)
                bw = Int((ve - vs) / 60 * ppm) - 3
                if bw < 27 then bw = 27
                isNow = (s.startS <= nowS and nowS < s.endS)
                yr = ""
                if s.prog.Count() > 5 and s.prog[5] <> invalid and fmt(s.prog[5]) <> "" then yr = fmt(s.prog[5])
                rec = makeBlock(y, bx, bw, StripHTML(fmt(s.prog[1])), yr, isNow, acc)
                rec.slot = s : rec.x = bx : rec.w = bw : rec.isNow = isNow : rec.userChannel = false
                entry.blocks.Push(rec)
            end for
        end if
        m.grid.Push(entry)
    end for
    if m.row >= m.grid.Count() then m.row = 0
    if m.col >= m.grid[m.row].blocks.Count() then m.col = m.grid[m.row].blocks.Count() - 1
    scrollToRow(false)
    paintFocus()
end sub

' Four canvas-coloured corners on a plate (§13.4).
sub roundPlate(parent as Object, plate as Object)
    f = AWFrameBuild(parent)
    for each p in f.ring
        p.visible = false
    end for
    AWFramePlace(f, plate, false)
end sub

' Returns { node, plate, title, eyebrow, year }. Direct references, never
' FindNode: ids repeat across blocks, and on the device FindNode answered the
' wrong block — neighbours stayed lit and the focused fill landed elsewhere.
function makeBlock(y as Integer, x as Integer, w as Integer, title as String, yr as String, isNow as Boolean, acc as String) as Object
    g = m.g
    blk = m.rows.CreateChild("Group")
    blk.translation = [x, y]
    plate = blk.CreateChild("Rectangle")
    plate.width = w : plate.height = g.rowH
    plate.color = "0x1F1F24FF"
    roundPlate(blk, plate)
    rec = { node: blk, plate: plate, title: invalid, eyebrow: invalid, year: invalid }
    ty = 12
    if isNow
        eyebrow = blk.CreateChild("Label")
        eyebrow.font = m.t.uEyebrow : eyebrow.color = acc
        eyebrow.translation = [15, 9] : eyebrow.width = w - 30
        eyebrow.maxLines = 1 : eyebrow.ellipsizeOnBoundary = false
        eyebrow.text = AWTracked("ON NOW")
        ' The eyebrow is 90 px of tracked caps; a block cut short by the
        ' window's edge cannot hold it, and clipped caps read as debris.
        eyebrow.visible = (w >= 150)
        rec.eyebrow = eyebrow
        ty = 33
    end if
    lab = blk.CreateChild("Label")
    lab.font = m.t.uItem : lab.color = m.t.textPri
    lab.translation = [15, ty] : lab.width = w - 30
    lab.maxLines = 1 : lab.ellipsizeOnBoundary = true
    lab.text = title
    ' A block narrower than its own padding shows nothing; the ruler still
    ' shows WHERE the programme is, and the info line names it on focus.
    lab.visible = (w >= 120)
    rec.title = lab
    if yr <> "" and w > 150 and not isNow
        yl = blk.CreateChild("Label")
        yl.font = m.t.uMeta : yl.color = m.t.textSec
        yl.translation = [15, g.rowH - 36]
        yl.text = yr
        rec.year = yl
    end if
    return rec
end function

' ------------------------------------------------------------------ focus --

function focusedNode() as Object
    if m.grid.Count() = 0 then return invalid
    e = m.grid[m.row]
    if m.col < 0 then return e.rail
    if m.col < e.blocks.Count() then return e.blocks[m.col].node
    return invalid
end function

' The ring and the fill move; nothing else about the grid changes. The
' previously focused block goes back to its resting plate.
sub paintFocus()
    if m.grid.Count() = 0 then return
    ' Un-light everything (cheap: one plate per visible block).
    for each e in m.grid
        for each b in e.blocks
            b.plate.color = "0x1F1F24FF"
            b.plate.width = b.w
            if b.title <> invalid
                b.title.width = b.w - 30
                b.title.visible = (b.w >= 120)
                b.title.color = m.t.textPri
            end if
            if b.eyebrow <> invalid
                b.eyebrow.color = e.accent
                b.eyebrow.width = b.w - 30
                b.eyebrow.visible = (b.w >= 150)
            end if
        end for
    end for
    e = m.grid[m.row]
    c = m.channels[m.row]
    if c.userType <> invalid then m.top.focusedUserChannel = fmt(c.id) else m.top.focusedUserChannel = ""
    n = focusedNode()
    if n = invalid then return
    if m.col >= 0
        b = e.blocks[m.col]
        ' A focused block fills with the channel's accent and, if it is
        ' narrower than a readable width, grows to one — drawn LAST so it
        ' sits over its neighbours (the tvOS ProgramBlock expansion).
        w = b.w
        if w < 360 then w = 360
        b.plate.color = e.accent
        b.plate.width = w
        if b.title <> invalid
            b.title.width = w - 30
            b.title.visible = true
        end if
        if b.eyebrow <> invalid
            b.eyebrow.color = m.t.textPri
            b.eyebrow.width = w - 30
            b.eyebrow.visible = true
        end if
        m.rows.RemoveChild(n)
        m.rows.AppendChild(n)
        ' The info line: title · start – end.
        if b.userChannel = true
            m.info.text = fmt(c.title) + "  ·  plays " + describeFacets(c.userType, c.userDecade) + ", shuffled"
        else
            s = b.slot
            m.info.text = StripHTML(fmt(s.prog[1])) + "  ·  " + clockLabel(s.startS) + " – " + clockLabel(s.endS)
        end if
    else
        m.info.text = fmt(c.title)
        if c.tagline <> invalid and c.tagline <> "" then m.info.text = m.info.text + "  ·  " + fmt(c.tagline)
    end if
    placeRing(n)
end sub

sub hideRing()
    for each p in m.frame.ring
        p.visible = false
    end for
end sub

sub placeRing(n as Object)
    ' The ring group sits at the screen origin; the block sits inside the
    ' scrolled rows group inside the clip. Compose the offsets.
    p = n.GetChild(0)
    t = n.translation
    ' AWFramePlace reads the art's own translation, so give it a proxy
    ' rectangle positioned in ring-group space.
    if m.ringProxy = invalid
        m.ringProxy = m.ringG.CreateChild("Rectangle")
        m.ringProxy.visible = false
    end if
    m.ringProxy.width = p.width : m.ringProxy.height = p.height
    m.ringProxy.translation = [42 + t[0], m.g.top + m.scrollY + t[1]]
    AWFramePlace(m.frame, m.ringProxy, true)
    for each c in m.frame.corners
        c.visible = false
    end for
end sub

sub scrollToRow(animate as Boolean)
    g = m.g
    stride = g.rowH + g.rowGap
    first = Int(-m.scrollY / stride)
    last = first + g.visibleRows - 1
    target = m.scrollY
    if m.row < first
        target = -m.row * stride
    else if m.row > last
        target = -(m.row - g.visibleRows + 1) * stride
    end if
    if target > 0 then target = 0
    if target = m.scrollY then return
    if animate
        m.scrollAnim.control = "stop"
        m.scrollInterp.keyValue = [[0, m.scrollY], [0, target]]
        m.scrollAnim.control = "start"
    else
        m.rows.translation = [0, target]
    end if
    m.scrollY = target
end sub

' Up/Down keep the TIME: land on the block in the next row that is on the
' air at the focused block's start (the tvOS geometry-based focus).
function blockAt(e as Object, x as Integer) as Integer
    if e.blocks.Count() = 0 then return -1
    for i = 0 to e.blocks.Count() - 1
        b = e.blocks[i]
        if x >= b.x and x < b.x + b.w + 3 then return i
    end for
    if x < e.blocks[0].x then return 0
    return e.blocks.Count() - 1
end function

sub moveRow(delta as Integer)
    n = m.row + delta
    if n < 0 or n >= m.grid.Count() then return
    if m.col >= 0
        cur = m.grid[m.row].blocks[m.col]
        m.col = blockAt(m.grid[n], cur.x)
    end if
    m.row = n
    scrollToRow(true)
    paintFocus()
end sub

' ----------------------------------------------------------------- tuning --

function describeFacets(t as Dynamic, d as Dynamic) as String
    parts = "anything"
    if t <> invalid and fmt(t) <> "" then parts = prettyChannelType(fmt(t))
    if d <> invalid and Int(d) > 0 then parts = parts + " from the " + fmt(Int(d)) + "s"
    return parts
end function

function prettyChannelType(t as String) as String
    if t = "feature-film" then return "feature films"
    if t = "silent-film" then return "silent films"
    if t = "animation" then return "animation"
    if t = "short-film" then return "short films"
    if t = "newsreel" then return "newsreels"
    if t = "documentary" then return "documentaries"
    if t = "ephemeral" then return "ephemeral films"
    if t = "commercial" then return "commercials"
    return "anything"
end function

' Tuning in JOINS whatever is playing, part-way through, the way a television
' does. Starting at the beginning would make it a playlist, not a channel.
sub tuneIn(idx as Integer)
    c = m.channels[idx]
    if c.userType <> invalid
        m.top.tune = { userChannel: true, type: fmt(c.userType), decade: Int(c.userDecade),
                       channel: fmt(c.title) }
        return
    end if
    e = m.grid[idx]
    if e.slots = invalid or e.slots.Count() = 0 then return
    nowS = nowLocalSeconds()
    for i = 0 to e.slots.Count() - 1
        s = e.slots[i]
        if s.startS <= nowS and nowS < s.endS
            queue = []
            for j = i + 1 to e.slots.Count() - 1
                queue.Push({ url: fmt(e.slots[j].prog[3]), title: fmt(e.slots[j].prog[1]) })
                if queue.Count() >= 12 then exit for
            end for
            m.top.tune = { url: fmt(s.prog[3]), title: fmt(s.prog[1]),
                           meta: fmt(c.title) + "  ·  live",
                           channel: fmt(c.title),
                           startAt: nowS - s.startS, queue: queue }
            return
        end if
    end for
end sub

sub selectFocused()
    if m.grid.Count() = 0 then return
    e = m.grid[m.row]
    if m.col < 0
        tuneIn(m.row)
        return
    end if
    b = e.blocks[m.col]
    if b.userChannel = true or b.isNow
        tuneIn(m.row)
    else
        ' A programme later today cannot be "tuned into" — there is nothing to
        ' join yet. Its Detail screen is the honest destination: watch it now
        ' from the start, or save it.
        m.top.chosen = fmt(b.slot.prog[0])
    end if
end sub

sub onFocusOn()
    if m.top.focusOn
        m.top.setFocus(true)
        paintFocus()
    else
        hideRing()
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if m.grid.Count() = 0
        if key = "left" then m.top.exitLeft = true : return true
        return false
    end if
    e = m.grid[m.row]
    if key = "left"
        if m.col > 0
            m.col = m.col - 1 : paintFocus() : return true
        end if
        if m.col = 0
            if m.offsetMin > 0
                ' Page the window back before leaving the grid.
                m.offsetMin = m.offsetMin - 90
                if m.offsetMin < 0 then m.offsetMin = 0
                paintGrid()
                m.col = e.blocks.Count() - 1
                if m.grid[m.row].blocks.Count() > 0 then m.col = m.grid[m.row].blocks.Count() - 1
                paintFocus()
                return true
            end if
            m.col = -1 : paintFocus() : return true
        end if
        hideRing()
        m.top.exitLeft = true
        return true
    else if key = "right"
        if m.col < e.blocks.Count() - 1
            m.col = m.col + 1 : paintFocus() : return true
        end if
        if m.col = e.blocks.Count() - 1 and e.blocks.Count() > 0 and m.grid[m.row].blocks[m.col].userChannel <> true
            ' Past the last block: the window pages forward ninety minutes.
            m.offsetMin = m.offsetMin + 90
            if m.offsetMin > 24 * 60 then m.offsetMin = 24 * 60
            paintGrid()
            m.col = 0
            paintFocus()
            return true
        end if
        return true
    else if key = "down"
        moveRow(1) : return true
    else if key = "up"
        moveRow(-1) : return true
    else if key = "OK"
        selectFocused() : return true
    end if
    return false
end function
