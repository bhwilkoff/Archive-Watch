// Set the iPhone Duo simulator's pose in Xcode's Device Hub.
//
//   osascript -l JavaScript tools/duo_pose.js "Open" | "Closed" | "Partially Open" | "Rotate Right"
//
// simctl has no hinge control (Xcode 27.1); the poses exist only as Device
// Hub's bottom-bar buttons. This presses the button whose accessibility HELP is
// exactly the name given, with AXPress — no pointer event, so it can only
// reach that button (the cursor-click accident of 2026-09-23 cannot recur:
// memory no-pointer-automation-on-owner-mac). Exits non-zero when no button
// carries that name, instead of pressing something nearby.
//
// Needs Device Hub open on the Duo simulator, and Accessibility permission for
// the terminal.

function run(argv) {
  const want = argv[0];
  if (!want) throw new Error('usage: duo_pose.js "Open" | "Closed" | "Partially Open" | "Rotate Right"');
  const se = Application('System Events');
  const proc = se.processes.byName('DeviceHub');
  const win = proc.windows().find(w => /iPhone Duo/.test(w.name()));
  if (!win) throw new Error('no Device Hub window showing an iPhone Duo');

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
  button.actions.byName('AXPress').perform();
  return `pressed "${want}"`;
}
