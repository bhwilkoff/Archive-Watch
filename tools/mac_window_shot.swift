import CoreGraphics
import Foundation
// Capture ONE window of ONE named application, never a screen region.
//
// `screencapture -R x,y,w,h` captures whatever is at those coordinates — which
// on 2026-09-21 meant the owner's grading queue, with student names and email
// addresses in it, because the app window was not in front. A window id is the
// only form of this that cannot pick up somebody else's content.
//
// AND A WINDOW ID IS NOT ENOUGH ON ITS OWN. On 2026-09-22 this matched a
// window by TITLE SUBSTRING alone and captured the owner's TERMINAL, because
// the tab they were working in was titled "Watch Together Studio issues…" —
// the same words as the app window it was looking for. The frame that came
// back was their screen, not the product's. It was only a terminal this time;
// the same match could as easily have found a mail window or a document with
// those words in its name.
//
// So the OWNER APPLICATION is now required and is matched EXACTLY. A title is
// a thing anybody's window can happen to contain; the application that drew it
// is not.
//
//   winshot <app> <title substring> <out.png>
//   winshot "Archive Watch" "Watch Together Studio" /tmp/studio.png
//
// Pass "" as the title to take that application's frontmost window.
let args = CommandLine.arguments
guard args.count >= 4 else {
    print("usage: winshot <app name> <title substring | \"\"> <out.png>")
    print("  the app name is matched EXACTLY — see the header for why")
    exit(2)
}
let app = args[1], needle = args[2], out = args[3]
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    print("no window list"); exit(1)
}
var sawApp = false
for w in list {
    let title = (w[kCGWindowName as String] as? String) ?? ""
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    guard owner == app else { continue }          // EXACT, and first.
    sawApp = true
    guard needle.isEmpty || title.contains(needle) else { continue }
    guard let id = w[kCGWindowNumber as String] as? Int else { continue }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", out]
    try? p.run(); p.waitUntilExit()
    print("captured \"\(title)\" (\(owner)) -> \(out)")
    exit(0)
}
// SAY WHICH HALF FAILED. "no window matching X" sent me looking for a missing
// window when the app was not running at all, and the other way round.
print(sawApp
      ? "\(app) is running but has no window whose title contains \"\(needle)\""
      : "no application named exactly \"\(app)\" has an on-screen window")
exit(1)
