# Q-SYS Plugin — Samsung TV Control

A Q-SYS Designer plugin for controlling Samsung televisions, including **consumer Tizen sets** that the existing MDC plugin cannot reach.

> **Status: pre-alpha.** Protocol research is complete and field-verified. No plugin code has been written yet. See [`docs/samsung-tv-qsys-plugin-research.md`](docs/samsung-tv-qsys-plugin-research.md) for the full technical and market analysis this is built from.

## Why this exists

Q-SYS ships an official plugin for Samsung **commercial** displays over the MDC protocol. Nothing in Asset Manager controls Samsung **consumer** TVs — the Tizen sets sold at retail, which have no MDC and no RS-232.

That gap is structural rather than technical. Q-SYS plugins are overwhelmingly vendor-funded, and Samsung has no incentive to help consumer TVs displace its own commercial display line. So the sites that put consumer Samsungs on the wall — churches, schools, small nonprofits — end up with a Q-SYS core that can control every device in the building except the screens.

Consumer Tizen sets are, in fact, controllable: **Samsung IP Control**, a JSON-RPC 2.0 API over HTTPS on port 1516, handles power (including power-on from fully off), art mode, and full state readback. This plugin wraps that, plus the websocket remote for key presses, plus MDC for commercial panels, behind one normalized Q-SYS component.

## Supported devices

| Class | Transport | Notes |
|---|---|---|
| Consumer Tizen 2020+ | JSON-RPC 1516 + WebSocket 8002 | Primary target. Requires **IP Remote** enabled on the TV. |
| Consumer Tizen 2016–2019 | JSON-RPC 1515 + WebSocket 8002 | Reduced method support; detected by capability probe. |
| The Frame | as above, plus `artModeControl` | Verified on QN50LS03FA (2025). |
| Commercial / signage | MDC over TCP 1515 or RS-232 | Adds picture controls, video wall, panel hours. |
| Any cloud-registered set | SmartThings HTTPS | Fallback when the Core cannot sit on the TV's subnet. |

The plugin **probes capabilities at connect** rather than trusting the model string, and disables controls the device doesn't actually support. This matters because real-world fleets are mixed — TVs bought at retail over several years span multiple firmware generations in one building.

## Planned features

Full specification in [§7 of the research doc](docs/samsung-tv-qsys-plugin-research.md). Summary:

- **Power** — on from fully off, off, toggle, reboot, with true state feedback
- **Input** — select and feedback (consumer sets need a cycle-and-verify loop; `inputSourceControl` is not implemented on them)
- **Audio** — volume up/down, mute, and readback of absolute volume
- **Navigation** — full remote key set, transport keys, numeric pad
- **The Frame** — art mode on/off and state
- **Apps** — app launch by ID, browser URL
- **Commercial tier** — picture controls, video wall, panel on-time, temperature, error status
- **Fleet management** — Q-SYS `Is Managed` status integration, so TVs appear in Core Inventory and status changes raise Event Log alerts
- **Pairing** — one-button token pairing with persistent token storage

## Requirements

- Q-SYS Designer 10.4+ (developed against 10.4.1)
- VS Code — the Plugin Compiler ships as a VS Code build task and supports no other editor
- Q-SYS Core on the **same subnet as the TVs** — Samsung refuses pairing prompts for off-subnet requests
- **IP Remote** enabled per TV: Settings → All Settings → Connection → Network → Expert Settings → IP Remote
- One-time physical pairing at each TV (approval prompt must be accepted on screen)

## Development

### Setup

```
git clone <repo> && cd q-sys-plugin-samsung-tv
git config core.hooksPath .githooks    # enables the pre-commit leak check
code .
```

VS Code extensions are configured in `.vscode/settings.json`; install:

- `integratorblocks.qsys-intellisense` — Q-SYS design-time API completions
- `sumneko.lua` — Lua language server

The workspace settings map `*.qplug` to Lua and declare the Q-SYS runtime globals so the language server doesn't flag them as undefined.

### Building

Plugins ship as a single `.qplug` file but are developed as separate modules, combined by QSC's **Plugin Compiler** (`plugincompile/PLUGCC.exe`, included). `plugin.lua` is the skeleton; it pulls in the other modules with directives:

```lua
--[[ #include "controls.lua" ]]
--[[ #encode "logo.svg" ]]
```

Build with **Run Build Task** in VS Code (`Ctrl+Shift+B`, or bind it under File → Preferences → Keyboard Shortcuts → "Tasks: Run Build Task"). The task prompts for which version octet to increment:

| Argument | Effect on `BuildVersion` |
|---|---|
| `ver_maj` | `1.0.0.0` — major |
| `ver_min` | `x.1.0.0` — minor |
| `ver_fix` | `x.x.1.0` — bugfix |
| `ver_dev` | `x.x.x.1` — development build (default) |
| `ver_none` | leave unchanged |
| `CANCEL` | abort |

The build then: increments `BuildVersion` in `info.lua` · generates the plugin GUID on first build (replacing `"<guid>"`) · expands all `#include` directives and base64-encodes any `#encode` images · writes `<folder-name>.qplug` to the repo root · copies it to `Documents\QSC\Q-Sys Designer\Plugins\<folder-name>\`, where Designer picks it up automatically.

Two consequences worth knowing:

- **The folder name becomes the plugin filename.** Keep the repo directory named `q-sys-plugin-samsung-tv`.
- **`PluginInfo.Id` must never change once published.** Designer uses it to identify the plugin across versions; a new GUID reads as an entirely different plugin.

`files.autoSave` is deliberately off in the workspace settings — the compiler watches files, and autosave causes it to read partial writes.

### Layout

```
*.lua            plugin source modules, compiled together by PLUGCC
  plugin.lua       skeleton — #includes everything else
  info.lua         PluginInfo: name, version, GUID, author
  properties.lua   design-time properties pane
  controls.lua     control definitions
  layout.lua       control positions and graphics
  pages.lua        tabbed UI pages
  runtime.lua      everything that runs on the Core
plugincompile/   QSC Plugin Compiler (PLUGCC.exe + build scripts)
docs/            research, protocol reference, feature specification
docs/site-local/ deployment-specific notes — gitignored, never committed
```

### Testing

Q-SYS Designer bundles a Lua unit test harness at `lua/unittest.lua`, suitable for protocol-level logic — MDC checksums, RPC envelope construction, the input cycle-verify state machine — without requiring a TV.

Device testing requires a real Core on the TV subnet. Designer's emulation mode runs on the authoring PC's network stack, so pairing prompts will not render if that PC is on a different subnet than the TV.

## Known limitations

These are confirmed against hardware, not assumed:

| Want | Reality |
|---|---|
| Absolute volume set on consumer sets | Not available — `directVolumeControl` returns `-32601`. Up/down only. Reads work. |
| Direct input select on consumer sets | Not available — `inputSourceControl` returns `-32601`. Cycle-and-verify only. |
| Power off via websocket | Not possible — `KEY_POWER` only toggles art mode on a Frame. |
| State reads via websocket | None. RPC or nothing. |
| `/api/v2/ PowerState` as truth | Reports `on` while in art mode. Discovery only. |
| Art selection / upload on Frame | The `com.samsung.art-app` channel is closed by the TV on current firmware. |
| Cross-subnet pairing | Approval prompts never render off-subnet; the socket connects and hangs silently. |

Samsung's IP Control and websocket APIs are **unofficial and empirically enumerated**. Firmware updates have broken them before and carry no stability guarantee.

## Credits

Protocol behavior verified against real hardware. Builds on:

- [Samsung IP Control Protocol Reference](https://github.com/serjeleone/ha-samsungtv-smart/blob/main/IP_Control_Protocol_Reference.md)
- [q-sys-community/q-sys-plugin-samsung-display](https://github.com/q-sys-community/q-sys-plugin-samsung-display) (MIT) — structural reference for the MDC tier
- [xchwarze/samsung-tv-ws-api](https://github.com/xchwarze/samsung-tv-ws-api), [Home Assistant `samsungtv`](https://www.home-assistant.io/integrations/samsungtv/)

## License

MIT — see [LICENSE](LICENSE).
