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

    ' Rows are OptionRow components (a 60 px pill with the label inset), not
    ' LabelList rows: a LabelList draws its text flush against its focus
    ' bitmap and sizes that bitmap to the whole row — on the Roku 2 XD the
    ' 9-patch pill also came out as a lens (owner, 2026-09-17, twice).
    m.list.translation = [px + 42, 186]
    m.list.itemComponentName = "OptionRow"
    m.list.itemSize = [822, 60]
    m.list.itemSpacing = [0, 24]
    m.list.numRows = 8
    m.list.drawFocusFeedback = false
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
    ' A picker opens ON the value already chosen (F9): the viewer sees where
    ' they are and one press keeps it.
    sel = 0
    if payload.selected <> invalid then sel = payload.selected
    if sel < 0 or sel >= m.ids.Count() then sel = 0
    m.list.jumpToItem = sel
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
