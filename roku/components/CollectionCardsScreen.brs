sub init()
    m.t = Theme()
    m.heading = m.top.FindNode("heading")
    m.tagline = m.top.FindNode("tagline")
    m.empty = m.top.FindNode("empty")
    m.grid = m.top.FindNode("grid")

    m.heading.font = m.t.uScreen : m.heading.color = m.t.textPri
    m.heading.translation = [42, 132]
    m.heading.text = "Collections"

    ' The tvOS subtitle, in the tagline voice.
    m.tagline.font = m.t.uTagline : m.tagline.color = m.t.textSec
    m.tagline.translation = [42, 192]
    m.tagline.text = "Curator-led paths through the archive."

    m.empty.font = m.t.uBody : m.empty.color = m.t.textSec
    m.empty.translation = [42, 400] : m.empty.width = 1200 : m.empty.wrap = true
    m.empty.text = "Collections could not be loaded. Check the network and try again."

    ' Two cards across the 1740 px content column, 36 between; two rows on
    ' screen and the grid scrolls for the rest.
    m.grid.translation = [42, 258]
    m.grid.itemComponentName = "CollectionCard"
    m.grid.numColumns = 2
    m.grid.numRows = 2
    m.grid.itemSize = [852, 324]
    m.grid.itemSpacing = [36, 24]
    ' The CARD rings itself (§13.3); the grid's own bitmap would be a second,
    ' concentric one.
    m.grid.focusBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.focusFootprintBitmapUri = "pkg:/images/focus_none.9.png"
    m.grid.drawFocusFeedbackOnTop = false
    m.grid.vertFocusAnimationStyle = "floatingFocus"
    m.grid.ObserveField("itemSelected", "onSelected")
end sub

sub showCards(root as Object, total as Integer)
    m.grid.content = root
    m.grid.visible = (total > 0)
    m.empty.visible = (total = 0)
end sub

sub onSelected()
    if m.grid.content = invalid then return
    it = m.grid.content.GetChild(m.grid.itemSelected)
    if it = invalid then return
    ' Title first: the Scene reads it when `chosen` fires.
    m.top.chosenTitle = it.title
    m.top.chosen = it.id
end sub

sub onFocusOn()
    if not m.top.focusOn then return
    if m.grid.visible
        m.grid.setFocus(true)
    else
        m.top.setFocus(true)
    end if
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if not m.top.focusOn then return false
    if key = "left"
        if m.grid.itemFocused mod m.grid.numColumns = 0
            m.top.exitLeft = true
            return true
        end if
    end if
    return false
end function
