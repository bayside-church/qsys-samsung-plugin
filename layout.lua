-- Control layout and graphics for the plugin UI in Designer.
-- Coordinates are pixels within the plugin's rectangle; one page at a time.

local CurrentPage = PageNames[props["page_index"].Value]

local W = 340                 -- overall width
local M = 8                   -- margin inside a group box
local ROW = 24                -- row height for buttons
local FONT = 10

local COLOR_BTN   = { 0, 0, 0 }
local COLOR_GO    = { 0, 140, 0 }
local COLOR_STOP  = { 180, 0, 0 }
local COLOR_WARN  = { 230, 140, 0 }
local COLOR_GROUP = { 220, 220, 220 }

local function group(text, x, y, w, h)
  table.insert(graphics, {
    Type = "GroupBox", Text = text, Fill = COLOR_GROUP, StrokeWidth = 1,
    Position = { x, y }, Size = { w, h }, CornerRadius = 6, FontSize = FONT + 1,
  })
end

local function label(text, x, y, w, h, align)
  table.insert(graphics, {
    Type = "Label", Text = text, Position = { x, y }, Size = { w, h or 20 },
    FontSize = FONT, HTextAlign = align or "Left", VTextAlign = "Center",
  })
end

local function button(name, pretty, legend, x, y, w, h, style, color)
  layout[name] = {
    PrettyName = pretty, Style = "Button", ButtonStyle = style or "Trigger", Legend = legend,
    Position = { x, y }, Size = { w, h or ROW }, Color = color or COLOR_BTN, FontSize = FONT,
  }
end

local function readonly(name, pretty, x, y, w, h, wrap)
  layout[name] = {
    PrettyName = pretty, Style = "Indicator", IndicatorType = "Text", TextBoxStyle = "Normal",
    Position = { x, y }, Size = { w, h or 20 }, FontSize = FONT, HTextAlign = "Left",
    VTextAlign = wrap and "Top" or "Center", WordWrap = wrap or false,
  }
end

local function textbox(name, pretty, x, y, w, h)
  layout[name] = {
    PrettyName = pretty, Style = "Text", TextBoxStyle = "Normal",
    Position = { x, y }, Size = { w, h or 20 }, FontSize = FONT, HTextAlign = "Left",
  }
end

local function led(name, pretty, x, y)
  layout[name] = {
    PrettyName = pretty, Style = "LED", Position = { x, y }, Size = { 16, 16 },
    Color = { 0, 200, 0 }, OffColor = { 40, 40, 40 }, UnlinkOffColor = true, CornerRadius = 8,
  }
end

if CurrentPage == "Control" then
  -- Power ---------------------------------------------------------------------
  local gx, gy, gw = 5, 5, 160
  group("Power", gx, gy, gw, 118)
  button("PowerOn",     "Power On",     "On",     gx + M,      gy + 22, 68, ROW, "Trigger", COLOR_GO)
  button("PowerOff",    "Power Off",    "Off",    gx + M + 76, gy + 22, 68, ROW, "Trigger", COLOR_STOP)
  button("PowerToggle", "Power Toggle", "Toggle", gx + M,      gy + 52, 144, ROW)
  led("PowerState", "Power State", gx + M, gy + 86)
  readonly("PowerStateText", "Power State Text", gx + M + 22, gy + 84, 122, 20)

  -- Input ---------------------------------------------------------------------
  gx = 175
  group("Input", gx, gy, gw, 118)
  layout["InputSelect"] = {
    PrettyName = "Input Select", Style = "ComboBox", Position = { gx + M, gy + 22 },
    Size = { 144, ROW }, FontSize = FONT, HTextAlign = "Left",
  }
  label("Current:", gx + M, gy + 52, 50)
  readonly("InputState", "Input State", gx + M + 52, gy + 52, 92, 20)
  button("HDMICycle", "Cycle HDMI", "Cycle HDMI", gx + M, gy + 84, 144, ROW)

  -- Audio ---------------------------------------------------------------------
  gx, gy = 5, 130
  group("Audio", gx, gy, gw, 96)
  button("VolumeDown", "Volume Down", "Vol −", gx + M,      gy + 22, 44, ROW)
  button("VolumeUp",   "Volume Up",   "Vol +", gx + M + 50, gy + 22, 44, ROW)
  button("Mute",       "Mute",        "Mute",  gx + M + 100, gy + 22, 44, ROW, "Toggle", COLOR_WARN)
  label("Volume:", gx + M, gy + 56, 50)
  layout["Volume"] = {
    PrettyName = "Volume", Style = "Text", Position = { gx + M + 52, gy + 56 },
    Size = { 92, 22 }, FontSize = FONT, HTextAlign = "Center",
  }

  -- The Frame -----------------------------------------------------------------
  gx = 175
  group("The Frame", gx, gy, gw, 96)
  button("ArtMode", "Art Mode", "Art Mode", gx + M, gy + 22, 144, ROW, "Toggle", COLOR_WARN)
  label("Disabled unless the probe finds artModeControl.", gx + M, gy + 52, 144, 36)

  -- Status --------------------------------------------------------------------
  gx, gy = 5, 234
  group("Status", gx, gy, W - 10, 78)
  layout["Status"] = {
    PrettyName = "Status", Style = "Indicator", IndicatorType = "Status",
    Position = { gx + M, gy + 22 }, Size = { W - 10 - 2 * M, ROW }, FontSize = FONT,
  }
  led("Online", "Online", gx + M, gy + 54)
  readonly("ConnectionState", "Connection State", gx + M + 22, gy + 52, 120, 20)
  readonly("Model", "Model", gx + M + 150, gy + 52, W - 10 - 2 * M - 150, 20)

elseif CurrentPage == "Setup" then
  -- Pairing -------------------------------------------------------------------
  local gx, gy = 5, 5
  local gw = W - 10
  group("Pairing", gx, gy, gw, 112)
  button("PairRPC",     "Pairing~Pair RPC",       "Pair (RPC)",       gx + M,       gy + 22, 100, ROW, "Momentary", COLOR_WARN)
  button("PairWS",      "Pairing~Pair WebSocket", "Pair (WebSocket)", gx + M + 106, gy + 22, 110, ROW, "Momentary", COLOR_WARN)
  button("ClearTokens", "Pairing~Clear Tokens",   "Clear Tokens",     gx + M + 222, gy + 22, 94,  ROW, "Momentary", COLOR_STOP)
  label("RPC token:", gx + M, gy + 54, 70)
  layout["RPCToken"] = { PrettyName = "Pairing~RPC Token", Style = "Text", TextBoxStyle = "Normal", IsReadOnly = true,
    Position = { gx + M + 72, gy + 54 }, Size = { gw - 2 * M - 72, 20 }, FontSize = FONT, HTextAlign = "Left" }
  label("WS token:", gx + M, gy + 80, 70)
  layout["WSToken"] = { PrettyName = "Pairing~WebSocket Token", Style = "Text", TextBoxStyle = "Normal", IsReadOnly = true,
    Position = { gx + M + 72, gy + 80 }, Size = { gw - 2 * M - 72, 20 }, FontSize = FONT, HTextAlign = "Left" }

  -- Device --------------------------------------------------------------------
  gy = 125
  group("Device", gx, gy, gw, 96)
  label("Model:", gx + M, gy + 22, 70)
  readonly("Model", "Model", gx + M + 72, gy + 22, gw - 2 * M - 72, 20)
  label("MAC:", gx + M, gy + 46, 70)
  readonly("MAC", "Device~MAC", gx + M + 72, gy + 46, gw - 2 * M - 72, 20)
  label("Capabilities:", gx + M, gy + 70, 70)
  readonly("Capabilities", "Device~Capabilities", gx + M + 72, gy + 70, gw - 2 * M - 72, 20)

  -- Diagnostics ---------------------------------------------------------------
  gy = 229
  group("Diagnostics", gx, gy, gw, 160)
  label("Last error:", gx + M, gy + 22, 70)
  readonly("LastError", "Diagnostics~Last Error", gx + M + 72, gy + 22, gw - 2 * M - 72, 36, true)
  textbox("RawRPC", "Diagnostics~Raw RPC", gx + M, gy + 66, gw - 2 * M - 80, 22)
  button("RawRPCSend", "Diagnostics~Send Raw RPC", "Send RPC", gx + gw - M - 76, gy + 66, 76, 22, "Momentary")
  textbox("RawKey", "Diagnostics~Raw Key", gx + M, gy + 94, gw - 2 * M - 80, 22)
  button("RawKeySend", "Diagnostics~Send Raw Key", "Send Key", gx + gw - M - 76, gy + 94, 76, 22, "Momentary")
  readonly("RawResponse", "Diagnostics~Raw Response", gx + M, gy + 122, gw - 2 * M, 30, true)
end
