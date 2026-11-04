sub init()
    m.t = Theme()
    m.head = m.top.FindNode("head")
    m.body = m.top.FindNode("body")
    m.kb = m.top.FindNode("kb")
    m.list = m.top.FindNode("list")

    veil = m.top.FindNode("dim")
    veil.width = 1920 : veil.height = 1080 : veil.color = "0x000000BB"
    plate = m.top.FindNode("plate")
    plate.translation = [108, 0]
    plate.width = 1704 : plate.height = 1080
    plate.color = "0x121216FF"

    m.head.font = m.t.uScreen : m.head.color = m.t.textPri
    m.head.translation = [150, 78]
    m.body.font = m.t.uBody : m.body.color = m.t.textPri
    m.body.translation = [150, 186]
    m.body.width = 1500 : m.body.wrap = true

    m.kb.translation = [150, 186]

    m.list.itemComponentName = "OptionRow"
    m.list.itemSize = [822, 60]
    m.list.itemSpacing = [0, 24]
    m.list.numRows = 2
    m.list.drawFocusFeedback = false
    m.list.vertFocusAnimationStyle = "floatingFocus"
    m.list.ObserveField("itemSelected", "onPick")
end sub

sub open(payload as Object)
    m.head.text = payload.title
    root = CreateObject("roSGNode", "ContentNode")
    for each b in payload.buttons
        n = root.CreateChild("ContentNode")
        n.title = b
    end for
    m.list.content = root
    m.reading = (payload.message <> invalid)
    m.kb.visible = not m.reading
    m.body.visible = m.reading
    if m.reading
        m.body.text = payload.message
        m.list.translation = [150, 420]
        m.list.setFocus(true)
    else
        m.list.translation = [870, 186]
        if payload.text <> invalid then m.kb.text = payload.text
        m.kb.setFocus(true)
    end if
end sub

sub onPick()
    if not m.reading then m.top.text = m.kb.text
    m.top.buttonSelected = m.list.itemSelected
end sub

' Every key stops here: the panel covers the screen, and anything that reached
' MainScene would act on the surface behind it.
function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return true
    if key = "back"
        m.top.wasClosed = true
    else if key = "right" and m.kb.isInFocusChain()
        m.list.setFocus(true)
    else if key = "left" and not m.reading and m.list.isInFocusChain()
        m.kb.setFocus(true)
    end if
    return true
end function
