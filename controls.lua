-- Control inventory. Feedback fields are Indicator/Text (read-only at the
-- control level); the two token fields stay Text so their values persist with
-- the design, and are made read-only in the layout instead.
-- Names are the keys used at runtime via Controls.<Name> and
-- the pin names on the schematic. See research doc §7.3 for the full spec;
-- this is the Phase 1 (v0.1) subset plus the pieces the websocket needs.

local function add(t) table.insert(ctrls, t) end

-- Power and state ------------------------------------------------------------
add({ Name = "PowerOn",        ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input",  Count = 1 })
add({ Name = "PowerOff",       ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input",  Count = 1 })
add({ Name = "PowerToggle",    ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input",  Count = 1 })
add({ Name = "PowerState",     ControlType = "Indicator", IndicatorType = "Led", UserPin = true, PinStyle = "Output", Count = 1 })
add({ Name = "PowerStateText", ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })

-- Input ----------------------------------------------------------------------
add({ Name = "InputSelect",    ControlType = "Text", UserPin = true, PinStyle = "Both",   Count = 1 }) -- combobox; choices set at runtime
add({ Name = "InputState",     ControlType = "Indicator", IndicatorType = "Text", UserPin = true, PinStyle = "Output", Count = 1 })
add({ Name = "HDMICycle",      ControlType = "Button", ButtonType = "Trigger", UserPin = false, Count = 1 })

-- Audio ----------------------------------------------------------------------
add({ Name = "VolumeUp",       ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input", Count = 1 })
add({ Name = "VolumeDown",     ControlType = "Button", ButtonType = "Trigger", UserPin = true, PinStyle = "Input", Count = 1 })
add({ Name = "Volume",         ControlType = "Knob", ControlUnit = "Integer", Min = 0, Max = 100, UserPin = true, PinStyle = "Both",   Count = 1 }) -- settable where directVolumeControl exists; always shows feedback
add({ Name = "Mute",           ControlType = "Button", ButtonType = "Toggle", UserPin = true, PinStyle = "Both", Count = 1 })

-- The Frame ------------------------------------------------------------------
add({ Name = "ArtMode",        ControlType = "Button", ButtonType = "Toggle", UserPin = false, Count = 1 })

-- Pairing and tokens ---------------------------------------------------------
add({ Name = "PairRPC",        ControlType = "Button", ButtonType = "Momentary", UserPin = false, Count = 1 })
add({ Name = "PairWS",         ControlType = "Button", ButtonType = "Momentary", UserPin = false, Count = 1 })
add({ Name = "ClearTokens",    ControlType = "Button", ButtonType = "Momentary", UserPin = false, Count = 1 })
add({ Name = "RPCToken",       ControlType = "Text", UserPin = false, Count = 1 }) -- persisted with the design
add({ Name = "WSToken",        ControlType = "Text", UserPin = false, Count = 1 }) -- persisted with the design

-- Device info ----------------------------------------------------------------
add({ Name = "Model",          ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })
add({ Name = "MAC",            ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })
add({ Name = "Capabilities",   ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })

-- Diagnostics ----------------------------------------------------------------
add({ Name = "Status",         ControlType = "Indicator", IndicatorType = "Status", UserPin = true, PinStyle = "Output", Count = 1 })
add({ Name = "Online",         ControlType = "Indicator", IndicatorType = "Led", UserPin = true, PinStyle = "Output", Count = 1 })
add({ Name = "ConnectionState",ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })
add({ Name = "LastError",      ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })

-- Escape hatches -------------------------------------------------------------
add({ Name = "RawKey",         ControlType = "Text", UserPin = false, Count = 1 })
add({ Name = "RawKeySend",     ControlType = "Button", ButtonType = "Momentary", UserPin = false, Count = 1 })
add({ Name = "RawRPC",         ControlType = "Text", UserPin = false, Count = 1 })
add({ Name = "RawRPCSend",     ControlType = "Button", ButtonType = "Momentary", UserPin = false, Count = 1 })
add({ Name = "RawResponse",    ControlType = "Indicator", IndicatorType = "Text", UserPin = false, Count = 1 })
