# Roblox: git-based toolchain + autonomous testing with an AI agent (macOS), October 2026

Researched 2026-10-15. Sources: Roblox's own docs (read as Markdown, each page stamped
`last_updated: 2026-10-15`), GitHub repo metadata and release notes read through the GitHub API
on the same day, and the Roblox newsroom. Anything not confirmed in a primary source is marked
**UNVERIFIED**.

---

## 0. The short answer

Roblox now supports the "agent writes code in git, drives Studio itself" workflow directly:

- **Studio has a built-in MCP server.** Its 26 tools cover running Luau, starting and stopping
  playtests, reading the Output log, taking viewport screenshots and simulating keyboard, mouse
  and character movement. Claude Code is one of its "quick connect" clients. On macOS the binary
  is `/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`
  (https://create.roblox.com/docs/studio/mcp). The older standalone
  `Roblox/studio-rust-mcp-server` was **archived in April 2026** in favor of the built-in server
  (https://github.com/Roblox/studio-rust-mcp-server).
- **Roblox publishes a guide called "Build with a coding harness."** It walks through Script Sync
  plus the MCP server plus git, and names Claude Code
  (https://create.roblox.com/docs/ai/coding-harness).
- **Headless or cloud test execution** runs through the Open Cloud **Luau Execution API**
  (Roblox abbreviates it "OCALE"). It is stable, scripts run up to 5 minutes, and a place allows
  10 tasks in flight. Jest Roblox, which Roblox maintains, documents OCALE as its CI path.
- **Studio can be launched from a script.** The CLI has `--task RunScript --runScriptFile …
  --outputFile … --quitAfterExecution`, which gives a local, scriptable, non-interactive run on
  the Mac (https://create.roblox.com/docs/studio/command-line-interface).
- **Multi-client tests can be scripted.** `StudioTestService:ExecuteMultiplayerTestAsync(n, args)`
  starts a server plus up to 8 clients from a plugin
  (https://create.roblox.com/docs/reference/engine/classes/StudioTestService).
- **No route to real devices.** No official way was found to push a playtest to a real phone,
  console or VR headset, or to drive one automatically. Device tests stay manual, using
  published or private test places.

---

## 1. Toolchain: what is current in October 2026

Maintenance status was read from the GitHub API on 2026-10-15.

| Tool | Role | Latest release | Status |
|---|---|---|---|
| **Luau** (luau-lang/luau) | Language | repo pushed 2026-10-10 | Active |
| **Rojo** (rojo-rbx/rojo) | Sync between files and Studio, plus building `.rbxl` | **v7.7.1** (2026-10-02); v7.7.0 (2026-07-02) | Active. 7.7 added `rojo syncback` (turn an existing place into a project), moved to websockets and MessagePack, and fixed macOS paths (#1201) — https://github.com/rojo-rbx/rojo/releases/tag/v7.7.0 |
| **Wally** (UpliftGames/wally) | Package manager | v0.3.2 is stable (2023); **v0.4.0-alpha.1** (2026-10-12) | Revived in Sept–Oct 2026. The 0.4 alphas add `--locked`, new lockfile formatting and aarch64 macOS binaries — https://github.com/UpliftGames/wally/releases |
| **pesde** (pesde-pkg/pesde) | Alternative package manager covering Roblox and Lune | v0.7.4 (2026-09-09) | Active, but small (128 stars) |
| **Rokit** (rojo-rbx/rokit) | Pins tool versions | v1.2.0 (2025-09-30); repo pushed 2026-09-27 | **Recommended.** It is a drop-in replacement for Foreman and Aftman and reads their manifests — https://github.com/rojo-rbx/rokit |
| **Aftman** (LPGhatguy/aftman) | Pins tool versions | — | **Archived and unmaintained.** Its README recommends mise — https://github.com/LPGhatguy/aftman |
| **Foreman** (Roblox/foreman) | Pins tool versions | v1.7.0 (2026-05-01) | Maintained by Roblox and used in Roblox's own CI demo. Rokit is the community default. |
| **selene** (Kampfkarren/selene) | Linter | 0.32.0 (2026-10-01) | Active |
| **StyLua** (JohnnyMorganz/StyLua) | Formatter | v2.6.0 (2026-10-10) | Active |
| **luau-lsp** (JohnnyMorganz/luau-lsp) | Language server, plus **`luau-lsp analyze`** for type checking in CI | 1.70.1 (2026-09-27) | Active. The README says it "can run standalone … to provide type and lint warnings in CI, with full Rojo resolution and API types support", and it resolves the DataModel from a Rojo `sourcemap.json` — https://github.com/JohnnyMorganz/luau-lsp |
| **darklua** (seaofvoices/darklua) | Transforms Luau source (string requires, bundling, stripping) | v0.19.0 (2026-06-10) | Active. Roblox now supports **require-by-string natively** (`./`, `../`, `@self/`, `@game/`; https://create.roblox.com/docs/reference/engine/globals/LuaGlobals), so darklua matters less than it did. Its remaining use is code shared between Lune and Roblox, or bundling. |
| **Lune** (lune-org/lune) | Standalone Luau runtime | **v0.11.0** (2026-10-11): Luau 0.740, rbx-dom 0.741 | Active. Its `roblox` library reads and writes place and model files and has Roblox datatypes — https://github.com/lune-org/lune/releases/tag/v0.11.0 |
| **Jest Roblox** (Roblox/jest-roblox) | Test framework (port of Jest 27.4.7) | Wally `roblox/jest@3.20.0` (from the README) | **Active and maintained by Roblox** (pushed 2026-10-02). "Can run within Roblox itself, including via Roblox's OCALE … for testing on CI systems." — https://github.com/Roblox/jest-roblox |
| **TestEZ** (Roblox/testez) | Older BDD test framework | — | **Archived** (last push 2024-03). Do not start new work on it. |
| **run-in-roblox** (rojo-rbx/run-in-roblox) | Ran a place in Studio from a CLI | v0.3.0 (2020) | **Stale.** Studio's own `--task RunScript` replaces it. |
| **jsdotlua/jest-lua** | Jest for plain Lua | last push 2024-12 | Dormant |

### Script Sync (Roblox's own alternative to Rojo)
Studio's **Script Sync** (beta, enabled under File ▸ Beta Features) mirrors scripts to `.luau`
files in both directions. It uses the suffixes `.server.luau`, `.client.luau`, `.local.luau`,
`.plugin.luau` and `init.*.luau`. It works with Team Create and has a dialog for resolving
conflicts. Limits: it syncs **scripts only**, it ignores attributes and tags on scripts, and it
allows 10,000 scripts per synced root and 128 roots. Roblox's own advice: "If you want to check
your entire project (not just code) into version control or use your file system as the source of
truth … third-party tools like Rojo are a better choice."
(https://create.roblox.com/docs/scripting/sync, DevForum beta thread
https://devforum.roblox.com/t/studio-script-sync-now-in-beta/4065468)

**Recommendation for an agent-run repo:** run Rojo as a *fully managed* project, so the
filesystem is the source of truth and CI can build the `.rbxl` with no Studio involved. That is
also the precondition Roblox's own CI demo states. Script Sync suits a place that is edited mostly
by hand in Studio, which is the opposite of an agent-first workflow.

### Recommended layout (fully managed Rojo)
```
rokit.toml            # rojo, wally (or pesde), selene, stylua, luau-lsp, lune, darklua — pinned
default.project.json  # production tree: src/ → ReplicatedStorage/ServerScriptService/StarterPlayer…
test.project.json     # production tree + tests + Jest packages (DevPackages)
wally.toml / wally.lock
selene.toml           # std = "roblox"
stylua.toml
.luaurc               # languageMode strict, aliases
src/
  shared/             # pure logic: no game:GetService at module top level, so it runs in Lune
  server/             # *.server.luau
  client/             # *.client.luau
  assets/ (.rbxm/.model.json for non-script instances, maps)
tests/
  unit/               # run under Lune (pure logic)
  integration/__tests__/*.spec.luau   # Jest Roblox, run in Studio or OCALE
  runTests.server.luau / tasks/runTests.luau   # entry point that calls Jest.runCLI and returns results
scripts/ci/           # OCALE client (create task → poll → fetch logs), publish
sourcemap.json        # generated (rojo sourcemap) — gitignored
```
This layout is a synthesis: it combines Roblox/place-ci-cd-demo, the Jest Roblox README and the
luau-lsp sourcemap guidance. No single source prescribes it.

---

## 2. Studio on macOS: CLI, MCP and Assistant

### 2a. The Studio command line
Source: https://create.roblox.com/docs/studio/command-line-interface

- Executable: `/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio`. Flags use `--` and
  are case-insensitive. Studio writes **verbose logs to stdout** when launched from a command
  line.
- `--task EditFile --localPlaceFile <abs path>` opens a local `.rbxl` or `.rbxlx`.
  `--task EditPlace --placeId --universeId` opens a published place.
- **`--task RunScript --runScriptFile <abs .luau> [--outputFile <path>] [--quitAfterExecution]`**,
  optionally with `--localPlaceFile` or `--placeId`/`--universeId`. "Scripts run at the same
  permission level as the Studio command bar." This is the local building block for
  non-interactive runs: build with Rojo, then RunScript a test entry point, then read
  `--outputFile`.
- `--api`, `--fullApi` and `--apiV2 <path>` dump the API surface as JSON (useful for luau-lsp
  definitions).
- **There is no documented headless mode.** RunScript still launches the GUI app and needs a
  signed-in user on the Mac. **UNVERIFIED** whether RunScript can enter Play mode or reach
  `StudioTestService:ExecuteMultiplayerTestAsync`: that method is "plugin scripts only", and the
  command bar's permission level is not documented as equal to a plugin's.

### 2b. The built-in Studio MCP server
Source: https://create.roblox.com/docs/studio/mcp

- **Enable:** Assistant ▸ … ▸ Manage MCP Servers ▸ "Enable Studio as MCP server". A green
  indicator shows how many clients are connected. Transport is **stdio**.
- **Connect Claude Code:** Assistant Settings ▸ MCP Servers ▸ Quick connect ▸ Claude Code, or by
  hand: `claude mcp add roblox-studio -- /Applications/RobloxStudio.app/Contents/MacOS/StudioMCP`.
  The doc gives the macOS command path; the `claude mcp add` syntax is the standard Claude Code
  form.
- **The 26 tools:**
  - Scripts: `script_read`, `multi_edit`, `script_search`, `script_grep`.
  - Generation: `generate_mesh`, `generate_material`, `generate_procedural_model`,
    `wait_job_finished`, `search_asset`, `insert_asset`, `upload_image`, `store_image`.
  - DataModel: `search_game_tree`, `inspect_instance`, `subagent` (launches `explore` or
    `playtest` subagents).
  - **`execute_luau`** (`datamodel_type`: Edit, Client or Server, so code can run on either side
    of a live playtest).
  - **Playtesting:** `get_studio_state`, `start_stop_play`, `get_console_output`,
    **`screen_capture`** (viewport, with optional camera position and look-at target).
  - **Input simulation:** `character_navigation`, `user_keyboard_input`, `user_mouse_input`.
  - Docs: `http_get`, `skill`.
  - Sessions: `list_roblox_studios`. Every call takes a `studio_id`, so one agent can drive
    several open Studios.
- **Limits:** Studio must be running and signed in. `start_stop_play` is a **single** Play Client
  session; the StudioTestService doc says so explicitly and points to it for multi-client runs.
  Cost and quota for the generation tools are not documented on this page.

### 2c. Assistant
Sources: https://create.roblox.com/docs/assistant/guide,
https://about.roblox.com/newsroom/2026/04/roblox-studio-going-agentic (2026-04-15)

- Assistant has Planning Mode, a screen-capture subagent ("If you're using a third-party client
  via MCP … you continue to have direct access to the underlying screenshot tool"), mesh and
  procedural-model generation (procedural models: 50 per rolling 24 h) and a **playtesting agent
  (beta)** that "uses the player character as an automated QA tester". According to the newsroom
  post, 44% of the top 1,000 creators use Assistant or third-party AI through MCP.
- For Claude Code, Assistant itself is optional: the MCP server is the interface. Assistant can
  also *consume* other MCP servers (https://create.roblox.com/docs/assistant/mcp; not read in
  depth).

### 2d. Roblox's own coding-harness recipe
Source: https://create.roblox.com/docs/ai/coding-harness

The recipe is VS Code + the Claude Code extension (or Cursor) + git + Script Sync + MCP. Its
verification prompt has the agent call
`game:GetService("InstanceFileSyncService"):GetStatus(instance)` and "start a playtest to confirm
the output." It is a Script Sync recipe. A Rojo setup does the same job and suits CI better.

### 2e. Third-party MCP servers
These include robloxstudio-mcp, Ropilot and paralov/roblox-studio-opencode-mcp
(https://glama.ai/mcp/servers/paralov/roblox-studio-opencode-mcp/tools/roblox_playtest,
https://ropilot.ai/roblox-mcp-server). Since the built-in server exists, they are no longer
needed. One documented weakness of the plugin-polling designs: `RunService:Run()` is not the same
as Play Solo, because no local player character is created.

---

## 3. Automated testing: layer by layer

| Layer | Tool | Runs where | What it can prove |
|---|---|---|---|
| Static | `luau-lsp analyze` (strict types, with sourcemap and Roblox definitions), selene, `stylua --check` | Anywhere, including Linux CI | Types, lint, formatting |
| Pure-logic unit tests | **Lune** plus a small Luau test runner (for example `itsfrank/frktest`, tiny and last pushed 2025-09), or a hand-rolled `describe`/`expect` | Anywhere, in milliseconds, with no credentials | Game rules, math, state machines, serialization. Keep `src/shared` free of engine services so it runs here. Lune's `roblox` library has Vector3, CFrame and similar datatypes and can load `.rbxl` files to assert on structure. |
| Engine integration (single DataModel) | **Jest Roblox** run through the **Open Cloud Luau Execution API** | Roblox cloud, against an uploaded test place version | Real engine APIs, the DataModel, module wiring and DataStores (which are real: use a separate test universe) |
| Engine integration (local) | Jest Roblox through `--task RunScript … --quitAfterExecution`, or through MCP `execute_luau` | The Mac's Studio | Same as above, without the cloud quota |
| Live playtest, client and server | MCP `start_stop_play` + `execute_luau` (Client/Server) + `get_console_output` + `screen_capture` + input simulation | The Mac's Studio, with an agent driving | Replication, input, UI, "does it look right" |
| Multiplayer flows | **StudioTestService** (`ExecuteMultiplayerTestAsync(n≤8, args)`, `AddPlayers`, `EndTest(value)`, `LeaveTest`, `GetTestArgs`) | The Mac's Studio, launched from a plugin | Lobby, matchmaking, join/leave, races |
| Devices | Manual sessions on real hardware against a private test place | Real phones, consoles and headsets | Memory, frame rate, heat, touch and gamepad input, cellular networks |

### 3a. The Open Cloud Luau Execution API ("OCALE")
Source: https://create.roblox.com/docs/cloud/reference/features/luau-execution.md

- **Status:** every endpoint is **Stable**.
- **Endpoints:**
  - `POST /cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks`
    with `{ script, timeout?, binaryInput?, enableBinaryOutput? }`.
  - Poll with `GET …/luau-execution-sessions/{s}/tasks/{t}`. The state is QUEUED, PROCESSING,
    COMPLETE, FAILED or CANCELLED.
  - Fetch output with `GET …/tasks/{t}/logs` (`maxPageSize` up to 10,000).
  - Large inputs: `POST /cloud/v2/universes/{u}/luau-execution-session-task-binary-inputs`.
- **Auth:** an API key in `x-api-key`, with scopes `universe.place.luau-execution-session:write`
  and `:read`.
- **The environment** is a headless server DataModel of the given place version. "Physics
  simulation does not run. Server and local scripts within the place also do not automatically
  run." DataModel changes are not persisted (except through `AssetService:SavePlaceAsync`). It
  **can call DataStores and other cloud APIs**: "Exercise caution." There are no players and no
  clients.
- **Limits:**
  - Script size: 4 MB. Runtime: up to **5 minutes** (the default `timeout`).
  - Return values: 4 MB after JSON serialization. Logs: 450 KB, oldest dropped first. Task
    records are kept for 24 h.
  - **At most 10 incomplete tasks per place**; the 11th gets HTTP 429.
  - Binary input: 100 MiB, valid for 15 min. Binary output: 256 MiB.
  - Rate limits per API-key owner: create **5/min**, get 200/min, logs 45/min, binary-input
    5/min.
- **Pricing:** no price appears on the reference page or the Open Cloud index. **UNVERIFIED** that
  it is free; nothing found says it is billed.
- **Stale note to ignore:** the Roblox/place-ci-cd-demo README (repo last pushed 2024-09) says
  "limited to two concurrent request per universe". The current reference says 10 per place.
  Keeping a GitHub `concurrency:` group is still sensible because of the 5/min create limit.
- **Reference implementation:** https://github.com/Roblox/place-ci-cd-demo runs selene,
  StyLua, then `rojo build` → upload the test place → OCALE `tasks/runTests.luau` → on the
  `production` branch, `rojo upload`. Its README calls itself "not battle tested".

### 3b. Jest Roblox
Sources: https://github.com/Roblox/jest-roblox, https://roblox.github.io/jest-roblox/

- Tests are `*.spec.luau` files under `__tests__/`. The entry point calls
  `Jest.runCLI(root, { ci = true, … }, { projects })`. `ci = true` makes a new snapshot fail
  instead of being written.
- Its docs show `ProcessService:ExitAsync(code)` and `roblox-cli`. That CLI is Roblox's
  internal tool and **is not publicly distributed** (**UNVERIFIED**, but no public download
  exists). For OCALE, have the entry script `return` the results table and exit by FAILED or
  COMPLETE state.
- Coverage: `ScriptContext:EnableCoverage` and `GetCoverageStats` exist in the engine API
  (https://create.roblox.com/docs/reference/engine/classes/ScriptContext). **UNVERIFIED**
  whether they are reachable from OCALE or RunScript.

### 3c. Multi-client playtests
Source: https://create.roblox.com/docs/reference/engine/classes/StudioTestService

- By hand: Test ▸ "Server & Clients", up to 8 clients, F7
  (https://create.roblox.com/docs/studio/testing-modes). The Party Simulator emulates
  `SocialService` parties.
- **Scripted:** `StudioTestService:ExecuteMultiplayerTestAsync(numPlayers, args)` is
  plugin-only, yields until the server calls `EndTest(value)` and returns that value. It allows
  8 clients and one session per Studio. `AddPlayers(1..8)` runs from the server;
  `LeaveTest` and `CanLeaveTest` run from clients. There is a known issue with `GetTestArgs`
  from a client LocalScript. Also available: `ExecutePlayModeAsync` and `ExecuteRunModeAsync`.
- **Pattern for the agent:** keep a small local plugin, synced by Rojo into the Studio plugins
  folder (`rojo build -o ~/Documents/Roblox/Plugins/…`; that path on macOS is **UNVERIFIED**).
  The plugin watches a trigger (for example an attribute set through MCP `execute_luau` in the
  Edit DataModel), runs `ExecuteMultiplayerTestAsync`, and prints a JSON result that the agent
  reads with `get_console_output`. **UNVERIFIED** whether MCP `execute_luau` (Edit) can call
  `ExecuteMultiplayerTestAsync` directly: the MCP doc does not give its security level.
- **None of this runs in the cloud.** OCALE has no clients. Multi-client tests need a Mac with a
  signed-in Studio, which means a self-hosted macOS runner or the developer's machine. A hosted
  GitHub macOS runner cannot log Studio in. That is an inference; no documented Studio login
  flow for CI exists.

### 3d. UI and screenshot testing
- MCP `screen_capture` (optionally with a camera position and look-at target) plus
  `user_mouse_input`/`user_keyboard_input` allow agent-judged visual checks. There is no built-in
  pixel-diff or golden-image tooling; anything like that has to be built (save captures, compare
  them in a Lune or Python script). **UNVERIFIED** whether `screen_capture` returns the image
  bytes to the client or only a description.
- Logic-level UI tests (component trees, React-lua/Fusion state) run in Jest Roblox through OCALE
  without rendering.
- Device Simulator (beta) emulates screen sizes and input types inside Studio
  (https://create.roblox.com/docs/studio/device-simulator).

### 3e. Real devices
Source: https://create.roblox.com/docs/performance-optimization/test-on-hardware

- Roblox: the emulator "isn't accurate for memory usage"; touch, gamepad polling and cellular
  networks "can only be validated on real hardware." On device, use the Developer Console (F9),
  the MicroProfiler (⌘⌥F6, frame dumps analyzed on the dev machine) and Performance Stats. The
  guidance suggests a thermal-throttling soak of 10–15 minutes. Android is "~65%" of a typical
  player base, and ~60% of those devices have 2–4 GB of RAM. The page also names a sample device
  list.
- **No automation or remote-play API was found.** A DevForum *feature request* for "Remote play
  from studio to any roblox supported device" (active Aug 2026) suggests none ships today. Real
  devices join a private or unlisted test place. Observability comes from what the server records
  (LogService, analytics), not from driving the device.

---

## 4. CI: a GitHub Actions recipe

Built from Roblox/place-ci-cd-demo plus the current docs.
```yaml
jobs:
  static:            # ubuntu-latest
    - uses: actions/checkout@v4
    - uses: CompeyDev/setup-rokit@v0.1.2   # installs tools from rokit.toml (action name UNVERIFIED; else curl the rokit installer)
    - run: wally install          # or pesde install
    - run: rojo sourcemap default.project.json -o sourcemap.json
    - run: stylua --check src tests
    - run: selene src tests
    - run: luau-lsp analyze --sourcemap=sourcemap.json --definitions=globalTypes.d.luau --settings=.vscode/settings.json src
  unit:              # ubuntu-latest, no secrets → safe for forks
    - run: lune run tests/unit/run
  integration:       # needs: [static, unit]; secrets
    concurrency: { group: ocale-test-place, cancel-in-progress: false }
    - run: rojo build test.project.json -o test.rbxl
    - run: |  # upload as a SAVED (not published) version of the TEST place
        curl -X POST "https://apis.roblox.com/universes/v1/$TEST_U/places/$TEST_P/versions?versionType=Saved" \
          -H "x-api-key: $ROBLOX_API_KEY" -H 'Content-Type: application/octet-stream' --data-binary @test.rbxl
        # → {"versionNumber": N}
    - run: python scripts/ci/ocale.py --universe $TEST_U --place $TEST_P --version $N --script tasks/runTests.luau
        # POST …/versions/N/luau-execution-session-tasks ; poll until COMPLETE/FAILED ; GET logs ; exit non-zero on failures
  deploy:            # on push to main/production only, needs all
    - run: rojo build default.project.json -o game.rbxl
    - run: curl -X POST ".../universes/v1/$PROD_U/places/$PROD_P/versions?versionType=Published" ... --data-binary @game.rbxl
      # or: rojo upload default.project.json --api_key … --universe_id … --asset_id …
```
**Place publishing API**
(https://create.roblox.com/docs/cloud/guides/usage-place-publishing; reference
https://create.roblox.com/docs/cloud/reference/features/places.md):

- `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Saved|Published`
  with a `.rbxl` (`application/octet-stream`) or `.rbxlx` (`application/xml`) body. It returns
  `{"versionNumber": N}`.
- The API key needs the `universe-places` Write permission (`universe.places:write`). The
  endpoint is marked **BETA**, at 30 requests/min.
- **It does not update** EditableImage, EditableMesh, PartOperation (unions), SurfaceAppearance
  or BaseWrap instances. Places containing those still have to be published from Studio.
  `llms.txt` also lists a v2 path (`/cloud/v2/universes/{u}/places/{p}/versions`); the guide uses
  v1.

**Keys:** use one API key restricted to the test universe (luau-execution read/write and place
write) and a separate production key that can only publish. Use IP restrictions where the CI
egress allows them. Fork pull requests get no secrets, so only the static and unit jobs run on
them; the demo's README says the same.

**Local agent loop on the Mac, which is faster than CI:**

1. Run `rojo serve`; Studio's Rojo plugin connects.
2. Edit files.
3. Use MCP `execute_luau` (Edit) to run Jest in place, or `start_stop_play` +
   `get_console_output` + `screen_capture` for behavior.
4. Run StudioTestService through the helper plugin for multiplayer tests.
5. Push; CI repeats the deterministic layers.

---

## 5. Observability

| Need | Mechanism | Source |
|---|---|---|
| Capture logs in game | `LogService.MessageOut(message, messageType, context)`, `LogService:GetLogHistory()` | https://create.roblox.com/docs/reference/engine/classes/LogService |
| Uncaught script errors | `ScriptContext.Error` (message, stack, script), on the server and on the client (forward from the client through a remote, with rate limiting) | https://create.roblox.com/docs/reference/engine/classes/ScriptContext |
| Production error dashboard | Creator Hub ▸ Monitoring ▸ **Error Report**: server and client Luau errors and warnings "up-to-the-minute", stack traces. Filters by date range (1 h to 30 d), place, version annotations, severity, platform, OS and "new errors since" a version. Up to 100 regex or exact rules to ignore or group noise. | https://create.roblox.com/docs/production/analytics/error-report |
| Product analytics | `AnalyticsService:LogCustomEvent(player, name, value?)`: up to **100 custom events**, aggregated daily (charts appear in ≤ 24 h). Events can be sent **only from the server and only in published games, not from Studio or the client.** Funnel and economy events follow the same model. All are **free**. **View Events** gives a near-real-time list for checking events. | https://create.roblox.com/docs/production/analytics/custom-events, https://create.roblox.com/docs/production/analytics/event-types |
| Dashboards | Analytics dashboard (engagement, retention, monetization, performance) in Creator Hub | https://create.roblox.com/docs/production/analytics/analytics-dashboard |
| Programmatic metrics | **Analytics Query API** `POST https://apis.roblox.com/analytics-query-api/v1/universes/{id}/metrics` (scope `universe.analytics:read`): DAU, revenue, retention and more, with breakdowns by platform, country and age. Long queries become operations to poll. | https://create.roblox.com/docs/cloud/guides/analytics |
| Device performance | Performance dashboard plus on-device MicroProfiler and Developer Console | https://create.roblox.com/docs/performance-optimization/test-on-hardware |

**Consequence for testing analytics:** because custom events cannot be emitted from Studio or
from OCALE (no players), wrap `AnalyticsService` behind a module that can be swapped out. Unit
tests assert on the calls that wrapper receives. A published, private test place plus
**View Events** is the only end-to-end check.

---

## 6. Open questions to settle by experiment (all UNVERIFIED)

1. Can `--task RunScript` (command-bar permission) or MCP `execute_luau` call
   `StudioTestService:ExecuteMultiplayerTestAsync`, or is a real plugin required?
2. Does `--task RunScript … --quitAfterExecution` work unattended on macOS (no dialogs, Studio
   already signed in), and how long does a cold launch take?
3. Does MCP `screen_capture` return image bytes to Claude Code (needed for golden-image diffs)?
4. Is OCALE free with no hidden quota beyond the documented rate limits?
5. Are `ScriptContext` coverage APIs available inside OCALE?
6. Does the Wally 0.4 alpha's lockfile change break a CI cache keyed on `wally.lock`?
7. Which GitHub Action installs Rokit (`CompeyDev/setup-rokit` assumed), or should the
   installer script be curled instead?
8. The Luau new type solver's status: secondary sources say it reached GA in late 2025 and
   became the default in early 2026. Not confirmed from a primary source; the type-checking doc
   page does not mention a solver version.
