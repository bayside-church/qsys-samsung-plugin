# Q-SYS Plugin for Full Samsung TV Control — Research & Scoping

Date: 2026-09-16
Revised 2026-09-16 with findings from live testing on a 50" The Frame QN50LS03FA (2025, Tizen). Those findings replace the earlier assumption that consumer sets have no local control API.

---

## 1. What Q-SYS is (qsys.com)

Q-SYS is QSC's software-based audio/video/control (AV&C) platform. Relevant facts for plugin work:

- **Core**: the processor (hardware Core 8/110f/510i/610/Nano, or Core Cloud/NV series). Runs the compiled design. Everything you write executes here.
- **Q-SYS Designer Software (QDS)**: free Windows authoring tool. Schematic canvas of components, UCI (user control interface) editor, Asset Manager, emulation mode.
- **Control layer**: Lua 5.3-based. Three flavors:
  - **Control Script** component — raw Lua in a design.
  - **Block Controller** — visual/blocky wrapper that generates Lua.
  - **Plugin (`.qplug`)** — a *packaged, reusable, distributable* component that shows up in the Schematic Elements library with its own properties pane, control pins, and custom UI. This is what you want.
- **Q-SYS Extensions to Lua** (the API surface you get): `TcpSocket`, `UdpSocket`, `TcpSocketServer`, `WebSocket`, `HttpClient`, `Ssh`, `SerialPorts`, `SNMP`, `Ping`, `Timer`, `JSON`/`RapidJSON`, `LuaXML`, `Network`, `Log`, `Notifications`, `Design`, `System`, `UCI`, `EzSVG`, `QRCode`, `LuaDate`, `LPeg`, bitstring. No `io`/`os.execute`, no arbitrary filesystem, no LuaSocket, no external C modules. Sandboxed.
- **Distribution**: plugins are dropped in `%USERPROFILE%\Documents\QSC\Q-Sys Designer\Plugins` for dev/user use; official ones ship via **Asset Manager** (in-Designer repository). QSC runs a **Technology Partner Program** with "verified"/"certified" plugin badges — certification is a collaboration between the hardware vendor, QSC, and a Developer Partner.

### 1.1 Anatomy of a `.qplug`

One Lua file, two halves. Design-time functions are called by Designer; the runtime half only executes when `Controls` exists (i.e. the design is loaded/emulated).

```lua
PluginInfo = {
  Name = "Samsung~TV Control",   -- "~" makes a folder in the library
  Version = "1.0.0",
  Id = "<stable GUID — never change it>",
  Author = "You",
  Description = "Control of Samsung Tizen consumer TVs and MDC signage",
}

function GetColor(props) end          -- component color on canvas
function GetPrettyName(props) end     -- canvas label
function GetProperties()  end         -- properties pane (string/integer/boolean/enum)
function RectifyProperties(props) end -- show/hide properties dynamically
function GetControls(props) end       -- Controls: Button/Knob/Indicator/Text, Count, PinStyle
function GetControlLayout(props) end  -- layout + graphics tables (pixel positions)
function GetPages(props) end          -- tabbed UI
function GetComponents(props) end     -- optional embedded components
function GetPins(props) end           -- optional
function GetWiring(props) end

if Controls then                      -- RUNTIME
  -- sockets, timers, control handlers live here
end
```

Key design-time/runtime distinction: design-time code runs inside Designer's UI thread — no sockets, no timers there.

References: [Basic Plugin Framework](https://help.qsys.com/DeveloperHelp/Content/Code_Examples/Basic_Plugin_Framework.htm), [q-sys-community/q-sys-plugin-guide](https://github.com/q-sys-community/q-sys-plugin-guide), [gdyr/qsys-plugin-docs](https://github.com/gdyr/qsys-plugin-docs).

---

## 2. What already exists (don't rebuild this)

**Samsung Commercial Display (MDC Protocol)** — an official, QSC-moderated plugin in Asset Manager, plus the MIT-licensed community source at [q-sys-community/q-sys-plugin-samsung-display](https://github.com/q-sys-community/q-sys-plugin-samsung-display). Covers serial + TCP/1515 MDC for **commercial/signage panels** (QM/QB/QE/QH/VM series etc.).

**The gap**: *consumer* Samsung TVs (Tizen — Q/QN/S/CU/DU/The Frame, 2016+). These don't speak MDC and have no RS-232. They do, however, speak **Samsung IP Control** (JSON-RPC on 1516) — which is the same protocol family the Wall PRO and commercial panels expose, and which no existing Q-SYS plugin targets.

---

## 3. Samsung TV control surfaces

| Surface | Applies to | Transport | Gets you | Reliability |
|---|---|---|---|---|
| **IP Control (JSON-RPC)** | Consumer Tizen + Frame + Wall PRO | HTTPS **1516** (1515 on 2019-and-older) | Power on/off/reboot **from fully off**, art mode, mute, volume up/dn, full state readback, remote keys | **Primary** — verified on 2025 Frame |
| **Tizen WebSocket remote** | Consumer 2016+ | `wss://IP:8002/api/v2/channels/samsung.remote.control` | Key presses only — incl. `KEY_HDMI` cycling | Secondary; no reads, can't power off a Frame |
| **REST device info** | Consumer 2016+ | `http://IP:8001/api/v2/` | Model, name, `wifiMac`, `PowerState` — **discovery only** | Good for scanning, unreliable for state |
| **MDC** | Commercial signage | RS-232 9600-8N1 / TCP **1515** | Power, volume, mute, input, picture, video wall, virtual remote keys, model/serial polling | High — documented protocol |
| **SmartThings Cloud API** | Consumer, cloud-registered | HTTPS `api.smartthings.com/v1` + PAT/OAuth | Power, volume, mute, input, channel, app launch, state | Fallback only — now that RPC handles power-from-off, the cloud's main advantage is gone |
| **Wake-on-LAN** | Older consumer | UDP magic packet to TV MAC | Power on | **Not needed** where RPC 1516 is available; keep for pre-IP-Remote sets |
| **DIAL / UPnP** | Older + some current | HTTP :8001 / SSDP | App launch, some AV transport | Legacy |

### 3.1 IP Control — JSON-RPC 2.0 over HTTPS, port 1516 (primary)

`POST https://<ip>:1516/` with `Accept: application/json` and `Content-Type: application/json`. Self-signed cert — verification must be disabled. Method names are case-sensitive (`artModeControl`, not `artmodeControl`).

```json
// pair once — TV shows an approval prompt
{"jsonrpc":"2.0","id":1,"method":"createAccessToken"}
→ {"result":{"AccessToken":"hxd0…"}}

// every other call carries the token
{"jsonrpc":"2.0","id":1,"method":"powerControl",
 "params":{"AccessToken":"…","power":"powerOff"}}
```

| Method | Get (token only) | Set params |
|---|---|---|
| `powerControl` | `{"power":"powerOn"｜"powerOff"}` | `"powerOff"` · `"powerOn"` · `"reboot"` |
| `artModeControl` (Frame) | `{"artMode":"artModeOn"｜"artModeOff"}` | `{"artMode":"artModeOff"}` |
| `getTVStates` | `inputSource` (`HDMI2`, `TV`…), `volume`, `mute`, `pictureMode`, `soundMode`, `pictureSize`, `speakerSelect` | — |
| `muteControl` | `{"mute":…}` | `{"mute":"muteOn"｜"muteOff"}` |
| `volumeUpDnControl` | — | `{"control":"volumeUp"｜"volumeDn"}` |
| `remoteKeyControl` | — | `{"remoteKey":"power"｜"enter"｜"return"｜"exit"｜"cursorUp"…}` — **no HDMI/source keys** |
| `inputSourceControl`, `directVolumeControl` | **Not implemented on Frames** (`-32601`); present on Wall PRO / commercial panels | |

Errors: `-32601` method not found · `-32602` invalid params · `-32002` failed · `-32010` unauthorized (re-pair).
Protocol reference: [IP Control Protocol Reference](https://github.com/serjeleone/ha-samsungtv-smart/blob/main/IP_Control_Protocol_Reference.md) (empirically enumerated on 2024 + 2025 Frames, with Wall PRO cross-reference — directly relevant if the same plugin targets commercial panels).

**Prerequisites, all of which will bite you in the field:**
- **IP Remote must be enabled**: Settings → All Settings → Connection → Network → Expert Settings → *IP Remote*. This is what opens 1516.
- **Pair from the TV's own subnet.** Approval prompts (RPC *and* websocket) never render for requests originating on another subnet — the socket connects and then hangs silently with no prompt. This is the single biggest time sink.
- **Pair while the TV is on, not in Art Mode** — the prompt doesn't draw in Art Mode; the call just times out.
- **Tokens persist** across power cycles and reboots. Only a factory reset, disabling IP Remote, or removing the device from the TV's device list revokes them.
- **Reserve the TV's DHCP lease by MAC**, or resolve by MAC each run.
- On a site with many identical Samsungs, identify the target from the TV's own Network Status screen. Never probe candidates by sending keys.

### 3.2 WebSocket remote — key presses only (secondary)

```
wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64 name>&token=<token>

// first connect without token → on-screen approval; ms.channel.connect reply carries data.token
{"method":"ms.remote.control",
 "params":{"Cmd":"Click","DataOfCmd":"KEY_HDMI","Option":"false","TypeOfRemote":"SendRemoteKey"}}
```

Keys: `KEY_POWER`, `KEY_VOLUP/VOLDOWN/MUTE`, `KEY_HDMI`, `KEY_SOURCE`, `KEY_HOME`, `KEY_UP/DOWN/LEFT/RIGHT/ENTER/RETURN/EXIT`, `KEY_0`–`KEY_9`, `KEY_CHUP/CHDOWN`, `KEY_PLAY/PAUSE/STOP`, `KEY_MENU`, `KEY_TOOLS`, `KEY_INFO`.

Verified limits on current Frame firmware:
- Port 8001 (plain `ws://`) accepts the socket then closes it — **use 8002**.
- No state reads of any kind.
- `KEY_POWER` only toggles Art Mode ↔ on; press-and-hold is treated as a click. It cannot power the TV off.
- `KEY_HDMI1..4` are ignored. Input switching = press `KEY_HDMI` to cycle, then poll `getTVStates.inputSource` over RPC until it matches.
- The `com.samsung.art-app` channel is closed by the TV right after connect — use `artModeControl` over RPC instead.
- `/api/v2/` reports `PowerState: on` even in Art Mode, so it can't be trusted for power state. Use RPC `powerControl`.
- The TV batches multiple websocket frames per TCP read — a parser that assumes one frame per read will drop messages. (This surfaced in PowerShell; it applies equally to Q-SYS Lua if you ever hand-roll framing, though `WebSocket.New()` handles framing for you.)

### 3.3 App launch (websocket, non-Frame use cases)

```json
{"method":"ms.channel.emit","params":{"event":"ed.apps.launch","to":"host",
 "data":{"appId":"3201606009684","action_type":"DEEP_LINK"}}}
```
Netflix `11101200001`, YouTube `111299001912`, Disney+ `3201901017640`, browser via `org.tizen.browser` with a URL.

### 3.4 MDC framing — commercial panels (verify against the spec PDF)

```
Request : 0xAA | CMD | ID | LEN | DATA... | CHECKSUM
Response: 0xAA | 0xFF | ID | LEN | 'A'(0x41)|'N'(0x4E) | CMD | DATA... | CHECKSUM
CHECKSUM = (sum of all bytes after the 0xAA header) & 0xFF
```
Common commands: `0x00` status, `0x11` power, `0x12` volume, `0x13` mute, `0x14` input source, `0x18` MDC connect, `0x1D` model name/number, `0xB0` virtual remote key. ID `0xFE` = broadcast.
Spec: [MDC Protocol v13.7c PDF](https://aca.im/driver_docs/Samsung/MDC%20Protocol%202015%20v13.7c.pdf) · [v15.0](https://manuals.plus/m/377c6a902458fe2403a5ac274bbf1a33e4de4b72ea8fb3ef8a831b9439ff14d2). Implementations: [vgavro/samsung-mdc](https://github.com/vgavro/samsung-mdc) (84 commands), [psmsmets/samsung_mdc](https://github.com/psmsmets/samsung_mdc).

### 3.5 SmartThings (fallback)

`HttpClient` + PAT or OAuth bearer: `GET /v1/devices` → `POST /v1/devices/{id}/commands` (`switch:on/off`, `audioVolume:setVolume`, `audioMute:mute`, `mediaInputSource:setInputSource`, `tvChannel`, `custom.launchapp`) → `GET /v1/devices/{id}/status`. Works across subnets and from standby. Now that RPC 1516 covers power-from-off locally, reach for this only when the Core genuinely cannot sit on the TV's subnet, or on sets without IP Remote. Costs: internet dependency, seconds of latency, rate limits, token rotation.

### 3.6 Discovery

`GET http://<ip>:8001/api/v2/` returns `device.name`, `modelName`, `wifiMac`, `PowerState`. Scanning port 8001 across the subnet enumerates every Samsung on the network — useful for a plugin "Discover" button, with the caveat above about `PowerState` being unreliable.

---

## 4. Recommended architecture

**One plugin, selectable transport**, with RPC as the default for consumer sets. A `Device Type` property (`Consumer / Frame (IP Control)`, `Commercial (MDC/IP)`, `Commercial (MDC/Serial)`, `Cloud (SmartThings)`) driving `RectifyProperties()`. A single normalized control set on top, so a UCI built against it doesn't care which transport is live.

For consumer TVs the plugin runs **two transports at once**: RPC 1516 for everything stateful, websocket 8002 only for keys RPC doesn't expose (notably `KEY_HDMI`). Two independent tokens, two independent pairings.

```
 Controls (stable across transports)
 ├ Power On / Power Off / Power Toggle / PowerState (indicator)
 ├ Volume (knob 0-100) / VolumeUp / VolumeDown / Mute / MuteState
 ├ Input (combobox: HDMI1-4, TV, Apps…) / InputState
 ├ Nav pad: Up/Down/Left/Right/Enter/Back/Home/Menu/Exit/Info
 ├ Transport: Play/Pause/Stop/Rew/FF/Rec
 ├ Numeric 0-9, Channel Up/Down
 ├ AppLaunch (combobox + custom AppID string) / BrowserURL
 ├ Frame: ArtMode On/Off                       (consumer only)
 ├ Send Raw Key / Send Raw RPC — escape hatches
 └ Status: Online, ConnectionState, Model, Serial, FW, LastError
```

**Internals**
- Transport modules behind one interface: `open()/close()/send(cmd)/onData()`.
- Connection state machine: `Disconnected → Connecting → Pairing → Connected → Error`, with exponential-backoff reconnect (2s→30s cap) via `Timer`. `-32010` from RPC drives the state machine back to `Pairing`.
- **Input switching is a closed loop, not a command.** Press `KEY_HDMI` over websocket → read `getTVStates.inputSource` over RPC → repeat until it matches the requested input, with an attempt cap (~6) and a timeout so a missing source can't spin forever.
- Command queue with per-transport pacing (MDC: one outstanding frame, ~100–200 ms gap; WS: ~50–100 ms between keycodes; RPC: serialize, one request in flight).
- Poll timer (5–15 s): `getTVStates` gives power, input, volume, mute in one call — far better feedback than the websocket-only design originally assumed. MDC `0x00` is the equivalent single-shot status read.
- **Token persistence**: store both the RPC `AccessToken` and the websocket token in read-only `Text` controls, which are saved with the design and survive Core restarts. Never force re-pairing on reboot — pairing requires someone standing at the TV.
- WoL (`UdpSocket` broadcast of `FF×6 + MAC×16` to `255.255.255.255:9`) stays in as a "Power On Method" option for pre-IP-Remote sets, but is not the default.
- Never scope the `WebSocket`/`TcpSocket` object locally (GC will eat it).
- One plugin instance per TV; MDC Display ID property for daisy-chained signage.

### 4.1 Frame-specific behavior to encode

- After `powerOn`, a Frame comes up on input **TV** (Samsung TV Plus), not the last HDMI — the plugin must always steer input afterwards rather than assuming restoration.
- Art Mode is not "off": the panel only darkens when the motion sensor sees nobody. For genuinely dark overnight, send `powerOff`.
- Leaving Art Mode via `KEY_POWER` lands on the last non-HDMI source if that was used most recently.

### 4.2 "Full control" — honest capability matrix

Achievable: power on from fully off, power off, reboot, art mode, volume up/down, mute, input selection (via the cycle-and-verify loop), full remote navigation, app launch, browser URL, channel, transport keys, and readback of power/input/volume/mute/picture mode/sound mode/picture size.

Not achievable on consumer/Frame sets: absolute volume set (`directVolumeControl` → `-32601`), direct input selection (`inputSourceControl` → `-32601`), arbitrary picture geometry (MDC-only), any guarantee across firmware updates. Both missing methods exist on Wall PRO / commercial panels, so the same plugin should use them when the device type says commercial.

---

## 5. Build plan

1. **Port the proven reference implementation first.** A working PowerShell RPC client, websocket key sender, and state-checked morning/evening routine already exist and run on a schedule. That is the reference behavior — translate it to Lua rather than re-deriving it.
2. ~~**Prove the one Q-SYS-specific unknown.**~~ **Resolved 2026-09-16** — see §7.9. Q-SYS `HttpClient` and `WebSocket` both accept the TV's self-signed cert with no configuration; `createAccessToken` and authenticated `getTVStates` / `powerControl` / `artModeControl` round-trips all succeed from a Control Script.
3. Scaffold from Basic Plugin Framework; use the community Samsung MDC plugin (MIT) as a structural reference.
4. Build order: RPC transport → websocket keys → input cycle-and-verify loop → MDC → SmartThings/WoL.
5. UI: control layout + graphics, a ready-made example UCI, and a Debug Print property (`None/Tx/Rx/Tx&Rx/Function Calls`) — house style for Q-SYS plugins.
6. Test matrix: the 2025 Frame (known-good baseline), a 2024 Frame, a non-Frame 2022+ consumer set, a pre-2019 set (port 1515), and one commercial panel; wired and Wi-Fi; same-VLAN and cross-VLAN (to document the failure mode); Core reboot; TV power-cycle; firmware update.
7. Package: `.qplug` + nuspec + README/description; stable `Id` GUID. Optional: Technology Partner / Developer Partner track for Asset Manager listing.

**Effort estimate**: RPC + websocket consumer support ≈ 1–2 weeks (down from the earlier 2–3, since the protocol work is already done and field-verified). MDC ≈ 3–5 days. SmartThings ≈ 3–5 days.

**Top risks**
1. ~~Q-SYS `HttpClient` / `WebSocket` TLS behavior against a self-signed cert~~ — **resolved, works** (§7.9).
2. **Cross-subnet pairing is impossible.** The Core must be on the TV's subnet at least for pairing. This is a network design requirement to raise with the customer at scoping time, not a code problem.
3. Pairing requires physical presence at each TV, once per device. Plan commissioning around it.
4. Unofficial, empirically enumerated protocol — no stability guarantee across firmware.
5. Frames need input steering after every power-on; a naive "power on and done" macro will land users on Samsung TV Plus.

---

## 6. Market fit and need

### 6.1 Prior art — the gap is real

No Q-SYS plugin for consumer Samsung TVs exists publicly. Searches of the Q-SYS asset library, the `q-sys-community` GitHub org, and QSC's third-party plugin partner page return only MDC/commercial work; QSC's own FAQ ("Where can I find a plugin for Samsung displays?") answers with the MDC plugin alone. Caveat: Asset Manager's full catalog renders only inside Q-SYS Designer and developers.qsc.com sits behind a login, so this is absence of evidence from the public web. **Confirm by opening Asset Manager → search "Samsung"** before committing effort.

The gap has a structural cause rather than a technical one. Q-SYS plugins are overwhelmingly vendor-funded — ViewSonic shipped one in July 2025 to sell displays. Samsung has an active disincentive: a plugin that makes consumer TVs behave like commercial ones in a Q-SYS install cannibalizes their commercial display line. The party normally motivated to write this will not write it.

### 6.2 Internal need (the originating deployment)

A multi-room building with 20+ retail-purchased consumer Samsungs, running on a fixed weekly schedule, with Q-SYS being installed regardless. Concrete jobs, ranked:

1. **Scheduled power off.** Consumer panels are rated for far less than the 12+ hour duty cycles commercial rooms impose; leaving them on is the primary cause of early failure. A nightly off is the single highest-value function.
2. **Power on with input steering.** Sets come up on Samsung TV Plus, not the last HDMI. Across 20 rooms that is a volunteer walking the building with a remote every Sunday.
3. **All-call / emergency takeover.** Every screen to a common source from one button.
4. **Per-TV status.** See which screen stopped answering before a room leader reports it.
5. **Eliminating remotes.** In kids ministry, remotes disappear. A UCI on a wall panel removes them from the equation.

This justifies the build on its own. Do not let the external-market question gate it.

### 6.3 External market — narrow, and structurally so

The addressable set isn't "Q-SYS sites with Samsung TVs," it's "Q-SYS sites that put *consumer* Samsungs on the wall anyway." The AV trade press uniformly advises commercial panels (300–500 nits vs 200–250, business warranties, duty-cycle ratings), and professional integrators largely comply. Meanwhile Q-SYS is a mid-to-high-end platform — organizations that can fund a Core can often fund commercial displays.

The overlap is budget-asymmetric installs: a serious AV backbone paired with whatever screens fit the remaining budget. Churches are the textbook case; schools, small nonprofits, and some hospitality sit alongside. Real segment, small segment. The deployment that prompted this plugin is itself evidence it exists.

**Monetization, ranked by realism:** open-source for standing in the Q-SYS developer community (Asset Manager listing plus a verified badge is genuine reputational currency) · sponsored development on the Locimation model (third party funds the work for a discount) · bundled into integration services. Selling it as a product to a few hundred sites is not a credible plan.

**Recommendation:** build it because the originating site needs it, open-source it, treat outside adoption as upside. The expensive part — protocol reverse-engineering — is already done and field-verified. Covering the commercial MDC tier in the same plugin widens the audience at little extra cost.

### 6.4 Organizational risk

If an integrator designs and supports the kids-building Q-SYS system, a volunteer-authored plugin dropped into their design file creates a support seam: whose problem is it when a TV doesn't wake on a Sunday? Establish early whether display control is already specced (they may be planning CEC, or nothing), and build this *with* them rather than adjacent to them.

---

## 7. Full feature specification

Goal: expose everything each device is capable of, across every Samsung model the team might buy, with the plugin adapting to what's actually present rather than assuming a uniform fleet.

**Availability legend** — which device classes support a feature:

| Code | Class | Transport |
|---|---|---|
| **A** | Consumer Tizen 2020+ with IP Remote | JSON-RPC 1516 + WS 8002 |
| **B** | Consumer Tizen 2016–2019 | JSON-RPC 1515 (where present) + WS 8002 |
| **C** | The Frame (superset of A) | as A, plus art mode |
| **D** | Commercial / signage panel | MDC over TCP 1515 or RS-232 |
| **E** | Any cloud-registered set | SmartThings HTTPS |

**Verification legend:** ✔ verified on hardware (2025 Frame, 2026-09-16) · ▢ documented but untested here · ✘ confirmed unavailable.

### 7.1 Capability probing (the mechanism that makes "all models" work)

A retail-purchased fleet means several model years and firmware levels in one building. The plugin must never assume. At connect:

1. Try RPC on 1516; on failure try 1515; on failure fall back to WS-only, then SmartThings if credentials exist.
2. Call each optional RPC method once with a benign payload. Cache which return `-32601` (method not found).
3. Read `getTVStates` and record which keys the device actually returns.
4. Probe for art mode (`artModeControl`) to detect a Frame rather than trusting the model string.
5. Publish the result to a `Capabilities` text control, and **grey out / disable controls the device doesn't support** rather than letting them fail silently.
6. Re-probe on firmware-change detection (version string differs from cached).

This is a v1 requirement, not a later refinement — retrofitting it is materially harder than building it in.

### 7.2 Properties (design-time)

| Property | Type | Values / default | Notes |
|---|---|---|---|
| Device Class | enum | Auto · Consumer (IP Control) · Frame · Commercial (MDC/IP) · Commercial (MDC/Serial) · Cloud (SmartThings) | Auto runs the probe in 7.1 |
| IP Address | string | — | A/B/C/D |
| RPC Port | integer | 1516 (1515 legacy) | auto-detected when Device Class = Auto |
| WebSocket Port | integer | 8002 | 8001 closes on current firmware ✔ |
| MDC Display ID | integer | 0–254, `0xFE` broadcast | D only; daisy-chained panels |
| Serial Port / Baud | enum | 9600 8N1 | D serial only |
| SmartThings Token | string | — | E only |
| Poll Interval | integer | 5–60 s, default 10 | 0 disables polling |
| Power-On Method | enum | RPC · WoL · SmartThings · MDC · None | RPC default where available |
| MAC Address | string | — | WoL fallback + DHCP identification |
| Input After Power-On | enum | None · HDMI1–4 · TV · Last | drives the steer loop (7.6) |
| Input Cycle Attempt Cap | integer | default 6 | bounds the cycle-and-verify loop |
| Is Managed | boolean | Yes | adds to Core Inventory → Event Log alerts |
| Debug Print | enum | None · Tx · Rx · Tx&Rx · Function Calls | house convention |
| Friendly Name | string | "Q-SYS" | base64'd into the WS handshake |

### 7.3 Controls — complete inventory

**Power and state**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Power On | trigger | A✔ B▢ C✔ D▢ E▢ | RPC `powerControl:powerOn` works from fully off ✔ |
| Power Off | trigger | A✔ C✔ D▢ E▢ | RPC only — WS `KEY_POWER` cannot power off a Frame ✘ |
| Power Toggle | trigger | all | wraps the above with state read |
| Power State | indicator + text | A✔ C✔ D▢ E▢ | from RPC `powerControl` get; **not** from `/api/v2/ PowerState` ✘ (reports `on` in Art Mode) |
| Reboot | trigger | A▢ C▢ D▢ | RPC `powerControl:reboot` |
| Panel On/Off (backlight) | toggle | D▢ | MDC-only; distinct from power |

**Audio**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Volume Up / Down | trigger | A✔ C✔ D▢ | RPC `volumeUpDnControl` |
| Volume (absolute) | knob 0–100 | D▢ E▢ | MDC `0x12` / SmartThings; `directVolumeControl` ✘ on Frames (`-32601`) |
| Volume State | knob feedback | A✔ C✔ D▢ | `getTVStates.volume` — readable even where not settable |
| Mute On / Off / Toggle | trigger/toggle | A✔ C✔ D▢ E▢ | RPC `muteControl` |
| Mute State | indicator | A✔ C✔ D▢ | `getTVStates.mute` |
| Speaker Select | combobox | A▢ C▢ | `getTVStates.speakerSelect` — TV vs external |
| Sound Mode | combobox | A▢ C▢ D▢ | `getTVStates.soundMode` |

**Input / source**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Input Select | combobox (HDMI1–4, TV, Apps) | A✔ C✔ D▢ E▢ | consumer: cycle-and-verify loop (7.6); commercial: MDC `0x14` direct |
| Input Discrete buttons | trigger ×N | as above | same loop underneath |
| Input State | text + indicator | A✔ C✔ D▢ | `getTVStates.inputSource` |
| HDMI Cycle | trigger | A✔ C✔ | raw `KEY_HDMI`; `KEY_HDMI1..4` ignored ✘ |

**Navigation and keys**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Up/Down/Left/Right/Enter | trigger | A✔ B▢ C✔ D▢ | RPC `remoteKeyControl` (`cursorUp`…) or WS keycodes |
| Return / Exit / Home / Menu / Tools / Info | trigger | A✔ C✔ D▢ | as above |
| Numeric 0–9 | trigger ×10 | A▢ C▢ D▢ | WS keycodes; MDC `0xB0` on commercial |
| Channel Up / Down | trigger | A▢ C▢ D▢ | |
| Transport (Play/Pause/Stop/Rew/FF/Rec) | trigger ×6 | A▢ C▢ D▢ | |
| Send Raw Key | string + trigger | A✔ C✔ | escape hatch for undocumented keycodes |

**Apps and content**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| App Launch | combobox + custom App ID | A▢ B▢ C▢ E▢ | WS `ed.apps.launch`; Netflix `11101200001`, YouTube `111299001912`, Disney+ `3201901017640` |
| Browser URL | string + trigger | A▢ C▢ | `org.tizen.browser` |
| Launcher URL / Content Download | string | D▢ | MDC signage-only |

**Picture / display**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Picture Mode | combobox | A✔(read) C✔(read) D▢(set) | `getTVStates.pictureMode`; MDC settable |
| Picture Size / Aspect | combobox | A✔(read) D▢(set) | `getTVStates.pictureSize` |
| Brightness · Contrast · Sharpness · Color · Tint | knob ×5 | D▢ | MDC-only ✘ on consumer |
| Video Wall mode / config | combobox | D▢ | MDC-only |
| Safety Lock / OSD | toggle | D▢ | MDC-only |

**The Frame**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Art Mode On / Off | toggle | C✔ | RPC `artModeControl`; the WS `com.samsung.art-app` channel is closed by the TV ✘ |
| Art Mode State | indicator | C✔ | |
| *(Art selection / upload)* | — | ✘ | art-app channel unavailable on tested firmware |

**Device info**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Model Name / Number | text | A✔ B✔ C✔ D▢ | `GET :8001/api/v2/` or MDC `0x1D` |
| Serial Number | text | D▢ | MDC; not exposed by consumer RPC |
| Firmware Version | text | A▢ C▢ D▢ | drives re-probe on change |
| MAC (wifiMac) | text | A✔ C✔ | from `/api/v2/` |
| Panel On Time (hours) | text | D▢ | MDC — useful lifespan telemetry, commercial only |
| Temperature / Error Status | text | D▢ | MDC-only |

**Diagnostics, pairing, fleet**

| Control | Type | Avail. | Notes |
|---|---|---|---|
| Status | indicator + text | all | Q-SYS status model — see 7.5 |
| Online | indicator | all | |
| Connection State | text | all | Disconnected/Connecting/Pairing/Connected/Error |
| Pair (RPC) | trigger | A✔ C✔ | fires `createAccessToken`, TV draws approval prompt |
| Pair (WebSocket) | trigger | A✔ C✔ | separate token, separate prompt |
| RPC Token / WS Token | text (read-only) | A✔ C✔ | persisted in the design — see 7.6 |
| Clear Tokens | trigger | A✔ C✔ | forces re-pair |
| Capabilities | text (read-only) | all | probe result, per 7.1 |
| Last Error | text | all | includes RPC code (`-32010` → re-pair) |
| Send Raw RPC | string + trigger | A✔ C✔ | escape hatch for new methods |

### 7.4 Control pins

Expose at minimum as schematic pins so logic and scheduling need no scripting: **Power On**, **Power Off**, **Power State**, **Input Select**, **Input State**, **Mute**, **Online/Status**. This is what lets a Q-SYS Scheduler component drive the nightly-off as a literal wire on the canvas.

### 7.5 Status model

With **Is Managed = Yes**, the plugin joins the Core Inventory and its Status is monitored, with transitions raising Event Log alerts. Map deliberately:

| State | Condition |
|---|---|
| Initializing | probing capabilities / connecting |
| OK | connected, authorized, polling successfully |
| Compromised | connected but degraded — RPC unavailable and running WS-only, or a poll timing out intermittently |
| Fault | unreachable, or `-32010` unauthorized (needs re-pair) |
| Missing | configured but never seen since Core start |
| Not Present | disabled in properties |

Across 20+ TVs this is the difference between noticing a dark room on Sunday morning and being told about it Sunday afternoon.

### 7.6 Required behaviors

- **Connection state machine:** `Disconnected → Connecting → Pairing → Connected → Error`, exponential backoff 2 s → 30 s cap. `-32010` routes back to `Pairing`.
- **Dual transport (consumer):** RPC 1516 and WS 8002 held open simultaneously, two independent tokens, two independent pairings, independent health.
- **Token persistence:** both tokens in read-only Text controls saved with the design. Tokens survive TV power cycles and reboots; only factory reset, disabling IP Remote, or device-list removal revokes them. Never force a re-pair on Core reboot — pairing requires a human at the TV.
- **Power-on sequence:** `powerOn` → wait for `powerControl` to report on → if Frame and Art Mode on, `artModeControl:artModeOff` → steer input per the Input-After-Power-On property. A Frame that is merely "on" may still be showing art.
- **Input cycle-and-verify:** press `KEY_HDMI` → read `getTVStates.inputSource` → repeat until match, bounded by the attempt cap and a timeout, then raise Last Error. Presented upstream as an ordinary combobox.
- **Pacing:** RPC serialized, one request in flight · WS ~50–100 ms between keycodes · MDC one outstanding frame, ~100–200 ms gap.
- **Polling:** one `getTVStates` per interval yields power, input, volume, mute, picture and sound mode together. MDC `0x00` is the equivalent single-shot read.
- **TLS:** both RPC and WS use self-signed certificates; verification must be skippable. **This is the open risk — see §5.**
- **Socket lifetime:** never scope `WebSocket`/`TcpSocket` objects locally (GC will collect them mid-use).

### 7.7 Confirmed limits — document these, don't let integrators discover them

| Want | Reality |
|---|---|
| Absolute volume set on consumer | ✘ `directVolumeControl` → `-32601` on Frames. Up/down only. Volume *reads* fine. |
| Direct input select on consumer | ✘ `inputSourceControl` → `-32601`. Cycle-and-verify is the only route. |
| Power off via websocket | ✘ `KEY_POWER` toggles Art Mode ↔ on; press-and-hold is treated as a click. |
| Any state read via websocket | ✘ None. RPC or nothing. |
| `/api/v2/ PowerState` as truth | ✘ Reports `on` while in Art Mode. Discovery only. |
| Art selection / upload on Frame | ✘ `com.samsung.art-app` channel closed by the TV on tested firmware. |
| Picture geometry on consumer | ✘ MDC-only (commercial panels). |
| Cross-subnet pairing | ✘ Approval prompts never render for off-subnet requests — the socket connects and hangs silently. Network design requirement. |
| Pairing while in Art Mode | ✘ Prompt doesn't draw; the call times out. |

`inputSourceControl` and `directVolumeControl` *do* exist on Wall PRO and commercial panels sharing the protocol — so the same plugin should use them when the probe finds them.

### 7.8 Build order

The spec above is the destination. Ship it in slices so a working building beats a complete matrix:

- **v1 — the building works.** RPC transport, pairing + token persistence, power on/off with state, input steer loop, Status + Is Managed, poll. Covers all five ranked needs in §6.2.
- **v2 — parity with convention.** WS keys, full nav pad, volume/mute, device info, control pins, UCI example, debug levels, capability probe surfaced.
- **v3 — breadth across models.** MDC/commercial tier, Frame art mode, app launch, picture controls, SmartThings fallback, WoL for legacy sets.

---

### 7.9 Q-SYS transport verification (Phase 0, 2026-09-16)

Run from a Control Script in **Designer 10.4.1 emulation** on a PC that was *not* on the TV's subnet (routed, two hops), against a 2025 50" Frame. The probe script is `tools/p0_transport_probe.lua`; results were read back over QRC (`Control_Script` with *Script Access = All* exposes `code`, `reload` and `log.history`, so a script can be pushed, run, and its output collected without touching the Designer GUI).

| Question | Result |
|---|---|
| `HttpClient.Upload` POST to `https://<tv>:1516/` against the self-signed cert | ✔ Works with no cert options at all. There is no verify/insecure flag in the API and none is needed. |
| `WebSocket:Connect("wss", …, 8002)` against the self-signed cert | ✔ TLS handshake completes; `Connected` fires and frames arrive. |
| `createAccessToken` from off-subnet | ✔ **Token issued immediately** (HTTP 200, `result.AccessToken`), and the TV drew its approval prompt shortly *after* — authenticated reads already succeeded before anyone pressed Allow. This contradicts the earlier PowerShell finding that off-subnet RPC pairing hangs silently; treat that as firmware/state dependent, not a rule. |
| Websocket pairing from off-subnet | ✘ Socket opens, TV immediately sends `{"event":"ms.channel.timeOut"}` and closes. The cross-subnet rule holds for 8002. |
| Token validity | ✔ `getTVStates`, `powerControl` (get) and `artModeControl` (get) all return real state with the new token. |
| Bogus token | Returns `{"code":-32700,"message":"Parse error"}` — a **flat** object, not JSON-RPC-wrapped, and not the `-32010` the reference doc lists. The error mapper must route both to *re-pair*. |
| Response `id` | Comes back as the string `"1"` even when sent as the number `1`. Compare loosely. |
| `/api/v2/` `firmwareVersion` | `Unknown` on this set — don't rely on it for the capability probe. |

Consequences for the design: the RPC transport can be built exactly as specified in §4 with plain `HttpClient` calls. The websocket transport keeps its "pair from the TV subnet" prerequisite. Both transports should be treated as verified on the Windows emulator runtime and re-confirmed once on a physical Core before commissioning.

## Sources

- [Q-SYS Basic Plugin Framework](https://help.qsys.com/DeveloperHelp/Content/Code_Examples/Basic_Plugin_Framework.htm)
- [Q-SYS Plugins (Schematic Library)](https://help.qsys.com/q-sys_9.4/Content/Schematic_Library/plugins.htm)
- [Q-SYS Extensions to Lua](https://help.qsys.com/Content/Control_Scripting/Using_Lua_in_Q-Sys/Q-SYS_Extensions_to_Lua.htm)
- [Q-SYS WebSocket API](https://help.qsys.com/Content/Control_Scripting/Using_Lua_in_Q-Sys/lua_web_socket.htm)
- [Q-SYS HttpClient](https://help.qsys.com/q-sys_9.8/Content/Control_Scripting/Using_Lua_in_Q-Sys/HttpClient.htm)
- [Q-SYS TCPSocket example](https://q-syshelp.qsc.com/DeveloperHelp/Content/Code_Examples/TCPSocket_Example.htm)
- [q-sys-community/q-sys-plugin-guide](https://github.com/q-sys-community/q-sys-plugin-guide)
- [q-sys-community/q-sys-plugin-samsung-display](https://github.com/q-sys-community/q-sys-plugin-samsung-display)
- [Locimation Q-SYS Lua Design Patterns](https://locimation.github.io/qsys-patterns/)
- [Q-SYS Technology Partner Program](https://www.qsys.com/resources/news/detail/q-sys-launches-technology-partner-program/)
- Field testing on a 2025 The Frame, 2026-09-16 (see `docs/site-local/` for the deployment-specific record)
- [Samsung IP Control Protocol Reference](https://github.com/serjeleone/ha-samsungtv-smart/blob/main/IP_Control_Protocol_Reference.md)
- [Samsung MDC Protocol v13.7c (PDF)](https://aca.im/driver_docs/Samsung/MDC%20Protocol%202015%20v13.7c.pdf)
- [vgavro/samsung-mdc](https://github.com/vgavro/samsung-mdc) · [psmsmets/samsung_mdc](https://github.com/psmsmets/samsung_mdc)
- [xchwarze/samsung-tv-ws-api](https://github.com/xchwarze/samsung-tv-ws-api) · [Home Assistant Samsung TV integration](https://www.home-assistant.io/integrations/samsungtv/)
