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
        scene.deepLinkContentId = args.contentId
    end if

    while true
        msg = wait(0, port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        end if
    end while
end sub
