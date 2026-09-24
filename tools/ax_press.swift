// Find and press a NAMED control in one app's window through Accessibility —
// a targeted action on an element, never a pointer click at coordinates (the
// rule after a coordinate click once landed on the owner's other display).
//
//   swiftc -O tools/ax_press.swift -o /tmp/axpress
//   /tmp/axpress <bundleID> list [window-title-substring]
//   /tmp/axpress <bundleID> press "<label>" [window-title-substring]
//   /tmp/axpress <bundleID> set "<label>" "<text>" [window-title-substring]
//   /tmp/axpress <bundleID> focus "<label>" [window-title-substring]   (then send Return)
//
// A label matches AXTitle, AXDescription or AXValue exactly, then by prefix.
import AppKit
import ApplicationServices

func attr(_ e: AXUIElement, _ a: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success, let v else { return nil }
    return (v as? String) ?? (v as? NSNumber)?.stringValue
}
func children(_ e: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}
func walk(_ e: AXUIElement, depth: Int = 0, _ visit: (AXUIElement, Int) -> Bool) -> Bool {
    if visit(e, depth) { return true }
    guard depth < 60 else { return false }
    for c in children(e) where walk(c, depth: depth + 1, visit) { return true }
    return false
}
func label(_ e: AXUIElement) -> String {
    [attr(e, kAXTitleAttribute), attr(e, kAXDescriptionAttribute), attr(e, kAXValueAttribute),
     attr(e, kAXPlaceholderValueAttribute)]
        .compactMap { $0 }.filter { !$0.isEmpty }.first ?? ""
}

let args = CommandLine.arguments
guard args.count >= 3,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first else {
    print("usage: axpress <bundleID> list|press|set ..."); exit(2)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
var windows: CFTypeRef?
AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
let wins = (windows as? [AXUIElement]) ?? []
let mode = args[2]
let winFilter: String? = {
    switch mode {
    case "list": return args.count > 3 ? args[3] : nil
    case "press", "focus": return args.count > 4 ? args[4] : nil
    case "set": return args.count > 5 ? args[5] : nil
    default: return nil
    }
}()
let targets = wins.filter { w in winFilter.map { (attr(w, kAXTitleAttribute) ?? "").contains($0) } ?? true }

if mode == "list" {
    for w in targets {
        print("== window: \(attr(w, kAXTitleAttribute) ?? "")")
        _ = walk(w) { e, d in
            let r = attr(e, kAXRoleAttribute) ?? ""
            let l = label(e)
            if !l.isEmpty, ["AXButton", "AXPopUpButton", "AXRadioButton", "AXTextField", "AXCheckBox",
                            "AXMenuButton", "AXLink", "AXStaticText", "AXSegmentedControl"].contains(r) {
                print("\(String(repeating: " ", count: min(d, 20)))\(r): \(l)")
            }
            return false
        }
    }
    exit(0)
}

let want = args[3]
var found: AXUIElement?
for pass in 0..<2 {
    for w in targets {
        if walk(w, { e, _ in
            let r = attr(e, kAXRoleAttribute) ?? ""
            guard r != "AXStaticText" || mode == "set" else { return false }
            let l = label(e)
            let hit = pass == 0 ? l == want : l.hasPrefix(want)
            if hit { found = e; return true }
            return false
        }) { break }
    }
    if found != nil { break }
}
guard let el = found else { print("NOT FOUND: \(want)"); exit(1) }
if mode == "press" {
    let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
    print(r == .success ? "pressed: \(want)" : "press failed (\(r.rawValue)): \(want)")
    exit(r == .success ? 0 : 1)
} else if mode == "focus" {
    let r = AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    print(r == .success ? "focused: \(want)" : "focus failed (\(r.rawValue)): \(want)")
    exit(r == .success ? 0 : 1)
} else if mode == "set" {
    let r = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, args[4] as CFString)
    print(r == .success ? "set: \(want)" : "set failed (\(r.rawValue)): \(want)")
    exit(r == .success ? 0 : 1)
}
