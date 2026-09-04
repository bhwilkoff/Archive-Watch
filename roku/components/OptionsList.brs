sub init()
    m.t = Theme()
    m.dim = m.top.FindNode("dim")
    m.plate = m.top.FindNode("plate")
    m.head = m.top.FindNode("head")
    m.list = m.top.FindNode("list")

    m.dim.width = 1920 : m.dim.height = 1080 : m.dim.color = "0x000000BB"
    ' 726 truncated "…— Archive derivative" on the copy picker, whose whole job
    ' is to state facts about a file. A panel is sized by its longest real
    ' string, not by a round number.
    pw = 906 : px = 1920 - pw
    m.plate.translation = [px, 0]
    m.plate.width = pw : m.plate.height = 1080
    m.plate.color = "0x121216FF"

    m.head.font = m.t.uScreen : m.head.color = m.t.textPri
    m.head.translation = [px + 42, 78]

    m.list.translation = [px + 42, 186]
    m.list.itemSize = [822, 78]
    m.list.itemSpacing = [0, 18]
    m.list.numRows = 8
    m.list.font = m.t.uBody
    m.list.color = m.t.textPri
    m.list.focusedColor = m.t.canvas
    m.list.focusBitmapUri = "pkg:/images/pill_focus.9.png"
    m.list.focusFootprintBitmapUri = "pkg:/images/pill_rest.9.png"
    m.list.drawFocusFeedbackOnTop = false
    m.list.vertFocusAnimationStyle = "floatingFocus"
    m.list.ObserveField("itemSelected", "onPick")
end sub

sub open(payload as Object)
    m.head.text = payload.title
    m.ids = []
    root = CreateObject("roSGNode", "ContentNode")
    for each o in payload.options
        n = root.CreateChild("ContentNode")
        n.title = o.label
        m.ids.Push(o.id)
    end for
    m.list.content = root
    m.top.visible = true
    m.list.jumpToItem = 0
    m.list.setFocus(true)
end sub

sub onPick()
    i = m.list.itemSelected
    if i >= 0 and i < m.ids.Count()
        m.top.visible = false
        m.top.chosen = m.ids[i]
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.visible then return false
    if key = "back" or key = "left"
        m.top.visible = false
        m.top.closed = true
        return true
    end if
    return false
end function
