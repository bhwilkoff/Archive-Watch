---
name: smarttv-web-app
description: Smart-TV web patterns for Archive Watch's LG webOS / Samsung Tizen / VIDAA build — the additive tv.js+tv.css layer over the vanilla PWA (never a fork, no React so Norigin is out), the vanilla spatial-navigation engine and its misalignment-weight scoring, per-platform key/lifecycle/packaging shims only, Magic Remote pointer coexistence, .ipk/.wgt packaging from the shared root files, and the Node DOM-shim verification. Invoke before building or changing ANY web-TV surface, focus behavior, remote-key handling, or TV packaging.
---

# Smart-TV web app — focus, remotes, packaging

Binding spec: `docs/TV-DESIGN.md` §7. Strategy: **Decision 047**.
Backlog: `docs/TV-PLATFORM-BACKLOG.md` Phase 3.

One web build ships to **LG webOS, Samsung Tizen, and VIDAA/Titan/Zeasn**. They
are all HTML5 runtimes; the differences are key codes, lifecycle events and
packaging — nothing else.

## The layer is ADDITIVE — never a fork

`tv.js` + `tv.css` sit on top of the same `index.html` / `watch.js` /
`watch.css` the browser serves. No build step, no framework.

- `tv.js` **returns immediately** unless it detects a TV runtime, so
  phone/desktop pay nothing.
- every `tv.css` rule is scoped under `html.tv`, a class only `tv.js` adds — so
  a TV change **cannot** regress the phone viewer. Verify this mechanically:

```bash
# must print 0
grep -c '^[a-z*\[.#].*{' tv.css | ...   # every rule line contains html.tv
```

- Detection: UA match on `Tizen` / `Web0S|webOS` / `VIDAA`, **plus `?tv=1`** so
  the TV surface can be developed and screenshotted in a desktop browser.
  Without that escape hatch it could only ever be tested on a TV.

**React-based focus libraries (Norigin et al.) are out** — this codebase is
vanilla with no build step. The engine is ~200 lines and is ours by necessity.

## The spatial-navigation engine

Cards in this app are real `<a>` elements, so they are focusable without
touching a line of view code. The engine operates over
`a[href], button, input, select, [tabindex]:not([tabindex="-1"])`.

**Reachability filter** — a hidden view's cards stay in the DOM, so without
`el.closest('[hidden]')` plus a zero-size/`visibility` check the D-pad walks
into the previous screen.

**Scoring is the whole trick:**

```js
score = distanceAlongAxisOfTravel + misalignmentAcrossIt * MISALIGN_WEIGHT   // 3
```

The weight is what makes a grid feel like a grid: pressing Down from a card
lands on the card *below* it, not a nearer one three columns over. Compare
**edges, not centres** for the "is it in this direction" test — a tall
neighbour whose centre sits behind the cursor can still be the correct target.

**Always-focused invariant:** claim focus on boot, on `hashchange`, on return
from hidden, and via a `MutationObserver` (the first render is async on a
catalog fetch). Retry on a timer — views render after the hash changes.

**No dead ends:** if nothing lies in a direction, stay put. That is a deliberate
stop, not a strand — Back always still works.

## Per-platform shims — and NOTHING else branches

| Concern | webOS | Tizen |
|---|---|---|
| Back | `keydown` keyCode **461** | `tizenhwkey` event (+ keyCode **10009**) |
| Media keys | standard `keydown` | **must** `tizen.tvinputdevice.registerKey()` first, or they are never delivered |
| Lifecycle | `webOSLaunch` / `webOSRelaunch` | `visibilitychange` |
| Exit | `webOS.platformBack()` | `tizen.application.getCurrentApplication().exit()` |
| Pointer | Magic Remote cursor — **must coexist** | none |
| Package | `.ipk` via `ares-package` | signed `.wgt` via `tizen build-web` + `tizen package` |

Also accept **Escape (27)** and **Backspace (8)** as Back — aggregator and
white-label remotes use them, and getting Back wrong fails certification on
every platform.

**Magic Remote coexistence is not optional.** Hovering must move focus, so that
when the user puts the pointer down the D-pad continues from where they were
looking: two input models, **one** focus state.

## Packaging

`tv/build-tv-packages.sh` stages the SAME root files into each vendor layout
(`tv/webos/appinfo.json`, `tv/tizen/config.xml` + icons). There is no separate
TV codebase — **if you are editing a file under `tv/*/app/`, stop**; the change
belongs upstream in the shared app. Those dirs are gitignored.

Two packaging gotchas:
- **Exclude the service worker** from the package. A packaged TV app already
  stores its resources locally, and a stale SW inside the package shadows them.
  Strip the registration too, or the app registers a file that is not there.
- **Keep the Tizen signing certificate.** Samsung requires every update to be
  signed with the same one.

Bump `sw.js` `SHELL` on every web-TV change, or installs serve stale assets.

## Verification — Node DOM shim, not a headless browser

`tools/test_tv_focus.mjs` loads the **real** `tv.js` into a minimal DOM shim
(stubbed `getBoundingClientRect`, `focus()`, `activeElement`) and asserts:
initial focus, rail traversal, **column preservation on up/down**, reaching the
nav, the no-dead-end edge case, and both Back key codes.

This follows the project's documented web pattern: headless Chrome distorts
timers and `AbortSignal`, so exercising the real script in a shim is more
trustworthy than driving a browser.

```bash
node tools/test_tv_focus.mjs      # expects 10/10
```

Note `Object.defineProperty(global, 'navigator', …)` — modern Node makes
`navigator` a getter-only global, so a plain assignment throws.

## See also

- `docs/TV-DESIGN.md` §7 — the binding rules
- `web-platform-patterns` — service-worker versioning, view lifecycle, the
  sticky/scroll-snap CSS gotchas that still apply
- `web-catalog-data-layer` — where the TV build's catalog data comes from
