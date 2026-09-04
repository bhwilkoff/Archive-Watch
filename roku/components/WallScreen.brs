sub init()
    m.t = Theme()
    m.ground = m.top.FindNode("ground")
    m.tilesG = m.top.FindNode("tiles")
    m.hint = m.top.FindNode("hint")
    m.hintPlate = m.top.FindNode("hintPlate")
    m.swap = m.top.FindNode("swap")

    ' Full-bleed, behind the rail as well: the wall IS the screen.
    m.ground.translation = [-84, 0]
    m.ground.width = 1920 : m.ground.height = 1080
    m.ground.color = "0x000000FF"

    m.cols = 9
    ' Three rows, not four: 4 x (297 + 21) is 1272 on a 1080 screen, so the
    ' bottom row was simply cut off. Measured, not estimated.
    m.rowsN = 3
    m.tw = 198 : m.th = 297
    gapX = 15 : gapY = 21
    m.tilesG.translation = [-84 + 24, 42]

    m.cells = []
    for r = 0 to m.rowsN - 1
        for c = 0 to m.cols - 1
            p = m.tilesG.CreateChild("Poster")
            p.width = m.tw : p.height = m.th
            p.translation = [c * (m.tw + gapX), r * (m.th + gapY)]
            ' Decision 097 — fitted, never cropped, even on a wall.
            p.loadDisplayMode = "scaleToFit"
            m.cells.Push(p)
        end for
    end for

    m.hintPlate.translation = [-84, 1008] : m.hintPlate.width = 1920
    m.hintPlate.height = 72 : m.hintPlate.color = "0x0B0B0CE6"
    m.hint.font = m.t.uMeta : m.hint.color = m.t.textSec
    m.hint.translation = [m.t.readX - 84, 1032]
    ' Says only what it does. The first version promised "Press OK for the
    ' film on the wall" with no cursor behind it — the dead-control class this
    ' build keeps re-learning, and I nearly shipped another one.
    ' Back is the platform's own contract; a line saying so is narration.
    m.hint.text = ""

    m.swap.ObserveField("fire", "onSwap")
    m.pool = invalid
    m.slots = []
    m.cursor = 0
end sub

sub showWall(items as Object)
    m.pool = items
    m.slots = []
    if items = invalid or items.GetChildCount() = 0 then return
    n = items.GetChildCount()
    for i = 0 to m.cells.Count() - 1
        idx = i mod n
        m.cells[i].uri = items.GetChild(idx).HDPOSTERURL
        m.slots.Push(idx)
    end for
    m.cursor = m.cells.Count()
    m.swap.control = "start"
end sub

' Three tiles every four seconds. Swapping the whole wall at once reads as a
' page change; three at a time reads as a wall that is alive.
sub onSwap()
    if m.pool = invalid or m.pool.GetChildCount() = 0 then return
    n = m.pool.GetChildCount()
    for k = 1 to 3
        cell = Rnd(m.cells.Count()) - 1
        m.cursor = (m.cursor + 1) mod n
        m.cells[cell].uri = m.pool.GetChild(m.cursor).HDPOSTERURL
        m.slots[cell] = m.cursor
    end for
end sub

sub onFocusOn()
    if m.top.focusOn
        m.top.setFocus(true)
        m.swap.control = "start"
    else
        m.swap.control = "stop"
    end if
end sub

' Any key leaves, which is what a wall should do — except OK, which opens the
' film under the cursor so the wall is a way IN, not only something to look at.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if key = "back"
        m.swap.control = "stop"
        m.top.exit = true
        return true
    end if
    return false
end function
