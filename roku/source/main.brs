' Archive Watch for Roku — entry point.
'
' Roku channels start on a plain BrightScript thread. Everything visible lives
' in SceneGraph, so Main's only jobs are to create the screen, hand it a message
' port, show the Scene, and then sit in the event loop until the screen closes.
' Nothing expensive belongs here: this thread also draws, so work done inline is
' work the viewer sees as a frozen UI.
sub Main(args as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)

    scene = screen.CreateScene("MainScene")
    screen.Show()

    ' Deep links arrive as launch args (ECP /launch/dev?contentId=...), both on
    ' a cold start and, later, through roInput while running.
    if args <> invalid and args.contentId <> invalid
        if args.mediaType <> invalid then scene.deepLinkMediaType = args.mediaType
        scene.deepLinkContentId = args.contentId
    end if

    ' A deep link that arrives while the channel is ALREADY RUNNING comes
    ' through roInput, not through Main's args — a channel that only reads args
    ' answers the first link of a session and silently ignores every one after
    ' it, which is exactly what a test harness driving many films would hit.
    input = CreateObject("roInput")
    input.SetMessagePort(port)

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        else if type(msg) = "roInputEvent"
            if msg.IsInput()
                info = msg.GetInfo()
                if info.contentId <> invalid
                    if info.mediaType <> invalid then scene.deepLinkMediaType = info.mediaType
                    scene.deepLinkContentId = info.contentId
                end if
            end if
        end if
    end while
end sub
