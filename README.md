# Q-SYS Plugin — Samsung TV Control

A Q-SYS Designer plugin for controlling Samsung televisions, including **consumer Tizen sets** that the existing MDC plugin cannot reach.

> **Status: v0.1 — first usable release.** Power on/off, input selection, volume and mute with live state feedback, verified on a 2025 Frame and a 2026 M70H from Designer emulation. Not yet run on a physical Core or through a week of unattended operation; see [Roadmap](#roadmap). Full technical background in [`docs/samsung-tv-qsys-plugin-research.md`](docs/samsung-tv-qsys-plugin-research.md).

## Why this exists

Q-SYS ships an official plugin for Samsung **commercial** displays over the MDC protocol. Nothing in Asset Manager controls Samsung **consumer** TVs — the Tizen sets sold at retail, which have no MDC and no RS-232.

That gap is structural rather than technical. Q-SYS plugins are overwhelmingly vendor-funded, and Samsung has no incentive to help consumer TVs displace its own commercial display line. So the sites that put consumer Samsungs on the wall — churches, schools, small nonprofits — end up with a Q-SYS core that can control every device in the building except the screens.

Consumer Tizen sets are controllable: **Samsung IP Control**, a JSON-RPC 2.0 API over HTTPS on port 1516, handles power (including power-on from standby), input, volume, art mode, and full state readback. This plugin wraps that, plus the websocket remote as a fallback for older sets, behind one normalized Q-SYS component.

## What works today (v0.1)

| Feature | Consumer 2020+ (IP Control) | Consumer 2016–2019 (websocket only) |
|---|---|---|
| Power on from standby / off / toggle, with true state | ✔ verified | on: Wake-on-LAN · off: `KEY_POWER` · no state |
| Input select with readback | ✔ direct (`inputSourceControl`) | blind `KEY_HDMI` |
| Volume — absolute, up/down, mute, readback | ✔ verified | keys only, no readback |
| The Frame — art mode on/off/state | ✔ verified | — |
| Power-on sequence: on → art mode off → land on the configured input | ✔ verified | on → blind key |
| Q-SYS Status / Core Inventory (`IsManaged`) with "TV is off" reported as Compromised | ✔ | ✔ |
| One-button pairing; token persisted with the design | ✔ | ✔ |
| Capability probe at connect; unsupported controls disabled | ✔ | ✔ |
| Raw RPC / raw key escape hatches | ✔ | keys |

Detected automatically: a set that refuses port 1516 but answers on 8001 is placed in the websocket-only tier with an explicit Status message.

## Verified devices

| Model | Year | Class | Notes |
|---|---|---|---|
| QN50LS03FA (The Frame 50") | 2025 | IP Control + Frame | Full feature set. `inputSourceControl`/`directVolumeControl` present when on, `-32601` in standby. |
| UN65M70HD (M70H 65") | 2026 | IP Control | Full feature set; the optional methods are present even in standby. Paired and controlled across subnets. |
| UN55NU6900 (6-series 55") | 2018 | websocket only | No IP Control at all (no *IP Remote* menu item). Websocket tier; pairing must originate on the TV's subnet. |

## Requirements

- Q-SYS Designer 10.4+ (developed against 10.4.1). A Core only accepts designs from a Designer of matching version.
- **IP Remote** enabled on each TV: Settings → All Settings → Connection → Network → Expert Settings → *IP Remote* → On. (Not "Cable Box IP Remote", which is unrelated.) Also enable *Power On with Mobile*.
- Network: the Core needs a **route** to each TV on TCP 1516 and 8001. Same subnet is **not** required for IP Control sets — pairing and control both work across subnets. It *is* required for websocket-only (2016–2019) sets.
- One approval per TV, on screen, the first time it's paired.
- **One controller per TV.** Pairing from any client revokes the previous token. Pair from the Core (or once from a workstation, then push the token into the Core's instance); never test-pair from a laptop against a TV the Core is already using.

## Using it

1. Drop **Samsung → TV Control** from Schematic Elements → Plugins.
2. Properties: set **IP Address** and **Input After Power-On**. Defaults are fine otherwise.
3. Run the design. Status shows *Not paired — press Pair (RPC)*. Open the panel → **Setup** → **Pair (RPC)**, press **Allow** on the TV. Save the design — the token is stored in it.
4. Wire pins as needed: **Power Off** from a Scheduler, **Status** into a Status Combiner, etc. UCIs bind to the controls directly.

Properties worth knowing:

| Property | Default | Purpose |
|---|---|---|
| Poll Interval | 10 s | `getTVStates` + `powerControl` per interval. 0 disables. |
| Power-On Method | RPC | `WoL` for sets without IP Control (automatic on that tier). |
| Input After Power-On | None | Input to land on after every power-on and every art-mode exit. |
| Power Off Reports As | Compromised | Shows a TV in standby as orange in Core Manager / inventory. `OK` for sets meant to be off. |
| MAC Address | (learned) | Only needed for WoL when the TV is off at design load. |

## Development

### Setup

```
git clone <repo> && cd qsys-samsung-plugin
git config core.hooksPath .githooks    # enables the pre-commit leak check
code .
```

VS Code extensions (configured in `.vscode/settings.json`): `integratorblocks.qsys-intellisense`, `sumneko.lua`.

### Building

Plugins ship as one `.qplug` but are developed as modules combined by QSC's **Plugin Compiler** (`plugincompile/PLUGCC.exe`, included) via `--[[ #include "file.lua" ]]` directives in `plugin.lua`.

```
tools/build.sh            # bump dev version, compile, install into Designer's plugin folder
tools/build.sh ver_min    # bump minor instead (ver_maj / ver_fix / ver_none also accepted)
```

Designer only reloads a plugin whose version changed, so every build bumps by default. The VS Code build task (`Ctrl+Shift+B`) does the same thing interactively.

- **The folder name becomes the plugin filename** (`qsys-samsung-plugin.qplug`).
- **`PluginInfo.Id` must never change once published.** Designer uses it to identify the plugin across versions.

### Layout

```
plugin.lua            skeleton — #includes everything below
info.lua              PluginInfo: name, version, GUID, IsManaged
properties.lua        design-time properties pane
controls.lua          control inventory and pins
layout.lua            control positions and graphics (Control / Setup pages)
runtime.lua           #includes src/ in order
src/log.lua           debug printing gated by the Debug Print property
src/rpc.lua           JSON-RPC over HttpClient: envelope, classification, serialized queue
src/ws.lua            Tizen websocket key sender: pairing, pacing, reconnect
src/device.lua        state machine, capability probe, polling, power/input sequences
src/ui.lua            control event handlers
tools/                build script, QRC helpers, test harness, unit tests
docs/                 research, protocol reference, feature specification
docs/site-local/      deployment-specific notes — gitignored, never committed
```

### Testing

There is no standalone Lua on a typical Designer workstation, so tests run **inside the emulator** and are driven over QRC (JSON-RPC on TCP 1710, which Designer's emulator exposes on localhost):

1. Create a design with one **Control Script** whose *Script Access* property is `All`, and emulate it.
2. `python tools/qrc_push_run.py tools/test_rpc.lua 10` — unit tests for the RPC module (no TV needed).
3. `tools/run_scenario.sh readonly 30 <tv-ip> <rpc-token>` — runs the plugin's real `src/` modules against a TV with faked `Properties`/`Controls`. Scenarios: `readonly`, `audio`, `steer`, `artmode`, `poweroff`, `poweron`.

A plugin instance with *Script Access = All* can likewise be read and driven over QRC (`tools/qrc.py`), which is how the verified-device results above were produced.

## Known limitations

Confirmed against hardware:

| Want | Reality |
|---|---|
| Select an input with nothing connected | The TV accepts the call and stays put (verified M70H). There is no API that lists connected inputs, so the plugin keeps every input selectable and reports *"TV declined to switch — is a device connected?"* |
| State right after leaving Art Mode | `getTVStates` still reports the previous input while the screen shows the Smart Hub. The plugin re-issues the input after every art-mode exit. |
| Capability probe while in standby (Frame) | `inputSourceControl` / `directVolumeControl` report `-32601` until the TV is on. The plugin re-probes on the first off→on transition. |
| Power off via websocket on a Frame | `KEY_POWER` toggles Art Mode instead. RPC only. |
| State reads via websocket | None. |
| Websocket pairing across subnets | Refused (`ms.channel.timeOut`). Only matters for 2016–2019 sets. |
| Bad/revoked token | The TV answers `-32700 Parse error`, not `-32010`. Both are treated as *re-pair*. |

Samsung's IP Control and websocket APIs are **unofficial and empirically enumerated**. Firmware updates carry no stability guarantee.

## Roadmap

- **0.2** — full remote key set, app launch, device info, example UCI, `Debug Print` through every transport; run on a physical Core; a week unattended on a mixed fleet.
- **1.0** — MDC tier for commercial panels, SmartThings fallback, Asset Manager submission.

## Credits

Protocol behavior verified against real hardware. Builds on:

- [Samsung IP Control Protocol Reference](https://github.com/serjeleone/ha-samsungtv-smart/blob/main/IP_Control_Protocol_Reference.md)
- [q-sys-community/q-sys-plugin-samsung-display](https://github.com/q-sys-community/q-sys-plugin-samsung-display) (MIT) — structural reference for the MDC tier
- [xchwarze/samsung-tv-ws-api](https://github.com/xchwarze/samsung-tv-ws-api), [Home Assistant `samsungtv`](https://www.home-assistant.io/integrations/samsungtv/)

## License

MIT — see [LICENSE](LICENSE).
