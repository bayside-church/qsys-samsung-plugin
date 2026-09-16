# CLAUDE.md

Project context for Claude Code sessions in this repository.

## What this is

A Q-SYS Designer plugin (`.qplug`) for controlling Samsung televisions — primarily
**consumer Tizen sets**, which the existing official MDC plugin cannot reach.

Read [`docs/samsung-tv-qsys-plugin-research.md`](docs/samsung-tv-qsys-plugin-research.md)
before doing protocol or architecture work. It contains the verified protocol
behavior, the full feature specification (§7), and the confirmed limits (§7.7).
Do not re-derive any of it from the web — much of what is published about Samsung
TV control is wrong or outdated, and §7.7 records what was actually tested.

## 🔴 This repository is PUBLIC

**Never commit deployment-specific information.** That includes:

- IP addresses on the site's network (`10.82.x.x`)
- MAC addresses
- Internal hostnames, or local tooling paths from the deployment site
- The organization's name in operational context
- Links to private artifacts or internal documents

Site-specific material belongs in **`docs/site-local/`**, which is gitignored.
A pre-commit hook in `.githooks/pre-commit` scans staged content for these
patterns and blocks the commit. Enable it with:

```
git config core.hooksPath .githooks
```

When writing public docs, genericize rather than omit: "a multi-room building
with 20+ retail-purchased consumer Samsungs" carries the useful information
without identifying anyone. The `LICENSE` file is the one place the copyright
holder's name legitimately appears.

## Architecture

Plugins ship as one `.qplug` file but are developed as separate modules, combined
by QSC's Plugin Compiler (`plugincompile/PLUGCC.exe`, driven by a VS Code task).
Directives: `--[[ #include "file.lua" ]]` and `--[[ #encode "image.svg" ]]`.

Two halves in every plugin:

- **Design-time** — `GetProperties`, `GetControls`, `GetControlLayout`, `GetPages`,
  `RectifyProperties` etc. Runs inside Designer's UI thread. No sockets, no timers.
- **Runtime** — everything inside `if Controls then`. Sockets, timers, handlers.

Transports, behind one normalized control surface:

| Transport | Port | Role |
|---|---|---|
| Samsung IP Control (JSON-RPC) | 1516 (1515 legacy) | **Primary.** Power, art mode, all state reads. |
| Tizen websocket remote | 8002 | Key presses only. No reads. Cannot power off. |
| MDC | 1515 / RS-232 | Commercial panels. |
| SmartThings | HTTPS | Cloud fallback. |

Consumer sets run RPC and websocket **simultaneously** — two tokens, two pairings.

## Conventions

- Lua, 2-space indent (see `.vscode/settings.json`).
- Never scope `WebSocket`/`TcpSocket` objects locally — Lua's GC will collect them
  mid-use. Q-SYS documents this explicitly.
- Capability-probe at connect; never assume a uniform fleet or trust a model string.
- `PluginInfo.Id` is a stable GUID. **Never change it** once published — it is how
  Designer identifies the plugin across versions.
- Reference implementations worth reading: 28 QSC-signed plugins ship in
  `C:\Program Files\QSC\Q-SYS Designer 10.4\extensions\` (~47k lines of production
  Lua). They are the best available guide to house conventions for layout tables,
  property panes, and runtime structure.

## Tooling

- Q-SYS Designer 10.4.1 — `C:\Program Files\QSC\Q-SYS Designer 10.4\`
- Bundled Lua libs at `<install>/lua/` — includes `unittest.lua`, usable for
  protocol logic tests that need no TV.
- Claude has **no GUI access**. Anything requiring Designer's interface —
  Asset Manager, the schematic canvas, emulation, pushing to a Core — is the
  user's to run. Claude handles files, code, and builds.
- QRC (JSON-RPC over TCP 1710) can drive a running Core headlessly, which is the
  one path to verifying live behavior without the GUI.
