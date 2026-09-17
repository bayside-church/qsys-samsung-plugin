-- Design-time properties. Names are user-facing and are also the keys used at
-- runtime via Properties["..."].Value, so keep the two halves in sync.

table.insert(props, {
  Name = "IP Address",
  Type = "string",
  Value = "",
})
table.insert(props, {
  Name = "RPC Port",
  Type = "integer",
  Min = 1,
  Max = 65535,
  Value = 1516, -- 1515 on pre-2020 sets that still expose IP Control
})
table.insert(props, {
  Name = "WebSocket Port",
  Type = "integer",
  Min = 1,
  Max = 65535,
  Value = 8002, -- 8001 (plain ws) is closed by the TV on current firmware
})
table.insert(props, {
  Name = "Friendly Name",
  Type = "string",
  Value = "Q-SYS", -- what the TV shows in its device list; base64'd into the websocket handshake
})
table.insert(props, {
  Name = "Poll Interval",
  Type = "integer",
  Min = 0,
  Max = 60,
  Value = 10, -- seconds; 0 disables polling
})
table.insert(props, {
  Name = "Power-On Method",
  Type = "enum",
  Choices = { "RPC", "WoL", "None" },
  Value = "RPC", -- WoL is used automatically on sets without IP Control
})
table.insert(props, {
  Name = "MAC Address",
  Type = "string",
  Value = "", -- optional; learned from :8001/api/v2/ when blank. Needed for WoL while the TV is off.
})
table.insert(props, {
  Name = "Input After Power-On",
  Type = "enum",
  Choices = { "None", "HDMI1", "HDMI2", "HDMI3", "HDMI4", "TV" },
  Value = "None",
})
table.insert(props, {
  Name = "Input Cycle Attempt Cap",
  Type = "integer",
  Min = 1,
  Max = 12,
  Value = 6, -- bounds the KEY_HDMI cycle-and-verify loop
})
table.insert(props, {
  Name = "Power Off Reports As",
  Type = "enum",
  Choices = { "OK", "Compromised" },
  Value = "Compromised", -- a TV in standby shows orange in Core Manager / inventory; "OK" for sets that are meant to be off
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Tx", "Rx", "Tx/Rx", "Function Calls", "All" },
  Value = "None",
})
