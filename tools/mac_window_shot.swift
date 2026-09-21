import CoreGraphics
import Foundation
// Capture ONE window by title, never a screen region.
//
// `screencapture -R x,y,w,h` captures whatever is at those coordinates — which
// on 2026-09-21 meant the owner's grading queue, with student names and email
// addresses in it, because the app window was not in front. A window id is the
// only form of this that cannot pick up somebody else's content.
let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: winshot <title substring> <out.png>"); exit(2) }
let needle = args[1], out = args[2]
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    print("no window list"); exit(1)
}
for w in list {
    let title = (w[kCGWindowName as String] as? String) ?? ""
    let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
    guard title.contains(needle) || (needle == owner && !title.isEmpty) else { continue }
    guard let id = w[kCGWindowNumber as String] as? Int else { continue }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", out]
    try? p.run(); p.waitUntilExit()
    print("captured \"\(title)\" (\(owner)) -> \(out)")
    exit(0)
}
print("no window matching \"\(needle)\"")
exit(1)
