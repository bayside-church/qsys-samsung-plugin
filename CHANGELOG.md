# Changelog

All notable changes to this plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project uses Q-SYS four-part plugin versioning (`x.x.x.x`).

## [Unreleased]

### Added
- Websocket-only tier verified on hardware (2018 NU6900): off via `KEY_POWER`;
  on via `KEY_POWER` while the set's radio is up, else Wake-on-LAN — three
  rounds of unicast + broadcast, one socket per interface.
- Power On before classification fires every applicable wake method.
- Writing a token control from outside takes effect immediately.

### Fixed
- Websocket stopped reconnecting after the TV entered standby.
- Wake-on-LAN magic packet header was not `FF×6` (source-file encoding slip).
- Pair (RPC) on a websocket-only set no longer leaves a misleading error.
- :8001 lookup retried around power transitions; classification is sticky.

## [0.1.0.0] — 2026-09-17 — first usable release

### Added
- IP Control (JSON-RPC over HTTPS 1516) transport with serialized queue and
  response classification; Q-SYS `HttpClient` accepts the TV's self-signed cert.
- Tizen websocket (8002) key transport with token capture, pacing, reconnect.
- Connection state machine (Disconnected → Connecting → Pairing → Connected)
  with exponential backoff; unauthorized tokens park in Pairing and never
  auto-re-pair (one RPC token per TV — a new pairing revokes the previous one).
- Power on/off/toggle with true state; power-on sequence: on → art mode off
  (Frame) → land on *Input After Power-On*.
- Direct input select via `inputSourceControl`, verified against `getTVStates`,
  with websocket cycle-and-verify as fallback; input re-issued after every
  art-mode exit (the TV misreports state there).
- Absolute volume, volume up/down, mute, art mode, all with readback.
- Power-state-aware capability probe (Frames report `-32601` for the optional
  methods while in standby); re-probe on first off→on.
- Websocket-only tier for 2016–2019 sets without IP Control: `KEY_POWER`,
  Wake-on-LAN, blind `KEY_HDMI`, key-based volume; explicit Status message.
- Q-SYS Status / inventory integration (`IsManaged`); *Power Off Reports As*
  property (default Compromised) so a TV in standby shows orange.
- Two-page control layout; 12 schematic pins; raw RPC / raw key escape hatches.
- Tooling: `tools/build.sh`, QRC helpers, in-emulator harness and RPC unit tests.

### Verified on
- QN50LS03FA (2025 Frame), UN65M70HD (2026 M70H, cross-subnet), UN55NU6900
  (2018, websocket-only tier up to pairing).

### Known gaps
- Not yet run on a physical Core; no multi-day unattended run; MDC / SmartThings
  tiers not implemented.
- Websocket tier verified only to the TLS handshake — pairing needs a client on
  the TV's subnet, which no test has had yet.


### Added
- Protocol research and full feature specification (`docs/samsung-tv-qsys-plugin-research.md`)
- Market-fit analysis and build phasing
- VS Code workspace configuration for Q-SYS Lua development
