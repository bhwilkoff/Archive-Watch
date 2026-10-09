// Set the iPhone Duo simulator's pose in Xcode's Device Hub.
//
//   osascript -l JavaScript tools/duo_pose.js "Open" | "Closed" | "Partially Open" | "Rotate Right"
//
// simctl has no hinge control (Xcode 27.1); the poses exist only as Device
// Hub's bottom-bar buttons, and those ignore AXPress — only a real click moves
// the hinge (tried 2026-10-08: AXPress reported success and nothing changed).
// So this finds the button whose accessibility HELP is exactly the name given,
// reads ITS OWN frame, and clicks the center with a CGEvent. No guessed
// coordinate: a guess once landed on a second display (2026-09-23). Only when
// the owner is not using the Mac (memory no-pointer-automation-on-owner-mac).
// Exits non-zero when no button carries that name.
//
// Needs Device Hub open on the Duo simulator, and Accessibility permission for
// the terminal.

ObjC.import('CoreGraphics');

function click(x, y) {
  const p = $.CGPointMake(x, y);
  for (const type of [$.kCGEventMouseMoved, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp]) {
    const e = $.CGEventCreateMouseEvent($(), type, p, $.kCGMouseButtonLeft);
    $.CGEventPost($.kCGHIDEventTap, e);
    delay(0.08);
  }
}

function run(argv) {
  const want = argv[0];
  if (!want) throw new Error('usage: duo_pose.js "Open" | "Closed" | "Partially Open" | "Rotate Right"');
  const se = Application('System Events');
  const proc = se.processes.byName('DeviceHub');
  const win = proc.windows().find(w => /iPhone Duo/.test(w.name()));
  if (!win) throw new Error('no Device Hub window showing an iPhone Duo');
  proc.frontmost = true;
  delay(0.5);

  function find(e, d) {
    if (d > 7) return null;
    let kids = [];
    try { kids = e.uiElements(); } catch (x) { return null; }
    for (const k of kids) {
      let help = null;
      try { help = k.help(); } catch (x) {}
      if (help === want) return k;
      const hit = find(k, d + 1);
      if (hit) return hit;
    }
    return null;
  }
  const button = find(win, 0);
  if (!button) throw new Error(`no Device Hub control named "${want}"`);
  const [x, y] = button.position();
  const [w, h] = button.size();
  click(x + w / 2, y + h / 2);
  return `clicked "${want}" at ${Math.round(x + w / 2)},${Math.round(y + h / 2)}`;
}
