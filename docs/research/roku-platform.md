# Roku Platform — Engineering Research Brief

**Status:** research only. No decision logged, no code written.
**Date:** 2026-09-03
**Scope:** the ENGINEERING half of a research pair. Visual design guidance
lives in the companion design brief; this document touches design only where
a platform constraint forces a layout or interaction decision.
**Consumer:** the team evaluating Archive Watch as a first-class Roku channel,
alongside tvOS · iOS · macOS · Android/Google TV · Fire TV · web.

Every substantive claim carries its source URL. Where Roku's own documentation
is silent, stale, or self-contradictory, that is stated as such — this brief
distinguishes **confirmed**, **inferred**, and **must be measured on a device**,
because Decision 075's rule (controlled experiments over correlation) applies
harder here than on any platform we have shipped: Roku's docs are visibly out of
date in places, and two Roku-hosted pages contradict each other at least twice
(§7.7).

---

## 0. The executive summary, in seven facts

Read this section and you can make the go/no-go call. Everything after it is
the evidence.

1. **Roku is a full rewrite. There is no reuse.** BrightScript + SceneGraph XML
   shares nothing with Swift, Kotlin, or our vanilla-JS web layer. PARITY.md
   already records this correctly ("Roku | none — 0% reuse | 🔮 separate funded
   decision"). Nothing found in this research changes that number.

2. **The channel package must be ≤ 4 MB.** Certification item 4.11: *"The
   channel's file size is no larger than 4MB."*
   ([checklist](https://docs.roku.com/api/v1/published/channelcertificationchecklist/en/US/text))
   This is the single most architecture-defining constraint we found. It means
   **no bundled seed catalog of any kind** — not the 150 MB `catalog.sqlite`,
   not the 5 MB `seed.sqlite`, not a trimmed JSON. Decision 053's "first paint
   from the cached catalog, seed for first launch only" becomes "first paint is
   always a network fetch." There is no offline first run on Roku.

3. **There is no SQLite and no durable local storage worth the name.** The only
   documented durable per-app store is the registry, capped at **32 KB
   zlib-compressed, total, per app**
   ([roRegistry](https://developer.roku.com/docs/references/brightscript/components/roregistry.md)).
   `cachefs:` can hold multi-MB files across launches but Roku's own docs say
   the OS *"can evict the data at any time"* and a reboot always evicts
   ([file system](https://developer.roku.com/docs/developer-program/getting-started/architecture/file-system.md)).
   So: the catalog data plane is network-first with a best-effort cache, and
   favorites/progress live in 32 KB.

4. **We cannot port the resilient stream loader. At all.** The `Video` node's
   HTTP client is inside Roku's firmware. BrightScript cannot intercept it,
   cannot issue byte ranges for it, cannot proxy it (there is no local HTTP
   server API), and cannot even MITM it for debugging. Decisions 021 / 031 /
   034 / 077 have **no Roku equivalent** (§3.4). What remains is: set headers on
   the content node, let the firmware follow archive.org's 302, ask it to pin
   the redirect (`stickyredirects`), set `ignoreStreamErrors`, and build our own
   position-stagnation watchdog that re-issues `play` with `playStart`. That is
   a *coarse* restart, not a byte-exact resume. TV-DESIGN §5.6 already
   anticipated this: *"A platform whose player owns networking and cannot be
   made resilient (Roku) must have that regression recorded before work
   starts."* This brief is that record.

5. **Trick-play thumbnails are a certification item for content over 15
   minutes** — and the only mechanism available to a progressive-MP4 catalog is
   BIF files, which we would have to generate for ~20,000 titles
   ([trick mode](https://developer.roku.com/dev/docs/trick-mode)). Two
   Roku-hosted pages disagree on how hard the requirement is (§7.7); at minimum
   it is a new, large pipeline stage. **Bookmarking (resume) is separately
   required** for the same 15-minute threshold, stored ≥ 30 days
   ([bookmarking](https://developer.roku.com/dev/docs/bookmarking)).

6. **Sync is genuinely impossible, and not for the reason we assumed.** It is
   not that CloudKit and Drive are hard to reach. It is that Roku's
   certification criteria now *prohibit* the only flow that would work: *"Sign-up
   and sign-in workflows are prohibited from … utilizing off-device sign-up or
   sign-in mechanisms"*
   ([on-device authentication](https://developer.roku.com/docs/developer-program/authentication/on-device-authentication.md)).
   Google's OAuth device flow — the phone-completes-the-code pattern that would
   otherwise reach Drive App Data — is structurally the pattern Roku names and
   deprecates. Roku is a local-only island. See §4 for the honest framing.

7. **Our ECP harness is blocked by one on-device setting, and we found it.**
   `Settings → System → Advanced system settings → Control by mobile apps →
   Network access` defaults to **Limited** as of Roku OS 14.1, which 403s
   `keypress` / `keydown` / `keyup`. Set it to **Enabled**. `/launch` and
   `/query/device-info` are explicitly *not* gated, which is why discovery works
   while remote-driving does not
   ([ECP](https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md)).
   **This is the one owner action in this brief.**

---

## 1. SceneGraph architecture

### What it means for us

SceneGraph is closer to our web layer than to SwiftUI: a declarative XML tree of
nodes with typed fields, plus imperative BrightScript that reaches into it by
`id`. The mental model that transfers is **UIKit-with-XIBs**, not SwiftUI —
there is no diffing, no state-driven re-render. You mutate node fields; the
render thread draws.

The one thing with no analogue anywhere in our stack is the **rendezvous**: a
cross-thread field access costs *at least an order of magnitude more than a
direct access*
([data management](https://developer.roku.com/dev/docs/data-management)), and
**every dot in a chained expression is a separate rendezvous**
([threads](https://developer.roku.com/docs/developer-program/core-concepts/threads.md)).
This shapes the whole data layer: build node trees on a Task thread, hand them
over in ONE assignment.

### 1.1 The thread model — the load-bearing rules

Three thread layers
([threads](https://developer.roku.com/docs/developer-program/core-concepts/threads.md)):

| Thread | Created by | Job |
|---|---|---|
| **Main** | `Main()` / `RunUserInterface()` in `source/*.brs` | Creates `roSGScreen`, the Scene, then sits in a `wait()` message loop |
| **Render** | implicitly by `roSGScreen` | Draws everything. All renderable nodes are owned here |
| **Task** | `Task` node, `control = "RUN"` | Network, file I/O, JSON parse, anything that can block |

Hard rules, quoted:

- *"If the Render thread blocks execution, production apps will terminate after
  10 seconds; sideloaded apps will timeout in 3 seconds."* Note the asymmetry —
  **the sideloaded build is stricter than production**, so a dev build dies
  faster than the shipped one. That is a gift, not a nuisance.
- *"all BrightScript code executing on the render thread must execute within 16
  milliseconds"* to hold 60 fps
  ([optimization](https://developer.roku.com/dev/docs/optimization-techniques)).
- *"RokuOS imposes a limit of 100 concurrent threads per running instance of an
  app"*; exceeding it raises error `&h29`.
- **Node ownership**: nodes default to Render-thread ownership. A Task thread
  may create `Node` / `ContentNode` objects it owns exclusively — cheap to
  manipulate. *"the ownership of the node is changed to the thread that owns the
  node that contains the field"* the moment it is assigned in. Renderable nodes
  (`Group` and descendants) are **always** Render-owned regardless of who
  created them, so never build a `Group` on a Task thread.
- **The `m` clone trap**: *"On every setting of the Task node control field to
  RUN, a new thread is launched, and the Task node associative array is
  cloned."* Only primitives, nodes, arrays and AAs clone. A `roMessagePort`
  created in `init()` reaches only the *first* launched thread. This is a
  correctness bug, not a perf bug, and it bites when a Task node is reused.

**Diagnostics**: the SceneGraph debug console's `logrendezvous` reports whether
a rendezvous occurred and how long it took, in milliseconds. Wire this into the
first prototype, per our own debugging philosophy ("add observability before
trying another implementation").

### 1.2 Components, fields, observers, `m.top`

A SceneGraph component is one XML file in `components/`. Every `.xml` in that
directory is loaded at launch and registers a new node type
([hello world](https://developer.roku.com/docs/developer-program/getting-started/hello-world.md)).

Verified syntax, from Roku's own `videoplayer-channel` sample
([Item.xml](https://github.com/rokudev/videoplayer-channel/blob/master/components/Item.xml)):

```xml
<component name="Item" extends="Group">
  <children>
      <Poster id="poster" />
      <Label  id="label" font="font:MediumBoldSystemFont" horizAlign="center" />
  </children>
  <interface>
    <field id="width"       type="float" onChange="updateLayout"/>
    <field id="height"      type="float" onChange="updateLayout"/>
    <field id="itemContent" type="node"  onChange="itemContentChanged" />
  </interface>
  <script type="text/brightscript"><![CDATA[
      sub Init()
        m.Poster = m.top.findNode("poster")
      end sub
      sub itemContentChanged()
        m.Poster.uri = m.top.itemContent.HDPOSTERURL
      end sub
  ]]></script>
</component>
```

- `m.top` is the component's own root node — the *only* handle to its public
  interface. `m` is component-private state.
- `<interface><field>` declares the public API. `onChange` names a handler;
  `alwaysNotify="true"` fires even when the value is unchanged (Roku's own
  `Task.xml` sample uses this for command fields).
- **`observeField(field, callback)` vs `observeField(field, port)`**: the port
  form delivers an `roSGNodeEvent` to a message port; the callback form runs
  the handler inline. Roku's guidance for Task nodes is explicit — *"Rather than
  relying on onChange handlers (executed on render thread), use observeField()
  to send roSGNodeEvent messages to your port."*
  ([optimization](https://developer.roku.com/dev/docs/optimization-techniques))
- Since Roku OS 7.5 observer callbacks are **recursive, not deferred** — setting
  a field inside an observer runs the next observer immediately, nested
  ([events](https://developer.roku.com/docs/developer-program/core-concepts/handling-application-events.md)).
  Deep observer chains become deep call stacks.
- `observeFieldScoped` / `unobserveFieldScoped` scope the registration to the
  observing component. Plain `unobserveField` removes **every** observer on that
  field from every component. In pooled list-item components (§1.4) always use
  the scoped form. *(The scoped-vs-unscoped semantics above are widely
  documented in the community and consistent with the `ifSGNodeField` interface
  list, but we could not pin a verbatim Roku sentence — treat as high-confidence
  inference.)*
- `m.global` is a single Render-owned node. Every Task-thread touch of it is a
  rendezvous. Cache what you need locally.

Base `Node` interfaces
([Node](https://developer.roku.com/docs/references/scenegraph/node.md)):
`ifSGNodeChildren` (createChild, appendChild, appendChildren, removeChild,
getChild, getChildCount), `ifSGNodeField` (addField(s), setField(s),
getField**s**, observeField, observeFieldScoped, unobserveField),
`ifSGNodeFocus` (setFocus, hasFocus, isInFocusChain), `ifSGNodeDict` (findNode,
callFunc, clone, threadinfo). **Prefer `getFields()`/`setFields()`** — one
rendezvous instead of N.

### 1.3 Key handling and focus

`onKeyEvent(key as String, press as Boolean) as Boolean`
([events](https://developer.roku.com/docs/developer-program/core-concepts/handling-application-events.md)).
Keys: `up`, `down`, `left`, `right`, `OK`, `back`, `play`, `rewind`,
`fastforward`, `replay`, `options`. Return `true` to consume; `false` bubbles up
the focus chain. **`Home` is reserved** and cannot be handled.

This maps cleanly onto TV-DESIGN §3 (the focus contract) and §5.2 (the player
key contract) — the *verbs* are the same as Android TV and web-TV, the idiom is
the bubbling `onKeyEvent` chain. TV-DESIGN §1.7 ("Back is sacred") has a
concrete Roku expression: `Scene.backExitsScene` (default `true`) governs
whether Back from the root exits the channel.

Certification interacts here: item 9.1 — the **`*` (Options) button is reserved
during full-screen playback**; do not bind an overlay to it. And item 4.9 —
Instant Replay must rewind 10–25 s (the checklist's own recommended figure is
~20 s).

### 1.4 The node types a content app needs

| Node | Use in Archive Watch | Notes |
|---|---|---|
| `Scene` | the root; one per `roSGScreen` | fields: `backgroundURI`, `backgroundColor`, `dialog`, `backExitsScene`, `currentDesignResolution`, `palette` ([Scene](https://developer.roku.com/docs/references/scenegraph/scene.md)) |
| `Group` | plain container, manual coordinates | base class of every renderable node |
| `LayoutGroup` | stacks with automatic placement | `layoutDirection` (`horiz`/`vert`), `horizAlignment`, `vertAlignment`, `itemSpacings` ([LayoutGroup](https://developer.roku.com/docs/references/scenegraph/layout-group-nodes/layoutgroup.md)) |
| `RowList` | **Home shelves** | two-level ContentNode tree: root → row nodes → item nodes. `itemComponentName`, `numRows`, `rowItemSize`, `rowHeights`, `rowFocusAnimationStyle` (`floatingFocus`/`fixedFocus`/`fixedFocusWrap`), read-only `rowItemFocused` / `rowItemSelected` as `[row, item]` ([RowList](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/rowlist.md)) |
| `MarkupGrid` | **Browse / Search / filtered grids** | flat ContentNode children (or sectioned with `CONTENTTYPE="SECTION"`), `numColumns`, `numRows` (default 12), `itemSize`, `fixedLayout` ([MarkupGrid](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/markupgrid.md)) |
| `PosterGrid` / `LabelList` / `MarkupList` | simpler variants | all extend `ArrayGrid` |
| `Poster` | every tile, hero, backdrop | `uri`, `loadStatus` (`none`/`loading`/`ready`/`failed`), `loadWidth`/`loadHeight` (**set before `uri`**), `loadDisplayMode`, `loadingBitmapUri`, `failedBitmapUri`, `blendColor` ([Poster](https://developer.roku.com/docs/references/scenegraph/renderable-nodes/poster.md)) |
| `Label` / `MonospaceLabel` | all text | `MonospaceLabel` arrived in Roku OS 14.0 — use it for the runtime/timecode display, matching our "timecode not percent" rule |
| `Rectangle` | scrims, focus rings, dividers | cheaper than `Poster` — no bitmap is loaded at all |
| `Video` | the player | §3 |
| `Dialog` / `KeyboardDialog` / `StandardKeyboardDialog` | modals, Search entry | shown by assigning to `Scene.dialog` ([Scene](https://developer.roku.com/docs/references/scenegraph/scene.md)). `StandardKeyboardDialog` is the current one — it wraps `DynamicKeyboard` and adds voice entry; `KeyboardDialog` is legacy |
| `MiniKeyboard` / `DynamicKeyboard` | inline Search | TV-DESIGN §3.6 still binds: every browse path must work without typing |
| `BusySpinner` | loading states | cert 6.1 requires a loading indicator for anything over 3 s |
| `Task` | all networking | §2 |
| `ContentNode` | the data model | §2.4 |
| `Animation` / `Interpolator` | focus scale, transitions | field-attached, declarative |

`ArrayGrid` is the abstract base for every list/grid and carries the fields that
matter for large data: `content`, `itemSize`, `numRows`/`numColumns`,
`jumpToItem` / `animateToItem` (write-only), `itemFocused` / `itemSelected` /
`itemUnfocused` (read-only), `currFocusRow`
([ArrayGrid](https://developer.roku.com/docs/references/scenegraph/abstract-nodes/arraygrid.md)).
**There is no documented "load more on scroll" event** — you observe
`itemFocused` and append to the content node yourself when the index nears the
end. That is the paging idiom.

### 1.5 A real, minimal, sideloadable skeleton

This is Roku's own Hello World
([rokudev/hello-world](https://github.com/rokudev/hello-world)) reproduced
verbatim, with the manifest keys certification actually requires. It sideloads
and draws.

```
channel.zip                 ← the manifest MUST be at the ZIP ROOT
├── manifest
├── source/
│   └── Main.brs
├── components/
│   └── HelloWorld.xml
└── images/
    ├── channel-poster_fhd.png   540×405
    ├── channel-poster_hd.png    290×218
    ├── channel-poster_sd.png    214×144
    ├── splash-screen_fhd.jpg   1920×1080
    ├── splash-screen_hd.jpg    1280×720
    └── splash-screen_sd.jpg     720×480
```

**`manifest`** (no extension; the trailing newline matters to some tooling):

```ini
title=Archive Watch
major_version=1
minor_version=0
build_version=00001

mm_icon_focus_fhd=pkg:/images/channel-poster_fhd.png
mm_icon_focus_hd=pkg:/images/channel-poster_hd.png
mm_icon_focus_sd=pkg:/images/channel-poster_sd.png

splash_screen_fhd=pkg:/images/splash-screen_fhd.jpg
splash_screen_hd=pkg:/images/splash-screen_hd.jpg
splash_screen_sd=pkg:/images/splash-screen_sd.jpg
splash_color=#0A0A0A
splash_min_time=1

ui_resolutions=hd,fhd
rsg_version=1.3
supports_input_launch=1
run_as_process=1
```

**`source/Main.brs`**:

```brightscript
sub Main()
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)

    scene = screen.CreateScene("HelloWorld")   ' loads components/HelloWorld.xml
    screen.show()

    while(true)
        msg = wait(0, m.port)
        if type(msg) = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        end if
    end while
end sub
```

**`components/HelloWorld.xml`**:

```xml
<?xml version="1.0" encoding="utf-8" ?>
<component name="HelloWorld" extends="Scene">
  <children>
      <Label id="myLabel" text="Hello World!" width="1280" height="720"
             horizAlign="center" vertAlign="center" />
  </children>
  <script type="text/brightscript"><![CDATA[
    function init()
      m.top.setFocus(true)
      m.myLabel = m.top.findNode("myLabel")
      m.myLabel.font.size = 92
      m.myLabel.color = "0x72D7EEFF"
    end function
  ]]></script>
</component>
```

Sideload it (§5.1):

```bash
zip -r channel.zip manifest source components images     # NOT the parent folder
curl --user rokudev:$ROKU_PW --anyauth -sS \
  -F "mysubmit=Replace" -F "archive=@channel.zip" -F "passwd=" \
  "http://$ROKU_IP/plugin_install"
```

**Manifest keys worth knowing beyond the minimum**
([manifest](https://developer.roku.com/docs/developer-program/getting-started/architecture/channel-manifest.md)):
`rsg_version` — Roku's docs state it **must be `1.3` by October 1, 2026 for
certification**, and OS 14.5 already sunset RSG 1.1. `supports_input_launch=1`
is **required** to receive a deep link while the app is already running.
`run_as_process=1` enables Instant Resume and some debug tooling.
`splash_rsg_optimization=1` removes the black flash between splash and first
frame. `bs_const` defines compile-time constants, which RokuCommunity tooling
uses for debug/release variants. `network_not_required=1` — deliberately NOT set
for us; Archive Watch cannot function offline on Roku (§0.2).

---

## 2. The data layer

### What it means for us

**The web data plane is the right shape to reuse, but the wrong artifact to
reuse as-is.** The index+shards *architecture* — a slim index plus lazily
fetched per-item detail — maps exactly onto Roku's Task-node/lazy-fetch model,
and Roku's own guidance says so: *"implement server side filtering, data
optimization, or paging to reduce the amount of data that is fetched"*
([optimization](https://developer.roku.com/dev/docs/optimization-techniques)).
But the specific 6.2 MB `catalog-index.json` is a risky single `ParseJson` on a
1 GB device, and the ContentNode tree it would feed is a second, larger copy of
the same data.

The honest recommendation is a **third artifact from the same pipeline**: Roku
shards, generated alongside `catalog-index.json` and `details/*.json` by the
existing Python tools. Details in §8.

### 2.1 Fetching: `roUrlTransfer` on a Task node

`roUrlTransfer` implements `ifUrlTransfer` + `ifHttpAgent`
([ifUrlTransfer](https://developer.roku.com/docs/references/brightscript/interfaces/ifurltransfer.md),
[ifHttpAgent](https://developer.roku.com/docs/references/brightscript/interfaces/ifhttpagent.md)).

- Sync: `GetToString()`, `GetToFile(path)`, `PostFromString()`, `Head()`.
- Async: `AsyncGetToString()`, `AsyncGetToFile(path)`, `AsyncCancel()` — deliver
  an `roUrlEvent` to a message port. **One async operation per object**:
  *"Each roUrlTransfer object can perform only one asynchronous operation at one
  time."* Correlate responses by matching `GetIdentity()` against the event's
  `GetSourceIdentity()`.
- **It must run on a Task thread.** A sync `GetToString()` on the render thread
  is exactly the 3-second sideload kill.
- Headers: `AddHeader(name, value)`, `SetHeaders(aa)`. Names beginning
  `x-roku-reserved-` are blocked (except `x-roku-reserved-dev-id`, whose value
  is overwritten by the OS). **No documented restriction on `Range`** — so
  ranged reads of a static file are probably available, but this is *unverified*
  and matters if we ever want a binary index (§8, Option C).
- `EnableEncodings(true)` — *"Enables gzip encoding of transfers."* **Use it.**
  Our 6.2 MB index gzips to 2.0 MB; a slim 6-column variant to 1.3 MB. This is
  free bandwidth and Pages already serves gzip.
- `EnableResume(true)` — *"Enables automatic resumption of AsyncGetToFile and
  GetToFile requests."* Relevant for a catalog download over a flaky link. It
  does **not** apply to video.
- `SetMinimumTransferRate(bytes_per_second, period_in_seconds)` — aborts a
  transfer that stalls below a floor. The closest thing to a timeout knob.
- **There is no documented timeout setter.** Community reports describe a fixed
  ~30 s with error `-28`. Treat as unconfirmed; design retries around
  `SetMinimumTransferRate` and our own timers.
- **Redirects are always followed** for 301/302/303/307 and cannot be disabled
  ([community, corroborated by the `StreamStickyHttpRedirects` doc entry](https://developer.roku.com/docs/developer-program/getting-started/architecture/content-metadata.md)).
  Good for archive.org.
- HTTPS: every Roku example calls
  `SetCertificatesFile("common:/certs/ca-bundle.crt")` plus
  `InitClientCertificates()`. Whether a plain server-authenticated HTTPS GET
  works without it is **not stated**; assume you must call it.
- **No built-in retry.** Ours to write.

### 2.2 Task nodes in practice

```xml
<component name="CatalogTask" extends="Task">
  <interface>
    <field id="url"    type="string" />
    <field id="result" type="node" alwaysNotify="true" />
    <field id="error"  type="string" alwaysNotify="true" />
  </interface>
  <script type="text/brightscript"><![CDATA[
    sub init()
      m.top.functionName = "run"
    end sub

    sub run()
      xfer = CreateObject("roUrlTransfer")
      xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
      xfer.InitClientCertificates()
      xfer.EnableEncodings(true)
      xfer.SetUrl(m.top.url)
      body = xfer.GetToString()          ' safe: this is a Task thread
      if body = invalid or body = "" then
        m.top.error = "fetch failed" : return
      end if
      data = ParseJson(body)             ' also safe here, never on Render
      root = CreateObject("roSGNode", "ContentNode")   ' Task-owned, cheap
      ' … build the WHOLE subtree here …
      m.top.result = root                ' ONE rendezvous, ownership transfers
    end sub
  ]]></script>
</component>
```

The pattern that matters is the last two lines. Roku states it directly: *"A
Task thread should use a single dot reference at the end to set the entire
ContentNode and its subtree rather than setting the node first and then
operating on it with multiple dot operations."*
([data management](https://developer.roku.com/dev/docs/data-management))

Task reuse: Roku recommends *"persistent, reusable Task nodes over creating new
ones repeatedly"*, driven by observed input fields — but remember the `m` clone
trap (§1.1). The 100-thread cap is the hard ceiling.

### 2.3 `ParseJson` — the number we could not find

- Signature `ParseJson(json as String, flags = "" as String)`. Flags: `"i"` for
  case-insensitive AAs (later duplicate keys silently overwrite), `"d"`
  (OS 14.6+) for double-precision numbers
  ([global utility functions](https://developer.roku.com/docs/references/brightscript/language/global-utility-functions.md)).
- **The only documented limit is nesting depth: 256 levels.** No byte cap is
  documented.
- **There is no streaming or chunked JSON parser on Roku.** A 6.2 MB file is one
  synchronous call.
- Roku's own warning: `FormatJSON` is *"expensive, especially when operating on
  a large associative array"*, and *"the converted associative array consumes
  more memory than the original string"*
  ([optimization](https://developer.roku.com/dev/docs/optimization-techniques)).
  Elsewhere: *"accessing a 5.6MB AA can take hundreds of milliseconds."*
- Roku OS 15.0 shipped *"improved JSON parsing with lower memory overhead"* and
  **data-transfer-by-reference APIs** that move data in and out of fields
  without copying
  ([release notes](https://developer.roku.com/dev/docs/release-notes)). If we
  build this, target OS 15 APIs from day one.

**No wall-clock benchmark exists in the docs for any payload size.** This is
measurement #1 in §9.

### 2.4 ContentNode and how lists bind

`ContentNode` is the data vehicle. The decisive property: *"ContentNode objects
are passed by reference in the application, while associative array objects are
copied."* Roku's rule of thumb — AAs for small shallow structs, ContentNode
trees for anything large or nested
([ContentNode](https://developer.roku.com/dev/docs/contentnode),
[data management](https://developer.roku.com/dev/docs/data-management)).

The standard content-meta-data field names our tiles would use
([content metadata](https://developer.roku.com/docs/developer-program/getting-started/architecture/content-metadata.md)):
`Title`, `Description`, `HDPosterUrl` / `FHDPosterUrl` / `SDPosterUrl`,
`ReleaseDate`, `Length`, `Rating`, `StarRating`, `ContentType`, `Categories`,
`Actors`, `Directors`, `ShortDescriptionLine1/2` — plus the playback fields in
§3.2. Custom fields can be added with `addFields`.

Binding: assign a root ContentNode to `RowList.content` (two levels: rows, then
items) or `MarkupGrid.content` (one level). Both instantiate
`itemComponentName` *"on demand for each visible item"* — a recycler pool. The
item component receives `itemContent`, `focusPercent`, `itemHasFocus`, `index`,
`width`, `height` as interface fields, in a defined order.

**The recycling trap** (inferred, high confidence, worth a prototype test):
because instances are pooled and re-pointed at new `itemContent`, any observer a
component registers in `init()` on something *other than its own fields* — a
shared parent, `m.global` — persists across every item that slot ever shows.
Use `observeFieldScoped` and tear down explicitly. This is the same defect class
as our stacked-observer bugs on Apple.

**Node creation is not free.** A community benchmark measured ~92 ms to create
2,000 plain `ContentNode`s, rising to ~649 ms and ~1,324 ms for subtypes with
custom fields, against 3–4 ms for the equivalent plain arrays/AAs. *(Community
source, not first-party — directional only, but the direction is clear: keep
per-item ContentNodes plain and few.)*

### 2.5 Memory and images

**Device RAM**
([hardware](https://developer.roku.com/dev/docs/hardware)): 512 MB on the
original Streaming Stick, Roku Express and several entry TV chassis (720p UI
cap); **1 GB on the Streaming Stick 4K / 4K+ (3820X/3821X), Streaming Stick
Plus, Express 4K+ and most current 4K Roku TVs**; 2 GB on Roku Ultra and premium
chassis. All render through OpenGL ES 2.0.

**The app's own ceiling is not published as a table.** Query it at runtime:
`roAppMemoryMonitor.GetChannelMemoryLimit()` (OS 13.0+) and
`GetChannelAvailableMemory()` (OS 12.5+). Low-memory events fire at **80 / 85 /
90 / 95 %** of the app limit (OS 15.2)
([roAppMemoryMonitor](https://developer.roku.com/dev/docs/roappmemorymonitor)).
`roDeviceInfo.GetGeneralMemoryLevel()` returns `normal` / `low` / `critical`.
And the consequence is blunt: *"Apps exceeding RAM limits are killed before
noticeable performance degradation occurs."*
([memory management](https://developer.roku.com/dev/docs/memory-management))

**Roku states that integrating `roAppMemoryMonitor` becomes an app-certification
requirement starting October 1, 2026.** Build it in from the first commit.

**Texture memory** is a separate budget and is pure pixel area: *width × height ×
4 bytes*, regardless of file compression. A 1920×1080 poster costs ~8.3 MB
decoded; a 200×200 tile ~0.16 MB. Reusing the identical URL across nodes does
not multiply the cost. Symptom of exhaustion: *"flickering images or slow content
loading, as bitmaps will be constantly unloaded and reloaded."* Measure with the
debug console's `loaded_textures`.

**Direct consequence for our posters.** We currently hand Apple and Android TMDb
`w500`/`w780` URLs. On Roku, request the smallest size the tile actually draws
and set `loadWidth`/`loadHeight` **before** `uri`. Roku's guidance: *"load images
either identical to, or close to, the intended target screen dimensions."* Note
also Decision 097's rule (never reshape the art) has a clean Roku expression —
`loadDisplayMode="scaleToFit"` inside a fixed-aspect box, never `scaleToFill` /
`scaleToZoom`, on a catalog where 14 % of art is not 2:3.

**Whether Roku persists a disk cache of remote images across launches is not
documented.** It documents an in-memory texture cache that evicts offscreen
bitmaps. Assume cold re-fetch on every launch until measured.

### 2.6 Local storage — the whole truth

([file system](https://developer.roku.com/docs/developer-program/getting-started/architecture/file-system.md))

| Filesystem | R/W | Survives app exit | Survives reboot | Notes |
|---|---|---|---|---|
| `pkg:` | read-only | — | — | the ≤ 4 MB package |
| `tmp:` | read/write | **no** | no | RAM-backed, cleared on exit, not auto-cleaned during a session |
| `cachefs:` | read/write | usually | **no** | *"The OS can evict the data at any time"*; a reboot always evicts. **No documented quota.** Does not count against app memory |
| `common:` | read-only | — | — | only `common:/certs/ca-bundle.crt` |
| `ext1:`–`ext9:` | read-only | — | — | USB, model-dependent |
| Registry | read/write | yes | yes | **32 KB zlib-compressed, per app, total** |

So a catalog cache goes in `cachefs:` and **must** be treated as a miss-by-default
optimization — Roku's docs say to check the file exists before trusting it. There
is no offline mode and no seed. Combined with the 4 MB package cap, **Roku is the
only Archive Watch client that cannot show a single title without a network.**

---

## 3. Video playback

### What it means for us

This is where Roku costs us the most. Our playback resilience is the single most
iterated-upon subsystem in this project — Decisions 021, 031, 034, 056, 077, and
the entire `resilient-media-streaming` skill. **None of it ports.** The `Video`
node owns the socket, and BrightScript is on the wrong side of it.

What we get instead is a firmware player that is genuinely good at progressive
MP4, follows archive.org's 302 automatically, can be asked to pin the redirect,
and tells us when it stalls. What we lose is byte-exact resume, node failover,
and any ability to see or influence *why* a stream died.

### 3.1 The `Video` node
([Video](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md))

- `content` (ContentNode), `control` (`play`/`stop`/`pause`/`resume`/`replay`/
  `prebuffer`/`skipcontent`), `state` (read-only: `none`/`buffering`/`playing`/
  `paused`/`stopping`/`stopped`/`finished`/`error`).
- `position` and `duration` are **read-only**; `seek` is **write-only**.
  `notificationInterval` (default 0.5 s) sets how often `position` notifies.
- `seekMode`: `"default"` (nearest sync frame) or `"accurate"`.
- Errors: `errorCode` — `0` none, `-1` network, `-2` connection timed out, `-3`
  unknown, `-4` empty list, `-5` media error, `-6` DRM. Plus `errorMsg`,
  `errorStr`, and `errorInfo` (an AA with `clipId`, `ignored`, `source`,
  `category`, `errcode`, `dbgmsg`, `drmerrcode`).
  **Note what this costs us:** connection reset, DNS failure and redirect
  exhaustion all collapse into `-1`. We will not be able to tell an
  archive.org node failure from a Wi-Fi drop.
- Telemetry: `streamInfo` (`isUnderrun`, `isResume`, `measuredBItrate`,
  `streamBitrate`, `streamUrl`), `bufferingStatus` (`percentage`, `isUnderrun`,
  `prebufferDone`, `actualStart`), `timeToStartStreaming`, `videoFormat`,
  `audioFormat`. `streamingSegment` / `downloadedSegment` are **DASH/HLS only** —
  no segment telemetry for progressive MP4.
- Trick play: `enableTrickPlay` (default true), `trickPlayBar`, `bifDisplay`.
- Captions: `globalCaptionMode`, `subtitleTrack`, `availableSubtitleTracks`,
  `captionStyle`, `suppressCaptions`.

### 3.2 Content meta-data for a progressive MP4
([content metadata](https://developer.roku.com/docs/developer-program/getting-started/architecture/content-metadata.md))

| Field | Value for us |
|---|---|
| `url` | the archive.org `/download/<id>/<file>` URL |
| `streamFormat` | **`"mp4"`** (also covers `.mov` / `.m4v`) |
| `playStart` | seconds — **this is our resume mechanism** |
| `length` | runtime in seconds |
| `httpHeaders` | array of `"name:value"` strings; **setting it replaces all agent headers** |
| `httpCertificatesFile`, `httpSendClientCertificate`, `httpCookies` | TLS/cookie config |
| `ignoreStreamErrors` | *"the media player will not stop playback when it runs into a streaming related error"* — our only built-in leniency knob |
| `Streams` / `StreamUrls`+`StreamBitrates`+`StreamQualities` | multi-variant array, *"recommended for non-adaptive video (such as MP4 progressive download) only"* |
| `StreamStickyHttpRedirects` | *"Array of Boolean values indicating if the HTTP endpoint should be sticky and not subject to change on subsequent requests. Default is false."* |
| `cdnConfig` | `URLFilter` / `Priority` / `Weight` / `ServiceLocation` — real failover ordering, but described entirely in manifest-base-URL (DASH/HLS) terms |

**On `Streams` as a failover array — the answer is "probably not, and nobody
documents it."** Every description frames `Streams` as a *bitrate ladder*, chosen
by bandwidth. Nothing states that a hard connection failure on `Streams[0]`
causes the player to try `Streams[1]`. `cdnConfig` *does* express priority-ordered
failover, but only for manifest base URLs, and one community report describes
devices sticking to a chosen source rather than failing over when the download is
blocked. **We could not confirm `cdnConfig` applies to a bare progressive URL at
all.** This is measurement #3 in §9, and if it works it is the single largest
recoverable piece of Decision 034.

**`StreamStickyHttpRedirects` is the closest thing to Decision 031's node
pinning** — but it is a boolean hint to the firmware, not a handle. We cannot
see which storage node was chosen (no field exposes the resolved host), cannot
force a specific one, and cannot drop a bad one.

### 3.3 Codecs and containers
([streaming specifications](https://developer.roku.com/dev/docs/media))

| Codec | Max res | Profile / level | Max bitrate | Containers |
|---|---|---|---|---|
| H.264 / AVC | 1920×1080 | main, high · 4.1, 4.2 | **10 Mbps** | MP4/MOV/M4V, MKV/WebM |
| HEVC / H.265 | 3840×2160 | main, main10 · 4.1, 5.0, 5.1 | 40 Mbps | MP4/MOV/M4V, MKV/WebM |
| AV1 | 7680×4320 | main, main10 | 40 Mbps | **DASH only** |

Audio in MP4: AAC, AC3, EAC3, AC4, ALAC, MP3, PCM.

Our catalog is overwhelmingly H.264 SD/low-bitrate, so the 10 Mbps H.264 ceiling
is unlikely to bind — but note it is *lower* than some of our BluRay-sourced
derivatives, and certification item 9.17 separately requires the channel to be
able to serve **down to 800 kbps**. That interacts with our existing per-item
derivative picker.

**Two doc inconsistencies, flagged**: a search-cached version of the same page
gave HEVC 25 Mbps (vs 40 in the direct fetch) and listed VP9 support that the
direct fetch does not contain. **Re-verify the live page before finalizing any
encode spec.**

**The moov atom / faststart question is completely undocumented.** Roku says
nothing about moov placement for progressive MP4. Given a plain HTTP GET with a
tail-placed moov forces the player to read to EOF before it can start, and
certification 3.6 gives us **8 seconds to first frame**, treat faststart as a
hard requirement of *our* pipeline. We already run a `faststart-derivatives`
workflow; on Roku it stops being an optimization and becomes a gate.

### 3.4 The HTTP layer — what is impossible, stated plainly

**Impossible, confirmed:**

- **Intercepting or proxying the `Video` node's requests.** The transport lives
  in firmware. Corroborating evidence: even a developer MITM proxy cannot see it
  — *"network calls from the Roku OS itself and some native video player/RAF
  calls cannot be configured to use the certificate"*
  ([Proxying network requests](https://briandunnington.github.io/proxying_network_requests)).
  If we cannot inspect it, we certainly cannot intervene in it.
- **Byte-range resume of an in-flight stream.** The only resume is
  `content.playStart = <seconds>` + `control = "play"`, which is a brand-new
  request that discards whatever was buffered.
- **A local proxy server.** There is no local HTTP server API, and no content
  meta-data field points the player at one. `roStreamSocket` gives raw TCP for
  our *own* traffic; it cannot capture the player's.
- **Knowing which archive.org storage node is in use.** No field exposes it.

**Possible, confirmed:**

- Custom request headers via `httpHeaders`. *(Whether they survive the 302 hop
  is unconfirmed — measurement #4.)*
- Automatic 302 following (always on, cannot be disabled).
- Redirect pinning via `StreamStickyHttpRedirects`.
- `ignoreStreamErrors` to survive transient errors without a hard stop.
- Full observation of `state`, `bufferingStatus`, `position`, `streamInfo`.

**Undocumented and critical:** whether the firmware automatically retries or
reconnects after a mid-stream connection reset, and with what backoff. Roku's
docs are silent. Given archive.org's documented idle-reset behaviour is the
*whole reason* our Apple loader exists, **this is the single most important
measurement before committing to a Roku build** (measurement #2, §9).

### 3.5 The stall strategy we can actually build

1. Set `notificationInterval = 1` and observe `state`, `position`,
   `bufferingStatus`.
2. Detect a stall ourselves: `position` fails to advance while `state` is
   `buffering` beyond a threshold we choose. Roku offers no "stalled for N
   seconds" signal.
3. Recover: re-resolve the URL (our own pipeline can hand Roku a
   pre-resolved node URL rather than the redirecting `/download/` URL), set
   `content.playStart = lastKnownPosition`, `control = "play"`.
4. Set `ignoreStreamErrors = true` so transient errors don't hard-stop first.
5. Use `control = "prebuffer"` from the Detail screen so buffering starts while
   the viewer reads the synopsis — Roku's documented Fast Video Start pattern
   ([fast video start](https://developer.roku.com/docs/developer-program/media-playback/fast-video-start.md)),
   and certification 6.4 explicitly recommends it.

Note what step 3 costs: every recovery is a visible re-buffer from a cold
connection. On Apple we resume mid-connection at a byte offset and the viewer
sees nothing. **The Roku experience under a flaky archive.org node will be
measurably worse than every other platform we ship, and no amount of client work
closes that gap.** Decision 077's "fall back to a copy that can play" *does*
port, since it operates at the URL level.

### 3.6 Captions

- Side-loaded external subtitle files: the documented formats are **SRT and
  TTML**. WebVTT support is described as *"if embedded in HLS streams or
  manifests"* — i.e. **not confirmed for a side-loaded file against a
  progressive MP4** ([closed caption](https://developer.roku.com/dev/docs/closed-caption)).
  Our pipeline emits WebVTT (`vttURL`) for 404 of 411 SRT sources; **on Roku we
  would convert back to SRT**, or publish both. That is a cheap pipeline change,
  not a blocker — but it is the opposite direction from every other platform.
- `subtitleConfig` selects a track explicitly; the docs warn *"Do not use the
  SubtitleConfig property unless you are overriding the caption track that is
  automatically selected based on user caption language preference."*
- **Certification 4.8 requires following the user's global caption settings** and
  supporting On / Off / On-instant-replay (/ On-mute on Roku TVs), with VOD
  captions synchronised to audio. `globalCaptionMode` is how we read the system
  preference. Our own caption UI must defer to it, not replace it.
- Our live-caption engine (Decisions 058/068/072) has **no Roku analogue** —
  there is no on-device speech API. Roku sees only what the pipeline published:
  ~15.9 % of visible titles carry a subtitle track. That is the honest number to
  put in PARITY.

### 3.7 Trick play — a real, large pipeline cost

- `enableTrickPlay` gates scrubbing. `trickPlayBar` / `bifDisplay` are the
  built-in UI, per TV-DESIGN §5.1 (never build a custom scrubber).
- **BIF is the only scene-thumbnail route for progressive MP4.** The modern
  alternative (HLS/DASH standard thumbnail tiles) is manifest-driven and does
  not apply to us. BIF files are generated with Roku's BIF tool and referenced
  by HD/SD URL in content meta-data
  ([trick mode](https://developer.roku.com/dev/docs/trick-mode)).
- **The requirement, and the contradiction.** The trick-mode page states plainly:
  *"Apps must display thumbnails during trick play for VOD content longer than
  15 minutes to pass certification."* The certification checklist's item 9.8 is
  softer — it accepts *either* uniform positional increments *or* a BIF preview
  thumbnail. **These two Roku-hosted pages disagree.** Plan for the stricter
  reading: a BIF-generation stage across every title over 15 minutes. On our
  catalog that is roughly 20,000 items of ffmpeg work, sitting alongside the
  existing cover-generation pipeline (Decision 023) — feasible, and not small.
- Checklist 9.9 requires **exactly three FF/RW speed tiers: 1×/2×/4×**. Note
  this is trick-play scrub speed, not our playback-rate picker.
- **Whether seeking a progressive MP4 uses HTTP Range is undocumented.** Every
  competent player does; Roku does not say. Measurable with a LAN proxy.

### 3.8 Ads

The Roku Advertising Framework is scoped to ad-supported apps. Archive Watch is
free and ad-free, so **RAF integration is not required**
([certification](https://developer.roku.com/docs/developer-program/certification/certification.md)).
Confirm this holds if monetisation ever changes — the requirement triggers on
the presence of ads, not the app category.

---

## 4. Persistence and identity

### What it means for us

**Roku cannot join any of our sync islands, and the blocker is policy, not
plumbing.** This is the section most likely to change someone's mind about the
port, so it is worth being precise about *why*.

### 4.1 The registry: 32 KB, and that is the whole budget

*"The maximum size of each zlib-compressed application registry is 32K bytes"*
([roRegistry](https://developer.roku.com/docs/references/brightscript/components/roregistry.md)),
restated as *"Each app has access to only 32kb of registry space"*
([file system](https://developer.roku.com/docs/developer-program/getting-started/architecture/file-system.md)).
`roRegistry.GetSpaceAvailable()` reports the remainder.

API: `roRegistrySection` with `Read`/`ReadMulti`/`Write`/`WriteMulti`/`Delete`/
`Exists`/`GetKeyList`/`Flush`. **`Flush()` is required** — *"Does not guarantee a
commit to non-volatile storage until an explicit Flush() is done"* — and *"all
writes between calls to it are atomic"*
([ifRegistrySection](https://developer.roku.com/docs/references/brightscript/interfaces/ifregistrysection.md)).

Survives app exit and reboot; removed on uninstall or factory reset. One
signing-key subtlety: publishing an update with the **same signing key**
preserves registry data; a new key effectively resets it (§6.2).

**Sizing the budget honestly.** 32 KB compressed. A watch-progress entry
(`archiveID` + seconds + timestamp) is ~40 bytes raw; a favorite ~25. Storing
everything as one packed JSON blob per section, we can comfortably hold on the
order of a few hundred favorites and a few hundred progress records — which is
enough, provided we **cap and LRU-evict**, and never assume unbounded history.
Certification 4.10 only requires bookmarks be retained 30 days, so a rolling
window is compliant. Roku's bookmarking doc explicitly blesses the registry as
the no-backend path
([bookmarking](https://developer.roku.com/dev/docs/bookmarking)).

Decision 078's durable watch *history* (everCompleted, playCount,
firstWatchedAt, unioned across devices) will not fit and will not sync. Roku
gets progress + favorites, device-local, bounded.

### 4.2 There is no per-user identifier

- `GetChannelClientId()` — *"a unique identifier for the device… persistent and
  cannot be reset"*, and *"different across apps"*. Per-device **and**
  per-channel. Three Rokus in a house are three identities.
- `GetRIDA()` — the advertising ID; becomes a rotating temporary value under
  Limit Ad Tracking, and using an ad ID as an app identity key is a policy
  misuse.
- `GetDeviceUniqueId()` — **dead**: *"Returns a string of 12 zeroes."*
- `roChannelStore.GetUserData()` returns the user's Roku account email (and
  more) behind a native Share / Don't Share dialog — genuinely on-device, and
  the only account-scoped thing available. It is useless to us without a
  backend.

([ifDeviceInfo](https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md),
[ifChannelStore](https://developer.roku.com/docs/references/brightscript/interfaces/ifchannelstore.md))

### 4.3 Why sync is blocked — the exact sentence

Roku's on-device authentication requirement:

> *"Apps that include authentication must complete account sign-ups and sign-ins
> on the device using on-device authentication to pass certification. Sign-up and
> sign-in workflows are prohibited from including external webpages, links to
> off-device promotional or marketing materials, or utilizing off-device sign-up
> or sign-in mechanisms."*
> — [On-device authentication](https://developer.roku.com/docs/developer-program/authentication/on-device-authentication.md)

and, naming the pattern:

> *"on-device authentication deprecates the 'rendezvous' registration method.
> With this method, a customer was shown a registration code on their device and
> had to enter it on an external website."*

**CloudKit** is out regardless of policy: CloudKit Web Services needs a
`ckWebAuthToken` obtained through a browser redirect, expiring in 30 minutes (or
two weeks with "keep me signed in"). A Roku channel has no browser and no
webview. Dead end, twice over.

**Google Drive App Data** is *technically* reachable. Google's OAuth 2.0 device
authorization grant needs no browser on the device, and — verified — the allowed
scope list for "TVs and Limited-Input devices" **includes
`https://www.googleapis.com/auth/drive.appdata`**, exactly the scope our Android
and web clients use
([Google: OAuth for TV and limited-input devices](https://developers.google.com/identity/protocols/oauth2/limited-input-device)).
Refresh tokens are issued, so background sync would work. `roUrlTransfer` alone
is sufficient to implement it.

**But it is structurally the deprecated rendezvous pattern.** Roku's docs do not
name Google's flow, so this is not a settled fact — it is a strong reading of a
broad prohibition ("any other 1st or 3rd-party off-device… activation
mechanism"). The honest position: **do not plan on it clearing certification for
a public channel.** If sync ever becomes non-negotiable, ask Roku developer
support directly rather than building it and finding out at review.

### 4.4 What Roku offers instead

**Continue Watching** is Roku-account-scoped and genuinely cross-device — but it
is a *push target*, not a store. Roku is explicit: *"Roku does not maintain
bookmarks because content may be watched across multiple platforms."* It is a
REST API (`userdata.sr.roku.com/user-data/v1/content/continueWatching`) whose
auth headers the OS populates, it is gated behind partner approval, it requires
a working search feed + deep linking first, and it becomes *mandatory* only
above 5 M streaming hours/month in the US (1 M outside the US from 2026-10-01)
([continue watching](https://developer.roku.com/docs/developer-program/discovery/continue-watching.md)).
It presupposes a sync source of truth we would not have.

**Roku Search** takes a hosted JSON content feed and gives us discoverability +
voice search. It carries no per-user state in either direction. Not strictly
required for certification (items 8.2–8.4 are conditioned on *"If participating
in Roku Search"*), but for a 27,000-title public-domain catalog whose entire
value is discovery, skipping it would be perverse. Spec:
[search feed](https://developer.roku.com/docs/specs/search/search-feed.md) —
pagination via `nextPageUrl`, *"If the search feed is 20MB or larger, pagination
should be used"*, 250 MB per page, ETag/Last-Modified respected, up to 24 h to
propagate.

### 4.5 The honest PARITY row

| Verb | Roku | Reason |
|---|---|---|
| Favorites | ✅ local, capped | 32 KB registry |
| Watch progress / Continue Watching | ✅ local, capped, ≥30 d | cert 4.10; registry |
| Full watch history (D078) | 🚫 | will not fit in 32 KB |
| Playlists | ⏳ local, small | registry budget |
| Cross-device sync | 🚫 | no per-user id; off-device sign-in prohibited by cert |
| Downloads / offline | 🚫 | ≤4 MB package, evictable `cachefs:`, no durable store |
| Live captions | 🚫 | no on-device speech API |
| SharePlay / Watch Together | 🚫 | Apple-only framework |
| Clip Studio / Creation Studio | 🚫 | TV-DESIGN §2 — never on a TV build |

---

## 5. Deployment, tooling, and automation

### What it means for us

**Roku automates from a Mac shell about as well as Android does, and better than
tvOS.** Everything is HTTP: sideload, screenshot, remote keys, deep link, device
query. Logs stream over plain TCP. There is a real static-analysis CLI and a
real on-device test runner. The harness we would build looks like
`tools/verify_tv_focus.sh` with `curl` where `adb` used to be — with one
prerequisite the owner must flip on the device.

### 5.1 Developer mode and sideloading

Enable dev mode with the remote: *"press home three times, up twice, and then
right, left, right, left, right"*, set the `rokudev` password, device reboots
([developer setup](https://developer.roku.com/dev/docs/developer-setup)).

The developer web server lives at `http://<device-ip>/` behind **HTTP Digest
auth**, user `rokudev`, realm `rokudev`.

```bash
# Replace-then-Install is the robust order (roku-deploy does exactly this)
curl --user rokudev:$ROKU_PW --anyauth -sS \
  -F "mysubmit=Replace" -F "archive=@channel.zip" -F "passwd=" \
  "http://$ROKU_IP/plugin_install"

# first-ever install
curl --user rokudev:$ROKU_PW --anyauth -sS \
  -F "mysubmit=Install" -F "archive=@channel.zip" -F "passwd=" \
  "http://$ROKU_IP/plugin_install"

# remove
curl --user rokudev:$ROKU_PW --anyauth -sS \
  -F "mysubmit=Delete" -F "archive=" -F "passwd=" \
  "http://$ROKU_IP/plugin_install"
```

Optional fields on the same POST: `remotedebug=1`,
`remotedebug_connect_early=1`, `dev_autolaunch=0`.

*"Only one app can be sideloaded at a time."* — so the dev slot is a singleton,
and a CI job cannot install two variants side by side on one device. Our
`tools/devlease.py` protocol transfers directly.

**The zip trap**: the `manifest` must be at the **zip root**. Zipping the
project folder instead of its contents produces `Install Failure: No manifest.
Invalid package.` This is the single most common Roku onboarding failure and is
exactly why `roku-deploy` stages into a temp dir first.

*Unconfirmed: any dev-mode session timeout. We found no documented limit; the
commonly repeated "6 hours" figure did not appear in any source we could reach.*

### 5.2 Logs

```bash
nc "$ROKU_IP" 8085 | tee roku-console.log     # nc, not telnet — no TTY needed
```

Port **8085** is the BrightScript console: `print` output, compile errors, crash
stack traces with line numbers, and an interactive debugger on Ctrl-C (`bt`,
`var`, `step`, `over`, `out`, `print`, `threads`)
([debugging](https://developer.roku.com/docs/developer-program/debugging/debugging-channels.md)).

Port **8080** is the SceneGraph debug server, with the commands that matter for
performance work: `sgnodes all` / `sgnodes roots` / `sgnodes <id>`,
`loaded_textures`, `r2d2_bitmaps`, `free`, `chanperf`, `fps_display 1`,
`brightscript_warnings`, and `logrendezvous`. Port **8087** is screensaver
debugging. Ports 8089–8093 were per-thread debug endpoints and are **deprecated
since Roku OS 7.5** — everything consolidated onto 8085.

Note for our OCR-harness habits: a `print` buffering trap like the macOS one in
Decision 099's amendment does not apply here — the console is a live socket.

### 5.3 Screenshots

Verified from two independent open-source clients' request code rather than
prose docs:

```bash
curl --user rokudev:$ROKU_PW --digest -sS \
  -F "mysubmit=Screenshot" -F "archive=" -F "passwd=" \
  "http://$ROKU_IP/plugin_inspect"

curl --user rokudev:$ROKU_PW --digest -sS -o shot.jpg \
  "http://$ROKU_IP/pkgs/dev.jpg"
```

([roku-deploy](https://github.com/rokucommunity/roku-deploy/blob/master/src/RokuDeploy.ts),
[rokuview](https://github.com/Garulf/rokuview)) `roku-deploy` extracts the
filename from the response with a regex allowing `.jpg` or `.png`, so do not
hardcode the extension. Dev-mode only (same `rokudev` auth realm). Typical output
is 1280×720 — lower resolution than the 3840×2160 we get from
`devicectl device capture screenshot`, but ample for OCR assertions.

### 5.4 ECP — the remote, scriptable

Port **8060**. Discovery by SSDP:

```
M-SEARCH * HTTP/1.1
Host: 239.255.255.250:1900
Man: "ssdp:discover"
ST: roku:ecp
```

Endpoints
([ECP](https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md)):
`GET /query/device-info`, `/query/apps`, `/query/active-app`,
`/query/media-player`, `/query/icon/<id>`, `/query/registry`;
`POST /launch/<id>`, `/install/<id>`, `/keypress/<KEY>`, `/keydown/<KEY>`,
`/keyup/<KEY>`, `/input`.
`/search/browse` is **deprecated as of Roku OS 12.0**.

Keys: `Home`, `Rev`, `Fwd`, `Play`, `Select`, `Left`, `Right`, `Down`, `Up`,
`Back`, `InstantReplay`, `Info`, `Backspace`, `Search`, `Enter`, `FindRemote`,
`Volume*`, `Power*`, `Input*`, and **`Lit_<char>`** for literal text (URL-encode
the character; `Lit_%20` is a space). Text entry from a script is therefore
trivial — a real advantage over our tvOS harness.

```bash
curl -d '' "http://$ROKU_IP:8060/keypress/Down"
curl -d '' "http://$ROKU_IP:8060/launch/dev?contentId=paradise_in_harlem&mediaType=movie"
curl -s   "http://$ROKU_IP:8060/query/media-player"     # playback state + position
```

`/query/media-player` returning live playback state and position is worth
noticing: it makes an **external** assertion about what the player is actually
doing, which is precisely the shape our `atv_external_observation_harness`
standing directive asks for — and here it comes free from the OS rather than
from the app's own self-report.

### 5.5 ⚠️ The `Limited` / 403 constraint — root-caused

**This is the owner action.** Verbatim from Roku's ECP reference:

> *"As of Roku OS 14.1, the Settings > System > Advanced system settings >
> Control by mobile apps feature must be set to 'Enabled' for a Roku device to
> receive the following ECP commands: keypress, keydown, keyup, query/icon,
> query/tv-channels, query/tv-active-channel"*

A second tier requires **both** developer mode **and** that setting: `query/chanperf`,
`query/r2d2-bitmaps`, `query/sgnodes`, `query/sgrendezvous`, `query/registry`,
`query/graphics-frame-rate`, `fwbeacons`, `query/app-object-counts`,
`query/app-state`, `exit-app`.

**`/launch` and `/query/device-info` are NOT gated** — which explains the
observed behaviour exactly: discovery works, `/keypress` 403s.

**Exact path to fix, on the device:**

```
Settings → System → Advanced system settings → Control by mobile apps
        → Network access → Enabled
```

(Accept the security warning it shows.) Roku OS 14.1 changed the default to
**Limited**. Use `Permissive` only if the controlling Mac is not on the same
LAN segment. There is no ECP or web-installer endpoint that can change this
setting — it gates the very endpoints that would need to change it, so it is
necessarily a one-time manual step per device.

The wire error string is literally *"ECP command not allowed in limited mode"*
([home-assistant/home-assistant.io#36240](https://github.com/home-assistant/home-assistant.io/issues/36240)),
corroborated by multiple community reports of exactly this 403 after the 14.1
update.

*Two small ambiguities: (a) we could not independently confirm `ecp-setting-mode`
as a literal `/query/device-info` field name — the example XML on Roku's page is
stale (software-version 9.3.0) and omits several fields Roku says exist. The
team's own device observation is the better ground truth. (b) The value set
appears to differ across OS generations — older regional support pages list
`Default`/`Permissive`/`Disable` with no `Limited`. Verify against the device's
own on-screen text.*

### 5.6 Toolchain from a Mac shell

| Tool | What it does | Runs where |
|---|---|---|
| [`roku-deploy`](https://github.com/rokucommunity/roku-deploy) (npm) | stage → zip → `plugin_install`, plus rekey and `bs_const` injection | Node, headless |
| [`brighterscript`](https://github.com/rokucommunity/brighterscript) (`bsc`) | BrightScript superset + compiler/transpiler with diagnostics | headless, CI |
| [`bslint`](https://github.com/rokucommunity/bslint) | *"runs the BrighterScript compiler without the publishing step, only outputting diagnostics"*; flags unused components/scripts | headless, CI |
| [`sca-cmd`](https://developer.roku.com/docs/developer-program/dev-tools/static-analysis-tool/command-line-utility.md) | **Roku's own Static Analysis Tool** — the same check that gates publishing | Java CLI, headless |
| [Rooibos](https://github.com/rokucommunity/rooibos) | mocha-style unit tests that **run on a real device** and exit 0/1 | device-in-the-loop |
| [VS Code extension](https://github.com/rokucommunity/vscode-brightscript-language) | breakpoints via the BrightScript Debug Protocol | interactive |

```bash
sca-cmd ./channel --output reports/sca.xml --format console,junit
npx rooibos --project=bsconfig.json --host=$ROKU_IP --password=$ROKU_PW
```

`sca-cmd` deserves emphasis: **static analysis is a mandatory, publish-gating
step in the Developer Dashboard**, and the same check runs locally. Wiring it
into CI on day one avoids a whole class of submission surprise — the direct
analogue of our `tools/check_workflow_gates.py` discipline.

*There is no headless off-device SceneGraph test runner.* Rooibos executes on
hardware, which matches our standing rule that the device is the oracle.

### 5.7 Deep linking

`POST /launch/<id>?contentId=<X>&mediaType=<Y>` (`dev` is the sideloaded app).
The app receives it as `Function Main(args as Dynamic)` with keys `contentid`,
`mediatype`, `source`, `action`, `instant_on_run_mode`. To receive a deep link
**while already running** requires `supports_input_launch=1` in the manifest plus
handling `roInputEvent`
([deep linking](https://developer.roku.com/dev/docs/implementing-deep-linking)).

`mediaType` values: `movie`, `episode`, `series`, `season`, `shortFormVideo`
(≤15 min — exempt from the deep-linking cert requirement), `tvSpecial`,
`liveFeed`, `sportsEvent`. `contentId` is ASCII, ≤255 chars — our `archiveID`
fits trivially, and it **must be the same string** as the search feed's
`playId`/`contentId`. Deep links must launch straight into playback using stored
bookmarks, skipping any resume or profile screen.

This is the `archivewatch://item/{id}` verb in a new idiom, and it maps onto our
existing IntentInbox pattern cleanly.

---

## 6. Publishing

### What it means for us

Publishing is the *easiest* part of Roku: free account, HTTP-based packaging, a
one-week-ish review. The constraints that bite are in certification (§7), not in
the process.

### 6.1 Account

Free to enroll, develop, and publish, for individuals and companies. The account
is linked to a physical Roku device signed in with the same email. Tax forms
(W-9 / W-8BEN) apply only to the Partner Payouts monetisation program, which a
free channel never touches. *We could not confirm whether Roku restricts
publishing eligibility by country or entity type — only payouts.*
([dashboard](https://developer.roku.com/dev/docs/dashboard))

### 6.2 Packaging and signing
([packaging](https://developer.roku.com/dev/docs/packaging-channels))

1. `telnet <roku-ip> 8080` → type `genkey`. This generates a signing key in the
   device's crypto hardware and prints a **password + Developer ID**. *Record
   both — the password is never shown again.*
2. Sideload the channel, then open the **Packager** link in the dev web UI
   (`/plugin_package`): Dev ID, app name/version, the genkey password,
   compression (**squashfs** for Roku OS ≥ 8.0). Output is a signed, encrypted
   `.pkg`.
3. Upload the `.pkg` in the Developer Dashboard.

**Key hygiene, and one non-obvious consequence.** Roku: *"It is a good practice
to generate a new signing key for each app created unless you explicitly want to
share registry information between apps."* Publishing an update with the **same
key preserves users' registry data** — i.e. their favorites and watch progress.
A key change wipes them. Given §4.1 puts all of our user state in the registry,
**the signing key is as load-bearing as an Android upload keystore, and for a
reason that has no Apple analogue.**

Recovery: the Packager's **Rekey** utility restores a key onto a different dev
device — but it requires *both* a previously-signed `.pkg` *and* its original
password. Lose both and there is no documented path back. *(Inferred from the
rekey mechanism; Roku does not state "no recovery" explicitly.)* Back up the
password and one signed `.pkg` the way we back up
`~/keystores/archivewatch-upload.jks`.

### 6.3 Channel types — the CI/testing story

Private channels were retired. The replacement is **Beta apps**
([publishing guide](https://developer.roku.com/docs/developer-program/publishing/channel-publishing-guide.md)):
not listed in the store, **no certification required**, reportedly **up to 20
testers per beta app, expiring after 120 days, up to 10 beta apps per account**.
*(Those three numbers come from a doc summary and are the least well-corroborated
figures in this brief — verify before planning around them.)*

Practical read: this is enough for rolling internal QA and a small tester pool,
but it is **not TestFlight**. Expect to re-issue beta apps roughly quarterly.
For our own device loop, sideloading needs none of this.

### 6.4 Submission and review

Package → create the app in the Dashboard → upload → **Static Analysis
(mandatory, gates publish)** → optional Channel Behavior Analysis → submit →
manual QA. *"Schedule publishing with at least two business days' notice."*

Review time is **not published by Roku**. Third-party integrator write-ups
consistently report **~3–5 business days** for manual certification plus 1–2 days
of store propagation, with iterative rejection/resubmission being common. Treat a
week as the planning figure and confirm nothing.

---

## 7. Performance, certification gates, and gotchas

### 7.1 The performance numbers that are actually enforced

From the certification checklist
([docs.roku.com](https://docs.roku.com/api/v1/published/channelcertificationchecklist/en/US/text)):

| Item | Requirement |
|---|---|
| **4.11** | *"The channel's file size is no larger than 4MB."* |
| **6.1** | Loading/retrieving screens for anything over **3 s** |
| **6.2** | Launch to a **fully rendered** home screen: required within **20 s** on Roku Express (Littlefield); recommended 15 s |
| **6.3** (recommended) | tile-to-tile **250 ms**; remote response **250 ms**; video starts within **5 s**; animations ≥ **30 fps**; scene transitions ≤ **3 s** |
| **6.4** | Use **Fast Video Start** pre-buffering where applicable |
| **3.6** (certification.md) | *"Apps must start playing content within 8 seconds of initiation."* |
| **4.10** | Bookmarking for all VOD > 15 min, retained ≥ **30 days** |
| **9.9** | FF/RW must offer exactly **1× / 2× / 4×** |
| **9.17** | Must serve bitrates down to **800 kbps** |
| **5.2** | Graphics must be broadcast-safe: **RGB ≤ 235/235/235** |

**6.2 is the one to internalize.** Launch to a *fully rendered* home screen in
20 s on the slowest certified device — with **no bundled seed** (§0.2) and a
**cold network fetch + JSON parse** in the middle of it. That is the whole
budget: TLS handshake + download + `ParseJson` + ContentNode build + first paint.
It is achievable — but only with a small first payload, which is the entire
argument for §8's Roku-specific shards over the 6.2 MB index.

**5.2 is a quiet trap for our design system.** Our brand chrome is
`--color-bg: #FFFFFF` = RGB 255. **Pure white fails broadcast-safe cert.** Roku
needs its own token override capping whites at 235. Worth flagging to the design
half of this research pair.

### 7.2 Render thread discipline

Covered in §1.1; the operational rules: never network or parse on Render; keep
`init()` minimal; build node trees on a Task and hand over in one assignment;
prefer `getFields`/`setFields` over dotted chains; never create `Group`s on a
Task thread; use `logrendezvous` before guessing.

### 7.3 Texture memory

Covered in §2.5. The single actionable rule: **request the smallest poster the
tile actually draws**, set `loadWidth`/`loadHeight` before `uri`, and shed
offscreen textures on `roAppMemoryMonitor`'s 80 % threshold. Our Apple/Android
grids keep far more decoded art resident than a 1 GB Streaming Stick 4K will
tolerate.

### 7.4 List/grid recycling

Covered in §2.4. Two rules: observe `itemContent` *inside* the item component so
recycled slots update (reading it once in `init()` shows stale content), and use
`observeFieldScoped` for anything else so observers do not accumulate across the
pool's lifetime.

### 7.5 BrightScript language behaviour

- **Reference counting, no tracing GC.** *"BrightScript objects are deleted when
  their reference count drops to zero. However, this will not happen [if] there
  are circular references."* `RunGarbageCollector()` exists to find cycles in
  development, is *"relatively slow to run"*, should be off in production, and
  **cannot see cycles that span threads or mix SceneGraph nodes with plain
  BrightScript objects** — so a real leak class exists that the tool cannot
  detect ([optimization](https://developer.roku.com/dev/docs/optimization-techniques)).
- Associative arrays and other containers are **deep-copied** across field
  boundaries; nodes are passed by reference. *"accessing a 5.6MB AA can take
  hundreds of milliseconds."* Keep per-item payloads lean.
- To clone a node, use `createObject("roSGNode", oldNode.subtype())`, not
  `setFields(getFields())`.
- *We could not confirm from primary sources the common folklore about string
  concatenation, boxing, `Invalid` handling, or `for each` vs indexed loops.*
  Roku's own performance page explicitly does not cover them. Use the
  BrightScript Profiler (improved in OS 14.5) rather than folklore.

### 7.6 Roku OS 14 / 15 — what changed
([release notes](https://developer.roku.com/dev/docs/release-notes))

- **15.0** — data-transfer-by-reference APIs (move data in/out of fields without
  copying), improved lower-memory JSON parsing, `GetUptimeMillisecondsAsLong()`.
  *These directly target §2.3's cost.*
- **15.1** — Perfetto-based app tracing. **Deprecated: `roString.AppendString()`
  → use `SetString()`.**
- **15.2** — `roAppMemoryMonitor` thresholds at 80/85/90/95 %; ECP `chanperf`
  (raw CPU stats over ECP — useful for our harness); Perfetto heap graphs.
- **14.5** — **RSG 1.1 sunset**: apps declaring `rsg_version=1.1` run as 1.2 or
  *"may malfunction."* Declare 1.3 (required for certification by 2026-10-01).
- **14.0** — `MonospaceLabel`.
- **13.0** — `GetChannelMemoryLimit()`, `roAppManager.GetLastExitInfo()` (why the
  OS killed us — pair with the memory thresholds).

*No developer-facing home-screen change was found in this window; the
home-screen ad changes in the press are platform-level.*

### 7.7 Documentation contradictions found (do not trust one page)

1. **Trick-play thumbnails**: the trick-mode page says thumbnails are required
   for VOD > 15 min; checklist 9.8 accepts positional increments *or* a BIF
   thumbnail. Plan for the stricter reading.
2. **Codec table**: the live page gives HEVC 40 Mbps and AV1 as DASH-only; a
   cached version gave 25 Mbps and listed VP9. Re-verify before finalizing
   encodes.
3. **Instant Replay**: `certification.md` says 10–25 s; the checklist says ~20 s.
4. **Launch time**: `certification.md` says a flat 15 s; the checklist gives the
   device-qualified 20 s-on-Express figure. The checklist is more precise.
5. **`SubtitleUrl`**: present in one fetch of the content-metadata page, absent
   from the closed-caption page's account. Verify on device.
6. **Store poster dimensions**: no single authoritative table. Trust the
   Dashboard's asset-upload UI at submission time, which enforces current specs.

### 7.8 Device fragmentation

Detect at runtime with `roDeviceInfo.GetModel()` (a model *name* covering many
revisions), `GetModelDetails()` (the specific model number), `GetModelType()`.
Gate grid density, image sizes and prefetch on the 512 MB / 1 GB / 2 GB tiers —
the same "the low end is where submissions fail" lesson Decision 100 taught us
on Fire OS. *`GetGraphicsPlatform()` exists; its return values are not documented
in anything we could reach.*

---

## 8. Recommended architecture for Archive Watch on Roku

This is a proposal, not a decision. It is written so that a `/decision` entry
could be drafted from it if the port is funded.

### 8.1 The shape

```
┌──────────── source/Main.brs — roSGScreen + message loop ────────────┐
│  components/                                                        │
│    AWScene.xml          Scene: rail + view container + Dialog host   │
│    views/  Home  Browse  TVShows  Search  Detail  Player  Library    │
│    items/  PosterTile  ShelfRow  EpisodeRow      ← itemComponentName │
│    tasks/  CatalogTask  DetailTask  SearchTask  RegistryTask         │
│    lib/    Registry.brs  Net.brs  Content.brs  Log.brs               │
└─────────────────────────────────────────────────────────────────────┘
        Task threads ──HTTPS──▶ archivewatch.org (GitHub Pages)
                                 roku/*.json  ← NEW pipeline artifacts
                                 details/<xx>.json  ← EXISTING, reused
        Video node ──HTTPS──▶ archive.org (progressive MP4, 302 → node)
```

### 8.2 The data plane: reuse the *shape*, not the artifact

Measured facts about the current web plane (this repo, 2026-09-03):

| Artifact | Size | Notes |
|---|---|---|
| `catalog-index.json` | **6,219,596 B** (2.0 MB gzipped) | 26,965 items, 8 positional columns, avg 242 B/row |
| …items array alone | 6,516,040 B | dropping `search` + `backdrop` → 4.37 MB (1.30 MB gz) |
| …`shelves` map | **28,300 B** | 29 shelves, arrays of archiveIDs |
| …`collections` map | **81,267 B** | 26 curated collections |
| `details/<xx>.json` | 92–121 KB × 256 | ~105 items each, 30 MB total; carries `downloadURL`, synopsis, director, cast, genres |

**Recommendation: add a `roku/` output to the existing pipeline** (a sibling of
`build_catalog_index.py` / `build_web_details.py`, so it cannot drift), emitting:

| File | Contents | Est. size |
|---|---|---|
| `roku/home.json` | every Home shelf **hydrated** — id, title, year, poster, contentType per tile, ~20 tiles/shelf | ~120 KB |
| `roku/browse/<type>-<decade>.json` | paged browse shards, ~500 rows/page | ~120 KB each |
| `roku/collections.json` | the 26 collections + blurbs, hydrated | ~150 KB |
| `roku/search/<prefix>.json` | inverted title/keyword index sharded by 2-char token prefix | ~30–80 KB each |
| `roku/series/<slug>.json` | reuse the existing `series/*.json` unchanged | — |
| `details/<xx>.json` | **reuse unchanged** — one 92 KB fetch per Detail open, and the shard caches ~105 neighbours for free | — |

Why not just parse the 6.2 MB index: three reasons compound. (a) It is one
synchronous `ParseJson` on a 1 GB device with no streaming parser (§2.3). (b) The
parsed AA *"consumes more memory than the original string"*, and then the
ContentNode tree is a third copy. (c) Certification 6.2 gives us 20 s to a fully
rendered home screen on the slowest device, and Home needs ~120 KB of that
6.2 MB. **Hydrated shelves make Home a ~120 KB fetch instead of a 6.2 MB one.**

`EnableEncodings(true)` on every transfer; cache each shard in `cachefs:` keyed
by ETag, and always check the file exists before trusting it (§2.6).

**Search is the one genuinely open design question.** Roku has no FTS5, and
GitHub Pages is static. Three options, in order of preference:

- **A — prefix-sharded inverted index** (recommended). The pipeline emits a
  token→ids map sharded by the first two characters. A query fetches 1–2 shards
  and intersects. Small, fast, works on any device. Costs a new pipeline stage.
- **B — load the slim index once, search in memory.** 4.37 MB JSON / 1.30 MB
  gzipped, parsed on a Task thread and held as arrays (never ContentNodes) for
  linear scan. Simplest to build; **memory cost is the unknown** and could be
  8–16 MB resident. Viable only if measurement #1 says so.
- **C — HTTP Range reads over a compact binary index.** `AddHeader("Range", …)`
  has no documented prohibition, so a fixed-width binary index could be probed
  without downloading it. Clever, unverified, and probably not worth the risk.

TV-DESIGN §3.6 binds regardless: **every browse path must be complete without
typing** — categories, decades, collections, Surprise. Search is a convenience,
not the front door, which lowers the stakes on this choice considerably.

### 8.3 Playback

- `streamFormat = "mp4"`, `playStart` from the registry bookmark.
- `StreamStickyHttpRedirects = true` — the nearest thing to Decision 031's node
  pinning.
- `ignoreStreamErrors = true`.
- `control = "prebuffer"` from Detail (cert 6.4; buys us headroom against the
  8-second start gate).
- Our own stall watchdog on `position` stagnation → re-resolve URL → `playStart`
  → `play`. Accept that every recovery is a visible re-buffer.
- Decision 077's copy-level fallback **does** port: if a title cannot start
  within our own timeout, try the next derivative URL our catalog already knows
  about.
- Subtitles: publish SRT alongside WebVTT from the same pipeline.
- BIF thumbnails for every title over 15 minutes — a new ffmpeg pipeline stage
  next to `batch_covers.py`, with the same resumable-manifest discipline
  (Decision 023) and the same budget-that-publishes rule (Decision 057).

### 8.4 Persistence

One registry section, JSON-packed, with hard caps and LRU eviction, flushed on
write. Progress + favorites only. Cross-device sync recorded as 🚫 in PARITY with
the certification reason, not "planned."

### 8.5 Scope for a v1, mapped to TV-DESIGN §2

TV-DESIGN's wave table binds: **v1 = Home · Movies · TV · Search · Detail ·
Player · Library · Settings.** Channels, Surprise and Collections are v1.1;
Cartoon Mode and playlists v2. Clip Studio and Creation Studio never. Nothing in
this research argues for changing that; the Roku-specific additions to the v1
list are the **Roku Search content feed** (§4.4 — for a discovery-first catalog,
skipping it would be perverse) and **deep linking** (cert 5.1, and it is one of
the cheapest surfaces to build).

### 8.6 Effort, stated honestly

Zero code reuse. The comparable prior is the Android v1 spine (§PARITY: "shipped
in one session" — but on a mature Kotlin/Compose stack with our shared SQLite
contract already defined). Roku has neither the language familiarity nor the data
contract, and adds three net-new pipeline stages (Roku shards, SRT publication,
BIF generation). Decision 047's original estimate for Roku — *"0% reuse (~2–4
months)"* — remains the right order of magnitude, and this research does not
find anything that shortens it. What it *does* find is that the risk is
front-loadable: measurements #1–#4 in §9 can be answered in a few days on one
device, and any of them coming back badly changes the shape of the whole build.

---

## 9. Open questions — and the four that must be measured first

Ranked by how much they would change the plan.

1. **How long does `ParseJson` take, and how much does it cost, for a
   multi-MB payload on a Streaming Stick 4K?** No benchmark exists in any Roku
   doc. *Test:* Task-thread harness that fetches the real 6.2 MB
   `catalog-index.json` to `cachefs:`, times one `ParseJson`, and samples
   `GetGeneralMemoryLevel()` / `GetChannelAvailableMemory()` through it. Also run
   the 4.37 MB slim variant and a 120 KB shard. **This decides §8.2's Option A
   vs B.**

2. **Does the firmware recover from a mid-stream connection reset, and how?**
   Undocumented. This is the whole reason our Apple loader exists. *Test:* play
   an archive.org MP4 through a LAN proxy that RSTs the connection mid-transfer;
   observe `state`, `errorCode`, `errorInfo`, `bufferingStatus`,
   `streamInfo.isResume`. Repeat with `ignoreStreamErrors` on and off.
   **If the answer is "it dies," Roku playback quality is materially worse than
   every other platform and that belongs in the funding decision.**

3. **Does `Streams` (or `cdnConfig`) fail over on error, or only on bandwidth?**
   If `Streams` retries the next URL on a hard failure, we recover a large part
   of Decision 034 for free. *Test:* a `Streams` array whose first entry is a
   deliberately dead host and second is good; see whether playback starts.

4. **Do `httpHeaders` survive the archive.org 302, and does seeking use HTTP
   Range?** Both answerable from the same LAN proxy capture as #2.

Further open questions, not blocking:

5. Does Roku persist a **disk cache of remote images** across launches, or is
   every poster re-fetched cold? (Affects launch time against cert 6.2.)
6. What is the actual **`cachefs:` quota**, and how aggressively is it evicted
   in practice on a 1 GB stick with other apps installed? No number is
   documented.
7. What is the real **per-app memory limit** on a Streaming Stick 4K, from
   `GetChannelMemoryLimit()`? Not published as a table.
8. Does `subtitleUrl` accept a `.vtt` file despite the docs naming only SRT and
   TTML? (Would save a pipeline stage.)
9. Are the **beta-channel limits** (20 testers / 10 apps / 120 days) current?
   Least-corroborated figures in this brief.
10. Does Roku restrict **publishing** (not payouts) by country or entity type?
11. What is the real certification **review turnaround**? Roku publishes no SLA.
12. Is the trick-play thumbnail requirement enforced as the trick-mode page
    states or as checklist 9.8 states? Worth asking Roku developer support
    *before* building a 20,000-item BIF pipeline.
13. Would Roku accept a Google OAuth **device-flow** used solely to link a
    cloud-storage account (not to sign into our service)? §4.3 reads it as
    prohibited; only Roku developer support can settle it.
14. Does `/launch` remain reliable under `Network access: Limited` in practice?
    The docs say it is ungated; worth confirming on the device, since it is the
    one control-plane call our harness would depend on before the setting is
    flipped.

---

## 10. Sources

Primary (developer.roku.com / docs.roku.com):
[core concepts](https://developer.roku.com/docs/developer-program/core-concepts/core-concepts.md) ·
[threads](https://developer.roku.com/docs/developer-program/core-concepts/threads.md) ·
[data management](https://developer.roku.com/dev/docs/data-management) ·
[handling application events](https://developer.roku.com/docs/developer-program/core-concepts/handling-application-events.md) ·
[optimization techniques](https://developer.roku.com/dev/docs/optimization-techniques) ·
[Node](https://developer.roku.com/docs/references/scenegraph/node.md) ·
[Scene](https://developer.roku.com/docs/references/scenegraph/scene.md) ·
[LayoutGroup](https://developer.roku.com/docs/references/scenegraph/layout-group-nodes/layoutgroup.md) ·
[ArrayGrid](https://developer.roku.com/docs/references/scenegraph/abstract-nodes/arraygrid.md) ·
[RowList](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/rowlist.md) ·
[MarkupGrid](https://developer.roku.com/docs/references/scenegraph/list-and-grid-nodes/markupgrid.md) ·
[Poster](https://developer.roku.com/docs/references/scenegraph/renderable-nodes/poster.md) ·
[Task](https://developer.roku.com/docs/references/scenegraph/control-nodes/task.md) ·
[Video](https://developer.roku.com/docs/references/scenegraph/media-playback-nodes/video.md) ·
[ContentNode](https://developer.roku.com/dev/docs/contentnode) ·
[content metadata](https://developer.roku.com/docs/developer-program/getting-started/architecture/content-metadata.md) ·
[ifUrlTransfer](https://developer.roku.com/docs/references/brightscript/interfaces/ifurltransfer.md) ·
[ifHttpAgent](https://developer.roku.com/docs/references/brightscript/interfaces/ifhttpagent.md) ·
[roByteArray](https://developer.roku.com/docs/references/brightscript/components/robytearray.md) ·
[global utility functions](https://developer.roku.com/docs/references/brightscript/language/global-utility-functions.md) ·
[ifDeviceInfo](https://developer.roku.com/docs/references/brightscript/interfaces/ifdeviceinfo.md) ·
[ifChannelStore](https://developer.roku.com/docs/references/brightscript/interfaces/ifchannelstore.md) ·
[roRegistry](https://developer.roku.com/docs/references/brightscript/components/roregistry.md) ·
[ifRegistrySection](https://developer.roku.com/docs/references/brightscript/interfaces/ifregistrysection.md) ·
[roAppMemoryMonitor](https://developer.roku.com/dev/docs/roappmemorymonitor) ·
[memory management](https://developer.roku.com/dev/docs/memory-management) ·
[file system](https://developer.roku.com/docs/developer-program/getting-started/architecture/file-system.md) ·
[hardware specifications](https://developer.roku.com/dev/docs/hardware) ·
[streaming specifications](https://developer.roku.com/dev/docs/media) ·
[closed caption](https://developer.roku.com/dev/docs/closed-caption) ·
[trick mode](https://developer.roku.com/dev/docs/trick-mode) ·
[fast video start](https://developer.roku.com/docs/developer-program/media-playback/fast-video-start.md) ·
[bookmarking](https://developer.roku.com/dev/docs/bookmarking) ·
[on-device authentication](https://developer.roku.com/docs/developer-program/authentication/on-device-authentication.md) ·
[sign-in best practices](https://developer.roku.com/docs/developer-program/authentication/signin-best-practices.md) ·
[universal authentication protocol](https://developer.roku.com/docs/developer-program/authentication/universal-authentication-protocol-for-single-sign-on.md) ·
[continue watching](https://developer.roku.com/docs/developer-program/discovery/continue-watching.md) ·
[implementing search](https://developer.roku.com/docs/developer-program/discovery/implementing-search.md) ·
[search feed spec](https://developer.roku.com/docs/specs/search/search-feed.md) ·
[deep linking](https://developer.roku.com/dev/docs/implementing-deep-linking) ·
[instant resume](https://developer.roku.com/dev/docs/instant-resume) ·
[manifest](https://developer.roku.com/docs/developer-program/getting-started/architecture/channel-manifest.md) ·
[hello world](https://developer.roku.com/docs/developer-program/getting-started/hello-world.md) ·
[developer setup](https://developer.roku.com/dev/docs/developer-setup) ·
[debugging](https://developer.roku.com/docs/developer-program/debugging/debugging-channels.md) ·
[ECP](https://developer.roku.com/docs/developer-program/dev-tools/external-control-api.md) ·
[static analysis CLI](https://developer.roku.com/docs/developer-program/dev-tools/static-analysis-tool/command-line-utility.md) ·
[packaging](https://developer.roku.com/dev/docs/packaging-channels) ·
[publishing guide](https://developer.roku.com/docs/developer-program/publishing/channel-publishing-guide.md) ·
[certification](https://developer.roku.com/docs/developer-program/certification/certification.md) ·
[certification checklist](https://docs.roku.com/api/v1/published/channelcertificationchecklist/en/US/text) ·
[release notes](https://developer.roku.com/dev/docs/release-notes) ·
[deprecated APIs](https://developer.roku.com/docs/references/deprecated-apis.md)

Code read directly (verified, not paraphrased):
[rokudev/hello-world](https://github.com/rokudev/hello-world) ·
[rokudev/videoplayer-channel](https://github.com/rokudev/videoplayer-channel) ·
[rokucommunity/roku-deploy](https://github.com/rokucommunity/roku-deploy) ·
[Garulf/rokuview](https://github.com/Garulf/rokuview)

Non-Roku primary:
[Google OAuth for TV and limited-input devices](https://developers.google.com/identity/protocols/oauth2/limited-input-device)

Secondary / community (flagged as such at each use):
[rokucommunity/bslint](https://github.com/rokucommunity/bslint) ·
[rokucommunity/brighterscript](https://github.com/rokucommunity/brighterscript) ·
[rokucommunity/rooibos](https://github.com/rokucommunity/rooibos) ·
[vscode-brightscript-language](https://github.com/rokucommunity/vscode-brightscript-language) ·
[Proxying network requests](https://briandunnington.github.io/proxying_network_requests) ·
[home-assistant.io#36240 (ECP limited mode)](https://github.com/home-assistant/home-assistant.io/issues/36240)
