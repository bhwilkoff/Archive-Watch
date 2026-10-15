# 06 — Roblox UI that matches the Archive Watch design system (2D + 3D, agent-authored)

Researched 2026-10-15. Primary sources are Roblox Creator Hub docs (create.roblox.com,
mirrored as Markdown at github.com/Roblox/creator-docs), Roblox DevForum announcements,
and GitHub repos (status read from the GitHub API the same day). Anything not confirmed
from a primary source is marked **UNVERIFIED**.

---

## 0. Bottom line

| Question | Answer (Oct 2026) |
|---|---|
| Component framework | **React Luau** (Roblox's own, official, on Creator Store + Wally `roblox/react`, v17.1.x, mirror pushed 2026-10-14). Vide is the credible lightweight alternative. Roact is dead (archived 2023-12-13). jsdotlua/react-lua is a stale community fork (last push 2025-05-23). |
| Design tokens | **Engine-native UI Styling is fully released** (StyleSheet / StyleRule / StyleLink / StyleDerive, full release 2026-01-20; StyleQuery full release 2026-05-11). Tokens = attributes on a StyleSheet, referenced as `"$Token"`. This is the right home for the Archive Watch palette. |
| Roblox "Foundation" design system | **Not public.** Roblox's internal library (powers the client, Studio and website). Only a community Fusion port exists. |
| Brand fonts | **Custom font upload is not supported** (community consensus, July 2026; no official upload path found). Inter and Fraunces are not built in. Use BuilderSans (body) + Merriweather (display serif) or check the Creator Store fonts catalog. |
| Console / 10-foot | GuiService selection engine (`SelectedObject`, `NextSelection*`, `SelectionImageObject`, `GuiService:Select()`); console guidelines require content-maturity info, D-pad reachability of everything, TV-safe areas, chat window disabled. |
| 3D | SurfaceGui (on parts) / BillboardGui; buttons only take input when the gui lives in PlayerGui with `Adornee` set; high PixelsPerStud on big faces is costly. |
| Posters | Every poster must be an uploaded, moderated Roblox image asset (Open Cloud Assets API, <8000x8000, 20 MB). UI images should be <=512x512; texture memory is by pixel count. |
| Captions | VideoPlayer has no caption API; render subtitles yourself (TextLabel over the VideoDisplay). Video assets are capped at 5 minutes (feature films cannot be uploaded whole). |
| Agent workflow | Roblox Studio ships a **built-in MCP server** (docs updated 2026-06-11); the old `Roblox/studio-rust-mcp-server` was archived 2026-04-03 in its favor. |

---

## 1. UI frameworks and the styling system

### 1.1 React Luau (recommended)

- Official repo: <https://github.com/Roblox/react-luau> — "A comprehensive, but not exhaustive,
  translation of ReactJS 17.x into Luau. This is a read-only mirror." GitHub API: not archived,
  `pushed_at` 2026-10-14; tags up to **v17.1.3** (the GitHub *Releases* page still shows only
  v17.0.1 from 2024-01-18, so read the tags).
- The README now links an official **Creator Store** asset
  (<https://create.roblox.com/store/asset/15621638430>) and **Wally** package
  (<https://wally.run/package/roblox/react>) — i.e. Roblox now publishes it; previously the
  community had to fork it because Roblox "have not published React to any public package
  registry" (jsdotlua README).
- Docs: <https://www.react-luau.dev/>. Packages: `React`, `ReactRoblox`, `RoactCompat`
  (migration from legacy Roact 1.x).
- Roblox-specific deviation: **Bindings**, "a form of signals-based state that doesn't
  re-render, for highly-efficient animations" (README) — use for focus scale / marquee motion.
- Roblox's own app (the internal Foundation library) is built on it (community port says it
  ports "the React version"), so it is the framework the platform owner uses at scale.

### 1.2 Others

| Library | Status (GitHub API 2026-10-15) | Notes |
|---|---|---|
| Roact <https://github.com/Roblox/roact> | **Archived 2023-12-13**, "deprecated and no longer maintained" | Points to react-lua. Do not start new work on it. |
| jsdotlua/react-lua <https://github.com/jsdotlua/react-lua> | Last push **2025-05-23**, no releases | Community fork created when Roblox didn't publish packages; superseded by Roblox's own Wally/Creator Store release. Avoid for new work. |
| Fusion <https://github.com/dphfox/Fusion> (docs <https://elttob.uk/Fusion/latest>) | Latest release **v0.3-beta, 2024-08-30**; repo pushed 2026-02-02 | Reactive state objects (Value/Computed/spring). Still "beta" numbering; slow release cadence. |
| Vide <https://github.com/centau/vide> (docs <https://centau.github.io/vide/>) | Tags to **0.4.1**; pushed 2026-09-28; MIT | Solid-inspired fine-grained reactivity, `create "TextButton" {...}`, "Fully typecheckable in Luau". Small, active. |

**Choice for an AI-agent-authored codebase in 2026: React Luau.** Reasons: (1) officially
maintained and distributed by Roblox; (2) the largest body of training data/idioms an agent
already knows (React 17 semantics, hooks); (3) component + props model maps 1:1 onto the
existing apps' structure (Shelf, PosterCard, DetailHero, Player); (4) Luau type annotations
translated from upstream. Vide is the pick if bundle simplicity and fine-grained updates for
huge poster grids matter more than familiarity. Fusion's 2024 last release makes it the
weakest long-term bet. (Judgment, not a Roblox recommendation.)

Note on combining: React/Vide create plain Instances, so the engine Styling system (1.4)
applies to them unchanged — let the framework own structure/state and the StyleSheet own
color/type/spacing tokens.

### 1.3 Roblox "Foundation"

- Roblox's internal design-system library "used to build the components that are used on
  Roblox Client, Roblox Studio and the Roblox website" — quoted from the community port thread
  <https://devforum.roblox.com/t/fusion-foundation-a-fusion-port-of-robloxs-foundation-library-used-to-create-native-components/4706377>
  (port: <https://github.com/TenebrisNoctua/FusionFoundation>, incomplete).
- No public Roblox repo or package found (GitHub org search for "foundation" returns only
  AI repos). A Roblox job post describes a "Foundation team" that "defines and builds our
  design language and system" (<https://www.themuse.com/jobs/roblox/product-designer-visual-systems>).
- **UNVERIFIED** whether the port's provenance/licensing is clean; do not depend on it.

### 1.4 Engine UI Styling (StyleSheet / tokens) — RELEASED

Sources: <https://create.roblox.com/docs/ui/styling>, CSS mapping
<https://github.com/Roblox/creator-docs/blob/main/content/en-us/ui/styling/css-comparisons.md>,
stylable-property list
<https://github.com/Roblox/creator-docs/blob/main/content/en-us/ui/styling/compatibility.md>.

Timeline:
- 2025-08-26 Client Beta (publishable) — <https://devforum.roblox.com/t/client-beta-you-can-now-publish-styles-in-your-experience/3901480>; thread update **2026-01-20: "Styling is now fully released."**
- 2026-04-09 StyleQuery Studio beta → **2026-05-11 "StyleQuery and enhanced pseudoinstance styling are now fully released"** — <https://devforum.roblox.com/t/full-release-stylequery-more-styling-features/4566519>.

Model:
- **StyleSheet**: holds StyleRules; its **attributes are tokens** (`tokens:SetAttribute("Orange", Color3.fromHex("FF5C35"))`), referenced as `"$Orange"`. Tokens may alias tokens (`themeA:SetAttribute("FrameColor", "$Aqua")`).
- **StyleDerive**: one sheet inherits another (global tokens → theme → design sheet). "Related themes must have the same set of tokens" — swap themes by retargeting a StyleDerive.
- **StyleLink**: placed under a ScreenGui (formally: "Links a StyleSheet to the instance tree whose root is the parent of the StyleLink"); "Only one StyleSheet can apply to a given tree." Whether a StyleLink under a SurfaceGui/BillboardGui behaves identically is **UNVERIFIED** (the API text implies any parent).
- **StyleRule.Selector** syntax (from css-comparisons.md): class `"TextButton"`, tag `".PosterCard"` (CollectionService tag), name `"#ModalFrame"`, child `">"`, descendant `">>"`, list `"ImageLabel, TextLabel"`, state `"ImageButton:Hover"`, pseudo-instance `"Frame.Rounded::UICorner"`, query `"@Wide Frame > TextButton"`, nested relative selectors (`"> TextButton"`, `":Hover"`). `Priority` resolves conflicts.
- **States** are the four `Enum.GuiState` values only — Idle, Hover, Press, NonInteractable (<https://create.roblox.com/docs/reference/engine/enums/GuiState>). **There is no gamepad "Selected" state**, so "focus does the work" on TV must be driven by `SelectionGained/SelectionLost` (toggle a tag, e.g. `.Focused`) or `SelectionImageObject` — see §3.
- **Transitions**: `rule:SetPropertyTransitions({BackgroundColor3 = TweenInfo.new(...)})` (CSS-transition analogue).
- **StyleQuery** conditions: `MinSize`, `MaxSize`, `AspectRatioRange` (container), and global `ViewportDisplaySize`, `PreferredInput`(Type) (keyboard/mouse, touch, gamepad), `ReducedMotionEnabled`, plus `PreferredTextSize` with built-in selectors such as `@PreferredTextSizeLarge` and e.g. `@ReducedMotionEnabledTrue`. Caveats from the release notes: size conditions + conflicting size styles in one query can flicker; many StyleQueries under one instance cost performance, prefer built-in selectors.
- Stylable properties include FontFace, TextSize, LineHeight, OpenTypeFeatures, TextColor3, Image*/ScaleType/Slice*, Size/Position/AnchorPoint, Selectable/SelectionOrder, and the modifiers UICorner, UIStroke, UIGradient, UIPadding, **UIShadow** (blur/spread/inset, text shadows), UIListLayout flex props, UIFlexItem, UIAspectRatioConstraint, UITextSizeConstraint, UIScale.
- Known limitation (beta post): "StyleRules do not apply to properties that have been changed from their default values" — i.e. an instance's explicit property wins. **For an agent this is the main trap**: the component code must NOT set colors/sizes that the StyleSheet owns, or the token silently does nothing. (Whether this still holds post-GA is **UNVERIFIED**; design as if it does.)
- Performance (beta post): "Setting properties on StyleRules and changing tokens on StyleSheets are relatively cheap"; creating/removing rules and changing Derives cost more; a styled pseudo-instance costs about as much as a real one.
- Studio: Style Editor available to all; styled properties show a warning glyph in Properties.

**Proposed Archive Watch token sheet (sketch):**

```luau
-- ReplicatedStorage/Design/Tokens (StyleSheet)
tokens:SetAttribute("ColorPrimary", Color3.fromHex("FF5C35"))   -- marquee orange, CTA (chrome)
tokens:SetAttribute("ColorAccent",  Color3.fromHex("0047FF"))   -- links (chrome)
tokens:SetAttribute("ColorBg",      Color3.fromHex("FFFFFF"))
tokens:SetAttribute("ColorText",    Color3.fromHex("0A0A0A"))
tokens:SetAttribute("ColorBorder",  Color3.fromHex("E0E0E0"))
-- semantic (content meaning only — never used by chrome rules)
tokens:SetAttribute("CatFeatureFilm", Color3.fromHex("FF5C35"))
tokens:SetAttribute("CatClassicTV",   Color3.fromHex("2D5BFF"))
tokens:SetAttribute("CatSilentEra",   Color3.fromHex("C9A66B"))
tokens:SetAttribute("CatAnimation",   Color3.fromHex("FF4D8D"))
tokens:SetAttribute("CatNewsreel",    Color3.fromHex("8A8F98"))
tokens:SetAttribute("CatDocumentary", Color3.fromHex("3FA796"))
tokens:SetAttribute("CatEphemeral",   Color3.fromHex("7C5BBA"))
tokens:SetAttribute("CatShortFilm",   Color3.fromHex("E8A317"))
-- type: 3 weights x 2 sizes = 6 levels, as Font + size tokens
tokens:SetAttribute("FontRegular",  Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Regular))
tokens:SetAttribute("FontMedium",   Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Medium))
tokens:SetAttribute("FontBold",     Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold))
tokens:SetAttribute("TextSmall", 16) ; tokens:SetAttribute("TextLarge", 24)  -- TV theme overrides via @ViewportDisplaySizeLarge
```
Rules then target tags: `.Eyebrow` (Medium/Small), `.Title` (Bold/Large), `.Meta` (Regular/Small),
`.Cat-Animation::UIStroke`, etc. The brand/semantic split can be enforced mechanically: a lint
that refuses `$Cat*` tokens in any rule whose selector is chrome. Whether Font values are legal
token attributes: the docs' tag-selector example stores `Enum.Font.Oswald` as a token, so
`Enum.Font` works; storing a `Font` datatype as an attribute is **UNVERIFIED** (attributes
support a fixed type list) — fall back to `Enum.Font.BuilderSans*` tokens if not.

---

## 2. Fonts and text

- **Built-in families** (`Enum.Font`, <https://create.roblox.com/docs/reference/engine/enums/Font>): Arial/Arimo, SourceSans (+Light/Semibold/Bold/Italic), Gotham family, **BuilderSans (+Medium/Bold/ExtraBold)**, Roboto/RobotoCondensed/RobotoMono, Nunito, Ubuntu, TitilliumWeb, JosefinSans, Oswald, Jura, Michroma, **Merriweather**, Bodoni, Garamond, Fondamento, SpecialElite, Code, plus display/novelty faces. **Inter and Fraunces (Archive Watch web's `--font-body` / `--font-display`, per the repo's CSS) are not in the enum.** Docs note Gotham and Arial "will be removed in the near future" (Font datatype page, per search snippet; treat as **UNVERIFIED**).
- **Font datatype** (<https://create.roblox.com/docs/reference/engine/datatypes/Font>): `Font.new(family: Content, weight, style)`, `Font.fromEnum`, `Font.fromName`, `Font.fromId`; weights Thin..Heavy (100–900). Set `TextLabel.FontFace`.
- **More families**: Creator Store fonts section <https://create.roblox.com/store/fonts> (launched with 81 fonts, 2023: <https://devforum.roblox.com/t/fonts-in-creator-marketplace-81-new-fonts/2164977>), used via `Font.fromId(id)`. Whether Inter is in the store: **UNVERIFIED** (not found).
- **Uploading your own TTF/OTF: not supported.** No official upload path found; DevForum answer as of 2026-07-11: "roblox doesn't allow you uploading your own font" (<https://devforum.roblox.com/t/uploading-custom-fonts-or-workarounds/4731886>). Workarounds are image-sprite fonts (bitmap glyph sheets in ImageLabels) — poor for localization/scaling/accessibility; reserve for a wordmark only. A claim that Studio can load local font files for testing (creation.dev) is **UNVERIFIED**.
- **Recommendation**: BuilderSans for UI text (Roblox's own UI face, full weight range → the three-weight scale maps directly: Regular/Medium/Bold); Merriweather as the serif display stand-in for Fraunces (closest built-in; **judgment**). Ship the Archive Watch wordmark as an image asset.
- **RichText** (<https://create.roblox.com/docs/ui/rich-text>): enable per object (`RichText = true`). Tags: `<font color size face family weight transparency>`, `<stroke>`, `<b> <i> <u> <s>`, `<br/>`, `<uc>`, `<sc>` (small caps), `<mark>`, comments. Escape `& < > " '`. Localization strips tags (reapply after translating). Useful for a one-label meta line ("1931 · Horror · 71 min") with a weight change, without extra instances.
- Other text props worth using (stylable): `LineHeight`, `OpenTypeFeatures`, `TextTruncate` (AtEnd for long titles), `MaxVisibleGraphemes`, `UITextSizeConstraint` (docs: never set `MinTextSize` below 9).

---

## 3. Input across platforms

### 3.1 Gamepad / console ("focus does the work")
- **GuiService** (<https://create.roblox.com/docs/reference/engine/classes/GuiService>): `SelectedObject` (the focused GuiObject; "may reset to nil if the object goes off screen"), `GuiService:Select(parent)` (selects the visible selectable descendant with the lowest `SelectionOrder` — use on screen appear to imperatively claim focus, same lesson as tvOS `HeroCarousel`), `AutoSelectGuiEnabled`, `GuiNavigationEnabled` (turn off to write your own navigator), `ViewportDisplaySize` (Small/Medium/Large — use this, not `IsTenFootInterface()`, which "always returns true on consoles" and is not a console detector per docs).
- **GuiObject** (<https://create.roblox.com/docs/reference/engine/classes/GuiObject>): `Selectable`, `SelectionOrder`, `NextSelectionUp/Down/Left/Right` (explicit graph for shelves: Left/Right within a row, Up/Down between rows remembering column), `SelectionImageObject` (per-element focus ring; `PlayerGui.SelectionImageObject` globally — set to an empty Frame and draw focus yourself via UIScale + UIStroke), events `SelectionGained`/`SelectionLost`. `SelectionGroup` / `SelectionBehavior*` live on GuiBase2d (names from the class list; behavior details **UNVERIFIED**).
- Shelves: a horizontal `ScrollingFrame` per row; on `SelectionGained` scroll the canvas so the focused card stays in the safe band (Roblox auto-scrolls selected objects into view in ScrollingFrames — default behavior details **UNVERIFIED**; set `ScrollingFrame.SelectionBehavior`/manual `CanvasPosition` tween to be safe).
- **Input Action System** (<https://create.roblox.com/docs/input/input-action-system>): `InputContext` (priority, `Sink`), `InputAction`, `InputBinding` (KeyCode / composite / `UIButton` link for touch), `PreferredBinding`; core system not beta, but `InputActionLabel` (auto-resolving button glyph) and the Input Action Manager are **beta**. Use contexts to separate "browse" and "player" input (Back = ButtonB closes Detail / exits player).
- Gamepad conventions (<https://create.roblox.com/docs/input/gamepad>): ButtonA accepts, ButtonB cancels; detect device with `UserInputService.PreferredInput` (also `GamepadConnected/Disconnected`); Studio has a Controller Emulator.

### 3.2 Console guidelines (<https://create.roblox.com/docs/production/publishing/console-guidelines>)
- "Games designed for consoles always need to provide content maturity information" (Experience Guidelines questionnaire: <https://create.roblox.com/docs/production/promotion/experience-guidelines>).
- Every interactive element reachable with four directions + select + back; keep key actions few presses deep; device-correct button glyphs; progressive disclosure to secondary screens; sound on selection/move; haptics sparingly.
- Relative sizing, design low-res first, scale up via `ViewportDisplaySize`; keep key UI in **TV-safe areas** (some TVs crop edges) — reuse Archive Watch's 5% overscan band.
- **Disable the chat window** on console.
- A 2023 staff reply said there are "no console-specific requirements outside of the best practices" in these guidelines (<https://devforum.roblox.com/t/update-xbox-guidelines-2023/2398716>). Whether console availability is still an opt-in toggle in experience settings, and any PlayStation-specific restrictions (Roblox on PS is rated T: <https://en.help.roblox.com/hc/ar/articles/19816103303572-PlayStation-FAQ>), is **UNVERIFIED** for 2026.

### 3.3 Touch / mouse / keyboard
- Touch and mouse go through the same GuiButton `Activated`; `GuiState` Hover only exists for pointers (styling `:Hover` won't fire on touch or gamepad). `TouchControlsEnabled` hides the default thumbstick on browse screens.
- Use StyleQuery `PreferredInput` selectors to enlarge hit targets on touch and show focus rings only on gamepad.

### 3.4 VR
- VR guidelines (<https://create.roblox.com/docs/production/publishing/vr-guidelines>) cover comfort (vignette, stepped rotation), ≥72 FPS on Quest, and warn "Numerous and complex SurfaceGuis can be costly." They do not document how ScreenGuis appear in VR. `VRService.GuiInputUserCFrame` picks which tracked device drives GUI input. Community reports that VR GUI is placed on panels in a camera folder (old thread, **UNVERIFIED** for 2026). Practical approach: in VR, present browse as in-world SurfaceGui panels (§4) rather than ScreenGuis.

---

## 4. 3D UI in the world

Docs: <https://create.roblox.com/docs/ui/in-experience-containers>,
<https://create.roblox.com/docs/reference/engine/classes/SurfaceGui>.

- **SurfaceGui**: on a part `Face`; `SizingMode` = PixelsPerStud (default) or FixedSize with `CanvasSize` (pixel-for-pixel match with ScreenGui — use FixedSize so 2D components render identically in 3D); `LightInfluence` 0 for an emissive "screen"/marquee look, `Brightness` up to 1000 for dark theaters; `MaxDistance` (default 1000); `AlwaysOnTop`; `ZOffset` layering; `ClipsDescendants`.
- **Interactivity rule**: buttons in a SurfaceGui/BillboardGui "will only receive user input if they are parented to the PlayerGui" — so create the SurfaceGui under PlayerGui (via StarterGui) and set `Adornee` to the wall part; the part needs `CanQuery = true`. This also makes the same React tree reusable: `ReactRoblox.createPortal` into a PlayerGui SurfaceGui adorned to the wall (pattern; **judgment**).
- **Performance**: appearance cached and recomputed only when something changes; "a large pixel density could negatively affect performance" on large faces. Many SurfaceGuis are costly (VR guidelines). → One SurfaceGui per shelf/wall segment, not one per poster; animate focus with UIScale (cheap) rather than re-layout.
- **BillboardGui**: camera-facing; `Size` scale = studs; `StudsOffset`; `MaxDistance` default inf. Use for "Now playing" tags above a screen, not for posters (posters should sit flat on walls).
- **ProximityPrompt** (<https://create.roblox.com/docs/ui/proximity-prompts>): `ObjectText`/`ActionText`, `KeyboardKeyCode`/`GamepadKeyCode`, tap on touch, `HoldDuration`, `RequiresLineOfSight`, `MaxActivationDistance`; `ProximityPromptService.PromptShown/PromptHidden` for fully custom-styled prompts (set the prompt's Style to Custom — enum detail from API, page didn't state it: **UNVERIFIED** wording). Use: walk up to a poster → "Open" (Detail) / hold "Watch".
- **Lobby design pattern** (judgment): marquee = a long part with an emissive SurfaceGui (`LightInfluence = 0`) cycling hero titles; shelves = wall segments each with a FixedSize SurfaceGui holding a UIListLayout row of ~8–12 posters; the focused/nearest poster lifts with UIScale + UIShadow; a theater screen part hosts the VideoDisplay (§5).
- **ViewportFrame** (stylable: Ambient/LightColor/LightDirection) can render 3D objects inside 2D UI — e.g. a rotating film canister — but each is a render pass; keep to one or two on screen (perf **UNVERIFIED**, general guidance).

### 4.1 Hundreds of posters: assets and memory
- **Every image is a Roblox asset.** Upload via Open Cloud Assets API (<https://create.roblox.com/docs/cloud/guides/usage-assets>): `assetType` Decal/Image; png/jpeg/bmp/tga; "Must be smaller than 8000x8000 pixels"; ≤20 MB; image assets cannot be updated (new asset per change); response carries `moderationResult` — every poster passes Roblox moderation before it renders. Rate limits/quotas for images are not documented on that page (**UNVERIFIED**; plan for throttling with ~26k titles). A pipeline mapping `archiveID → rbxassetid` belongs in the catalog build, like the existing Roku poster fitting.
- **Memory** (<https://create.roblox.com/docs/performance-optimization/improve>): "the number of pixels in the texture determines memory usage"; 1024² = 4x 512²; UI images "usually need at most 512x512"; minor images "smaller than 256x256"; use **sprite sheets** with `ImageRectOffset/ImageRectSize` to load many small images as one. The engine starts with lower-quality textures and raises quality by device memory and camera distance.
  → Upload posters at 2:3 ~342x512 for Detail and build **contact sheets** (e.g. one 1024x1024 sheet = 4 columns x 3 rows = 12 thumbnails at 256x341) for shelves; rows virtualized (only build cards within ±1 screen of focus). Preload the next row with `ContentProvider:PreloadAsync` (API general knowledge; **UNVERIFIED** current guidance).
- **EditableImage** (<https://create.roblox.com/docs/reference/engine/classes/EditableImage>) can compose images at runtime (max 1024x1024, strict client memory budget; must enable "Allow Mesh / Image APIs"; can only load assets the experience owner/player has access to). It cannot fetch arbitrary web images itself; pushing externally fetched pixels into one (server HttpService → client buffer) would bypass asset moderation and is a policy risk — **do not plan on it** (policy position **UNVERIFIED**).

---

## 5. Accessibility, captions, video

- **Player settings** (<https://create.roblox.com/docs/production/publishing/accessibility>): `GuiService.PreferredTextSize` (Medium default → Large/Larger/Largest; respected by normal text, AutomaticSize, TextWrapped, TextService measurement; **ignored by `TextScaled`**, clamped by UITextSizeConstraint) → never use TextScaled for body text. `GuiService.ReducedMotionEnabled` → snap tweens (time 0) or fade with `CanvasGroup.GroupTransparency`; StyleQuery `@ReducedMotionEnabledTrue`. `GuiService.PreferredTransparency` (1 default → 0 opaque) → multiply BackgroundTransparency of overlays (player controls scrim, subtitle box).
- Guidelines: larger small text, strong contrast, don't rely on color alone (>5% color blind) — matches the binding rule that semantic category colors carry meaning and should pair with the category label text — don't rely on sound alone, separate volume groups.
- **Captions**: the accessibility page does not cover captions; **VideoPlayer** (<https://create.roblox.com/docs/reference/engine/classes/VideoPlayer>) has `VideoContent`, `Play/Pause`, `TimePosition`, `TimeLength`, `IsPlaying`, `Looping`, `PlaybackSpeed`, `Volume`, `LoadAsync`, `DidEnd`; it renders through a **Wire** to a **VideoDisplay** (and audio via Wire to an AudioEmitter) — **no caption/subtitle API**. Community consensus: Roblox "lacks a native closed captioning or subtitle system" (<https://devforum.roblox.com/t/add-dynamic-subtitles-and-closed-captions-to-your-roblox-game/2972849>). → Parse SRT/VTT (Archive Watch already has sourced subtitle files) into a Luau table at build time, drive a TextLabel overlay from `VideoPlayer.TimePosition` each frame (binary search), RichText off (avoid injection), honor PreferredTextSize, background scrim × PreferredTransparency. Over a 3D theater screen, place the caption TextLabel in the same SurfaceGui as the VideoDisplay.
- **Video hard limits (critical for a film app)** — <https://create.roblox.com/docs/ui/video-frames>: uploads need 13+ ID verification, **≤5 minutes**, mp4/mov, ≤4096x2160, <3.75 GB, **2,000 Robux per upload**, 20/day (a July 2025 announcement said 10/day: <https://devforum.roblox.com/t/longer-video-uploads-more-video-uploads/3532432> — conflict, **UNVERIFIED** which is current), "a maximum of two videos can play simultaneously", and you must hold the legal rights. Videos can't stream from archive.org URLs. So the Roblox "player" can realistically show trailers/excerpts/clips, not features — a product question for the owner, not a UI one.

---

## 6. Safe areas and responsive layout

- **ScreenGui.ScreenInsets** (<https://create.roblox.com/docs/reference/engine/classes/ScreenGui>): `CoreUISafeInsets` (default; clears the Roblox top bar and cutouts), `DeviceSafeInsets` (device cutouts only), `TopbarSafeInsets` (described in API, not this page), `None` ("only use … for a ScreenGui that contains noninteractive content like background images" — e.g. the hero backdrop wash). `ClipToDeviceSafeArea` default true. `SafeAreaCompatibility`: avoid fullscreen extensions for new work. `IgnoreGuiInset=true` just flips to DeviceSafeInsets. `DisplayOrder` stacks ScreenGuis (browse < detail < player < captions).
- **GuiService:GetGuiInset()** returns top-left/bottom-right insets (only affects ScreenGuis with IgnoreGuiInset false); **`GuiService.TopbarInset`** (Rect) is the free top-bar space next to Roblox's own buttons — watch with `GetPropertyChangedSignal` (that's where a compact title/search affordance can go on phones).
- **Layout** (<https://create.roblox.com/docs/reference/engine/classes/UIListLayout>, <https://create.roblox.com/docs/reference/engine/classes/UIFlexItem>, <https://create.roblox.com/docs/ui/size-modifiers>):
  - UIListLayout is now a flexbox: `Wraps`, `HorizontalFlex`/`VerticalFlex` (UIFlexAlignment), `ItemLineAlignment` (Start/Center/End/Stretch), `Padding`/`HorizontalPadding`/`VerticalPadding`. "Flex layouts require extra calculations" — fine for page chrome, avoid on 100-item rows.
  - UIFlexItem: `FlexMode` Grow/Shrink/Fill/Custom with `GrowRatio`/`ShrinkRatio`, per-item `ItemLineAlignment`.
  - UIGridLayout (`CellSize`, `CellPadding`, `FillDirectionMaxCells`) for the Movies grid; pair with `UIAspectRatioConstraint` (AspectRatio 2/3 for posters — "the constraint will override the layout and control the object's size").
  - `AutomaticSize` for text-driven containers (works with PreferredTextSize), `UISizeConstraint` min/max, `UIScale` for focus lift and whole-UI scaling on TV, `UIPadding` for overscan-safe margins.
  - Responsive switching: StyleQuery `ViewportDisplaySize` / `MinSize` / `AspectRatioRange` instead of script-side breakpoints (mobile-first: base rules for Small, `@` overrides for Medium/Large).

---

## 7. Agent workflow notes (how an AI agent writes this in code)

- **Studio MCP server (built-in)**: <https://create.roblox.com/docs/studio/mcp> (updated 2026-06-11) — local process, stdio transport; lets an AI client explore the data model, read/edit/grep scripts (`script_read`, `multi_edit`, `script_search`, `script_grep`), run Luau, and play-test. The old <https://github.com/Roblox/studio-rust-mcp-server> was **archived 2026-04-03**: "We've shifted ongoing engineering investment to the built-in MCP Server included with Roblox Studio … which we recommend as the best way to connect external AI tools going forward."
- Code-first structure an agent can own end-to-end (judgment): Luau sources in git, packages via Wally (`roblox/react`), file sync into Studio (Rojo — community tool; current status **UNVERIFIED** in this pass), tokens generated from a single JSON shared with the other platforms (one generator emits CSS custom properties for web and a Luau `Tokens` StyleSheet builder for Roblox — keeps the palette single-sourced and the brand/semantic split lintable).
- Verification loop: run play mode via MCP, capture output; screenshots of the Studio viewport for visual checks; test with Studio's Controller Emulator and device emulator — but note the project's "real devices only" rule (Archive Watch DEVICE-TESTING) still applies before shipping; console builds can only be truly verified on an Xbox/PlayStation.

---

## Sources (primary unless noted)
- UI styling: https://create.roblox.com/docs/ui/styling · https://github.com/Roblox/creator-docs/blob/main/content/en-us/ui/styling/css-comparisons.md · https://github.com/Roblox/creator-docs/blob/main/content/en-us/ui/styling/compatibility.md
- Styling announcements: https://devforum.roblox.com/t/client-beta-you-can-now-publish-styles-in-your-experience/3901480 · https://devforum.roblox.com/t/full-release-stylequery-more-styling-features/4566519
- React Luau: https://github.com/Roblox/react-luau · https://www.react-luau.dev/ · https://wally.run/package/roblox/react · https://create.roblox.com/store/asset/15621638430
- Roact (archived): https://github.com/Roblox/roact · jsdotlua: https://github.com/jsdotlua/react-lua
- Fusion: https://github.com/dphfox/Fusion · https://elttob.uk/Fusion/latest · Vide: https://github.com/centau/vide · https://centau.github.io/vide/
- Foundation (community port): https://devforum.roblox.com/t/fusion-foundation-a-fusion-port-of-robloxs-foundation-library-used-to-create-native-components/4706377
- Fonts: https://create.roblox.com/docs/reference/engine/enums/Font · https://create.roblox.com/docs/reference/engine/datatypes/Font · https://create.roblox.com/docs/ui/rich-text · https://devforum.roblox.com/t/fonts-in-creator-marketplace-81-new-fonts/2164977 · https://devforum.roblox.com/t/uploading-custom-fonts-or-workarounds/4731886 (community)
- Input: https://create.roblox.com/docs/reference/engine/classes/GuiService · https://create.roblox.com/docs/reference/engine/classes/GuiObject · https://create.roblox.com/docs/reference/engine/enums/GuiState · https://create.roblox.com/docs/input/gamepad · https://create.roblox.com/docs/input/input-action-system · https://create.roblox.com/docs/production/publishing/console-guidelines · https://create.roblox.com/docs/production/publishing/vr-guidelines
- 3D: https://create.roblox.com/docs/ui/in-experience-containers · https://create.roblox.com/docs/reference/engine/classes/SurfaceGui · https://create.roblox.com/docs/ui/proximity-prompts
- Assets/perf: https://create.roblox.com/docs/cloud/guides/usage-assets · https://create.roblox.com/docs/performance-optimization/improve · https://create.roblox.com/docs/reference/engine/classes/EditableImage
- Accessibility/video: https://create.roblox.com/docs/production/publishing/accessibility · https://create.roblox.com/docs/reference/engine/classes/VideoPlayer · https://create.roblox.com/docs/ui/video-frames · https://devforum.roblox.com/t/longer-video-uploads-more-video-uploads/3532432 · https://devforum.roblox.com/t/add-dynamic-subtitles-and-closed-captions-to-your-roblox-game/2972849 (community)
- Layout/safe areas: https://create.roblox.com/docs/reference/engine/classes/ScreenGui · https://create.roblox.com/docs/reference/engine/classes/UIListLayout · https://create.roblox.com/docs/reference/engine/classes/UIFlexItem · https://create.roblox.com/docs/ui/size-modifiers
- Agent tooling: https://create.roblox.com/docs/studio/mcp · https://github.com/Roblox/studio-rust-mcp-server
