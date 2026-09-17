--[[
  Runtime harness — runs the plugin's real runtime modules inside a plain
  Control Script (emulation or Core) with fake Properties and Controls, so the
  logic can be exercised against a real TV before the plugin is ever dragged
  onto a canvas.

  Push with:
    python tools/qrc_push_run.py tools/harness_runtime.lua 60 \
        --set TV_IP=<ip> --set RPC_TOKEN=<token> --set SCENARIO=readonly

  Scenarios (SCENARIO):
    readonly   connect, probe, poll; dump state. Changes nothing on the TV.
    audio      readonly + volume up/down + mute on/off round-trip.
    steer      readonly + attempt to steer input to STEER_TARGET (needs websocket).
    artmode    readonly + Art Mode on, then off (Frame only); verifies the input re-issue.
    poweroff   readonly + Power Off (TV goes dark — be sure).
    poweron    readonly + Power On sequence (+ art mode off + steer per property).
]]

TV_IP        = ""
RPC_TOKEN    = ""
WS_TOKEN     = ""
SCENARIO     = "readonly"
STEER_TARGET = "HDMI2"

-- Fake design-time surface --------------------------------------------------
Properties = {
  ["IP Address"]              = { Value = TV_IP },
  ["RPC Port"]                = { Value = 1516 },
  ["WebSocket Port"]          = { Value = 8002 },
  ["Friendly Name"]           = { Value = "Q-SYS Dev" },
  ["Poll Interval"]           = { Value = 5 },
  ["Power-On Method"]         = { Value = "RPC" },
  ["Input After Power-On"]    = { Value = STEER_TARGET },
  ["Input Cycle Attempt Cap"] = { Value = 6 },
  ["Power Off Reports As"]    = { Value = "Compromised" },
  ["Debug Print"]             = { Value = "All" },
}

-- Any Controls.X materializes as a plain table on first touch.
Controls = setmetatable({}, {
  __index = function(t, k)
    local c = { String = "", Value = 0, Boolean = false, Choices = {}, IsDisabled = false }
    rawset(t, k, c)
    return c
  end,
})
Controls.RPCToken.String = RPC_TOKEN
Controls.WSToken.String  = WS_TOKEN

-- Capture everything the runtime prints ---------------------------------------
LOG = {}
local rawprint = print
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  local line = table.concat(parts, " ")
  LOG[#LOG + 1] = line
  rawprint(line)
end

local function dump(title)
  print("")
  print("===== " .. title .. " =====")
  local names = { "ConnectionState", "Status", "Online", "PowerStateText", "InputState", "InputSelect",
                  "Volume", "Mute", "ArtMode", "Model", "MAC", "Capabilities", "LastError", "RPCToken", "WSToken" }
  for _, n in ipairs(names) do
    local c = rawget(Controls, n)
    if c then
      local v = c.String
      if n == "Status" then v = tostring(c.Value) .. " " .. c.String end
      if n == "Online" or n == "Mute" or n == "ArtMode" then v = tostring(c.Boolean) end
      if n == "Volume" then v = tostring(c.Value) end
      if n == "RPCToken" or n == "WSToken" then v = (v ~= "" and (v:sub(1, 6) .. "…") or "(none)") end
      print(string.format("  %-16s %s", n, v))
    end
  end
  print("  Device.state=" .. tostring(Device.state) .. " power=" .. tostring(Device.power) ..
        " input=" .. tostring(Device.input) .. " isFrame=" .. tostring(Device.isFrame))
end

local function finish()
  Device.stop()
  dump("FINAL")
  rawprint("FULL TRANSCRIPT\n" .. table.concat(LOG, "\n"))
end

-- The real runtime ------------------------------------------------------------
--[[ #include "src/log.lua" ]]
--[[ #include "src/rpc.lua" ]]
--[[ #include "src/ws.lua" ]]
--[[ #include "src/device.lua" ]]
--[[ #include "src/ui.lua" ]]

Device.start()

-- Scenario --------------------------------------------------------------------
local function press(name)
  print(">>> press " .. name)
  local c = Controls[name]
  c.Boolean = true
  c.EventHandler(c)
end

local function setToggle(name, on)
  print(">>> set " .. name .. " = " .. tostring(on))
  local c = Controls[name]
  c.Boolean = on
  c.EventHandler(c)
end

Timer.CallAfter(function()
  dump("AFTER CONNECT (8s)")
  if SCENARIO == "readonly" then
    Timer.CallAfter(finish, 6)

  elseif SCENARIO == "audio" then
    press("VolumeUp")
    Timer.CallAfter(function() press("VolumeDown") end, 2)
    Timer.CallAfter(function() setToggle("Mute", true) end, 4)
    Timer.CallAfter(function() dump("MUTED"); setToggle("Mute", false) end, 7)
    Timer.CallAfter(function() print(">>> set Volume = 5"); Controls.Volume.Value = 5; Controls.Volume.EventHandler(Controls.Volume) end, 10)
    Timer.CallAfter(function() print(">>> set Volume = 0"); Controls.Volume.Value = 0; Controls.Volume.EventHandler(Controls.Volume) end, 13)
    Timer.CallAfter(finish, 17)

  elseif SCENARIO == "steer" then
    print(">>> steer to " .. STEER_TARGET)
    Controls.InputSelect.String = STEER_TARGET
    Controls.InputSelect.EventHandler(Controls.InputSelect)
    Timer.CallAfter(finish, 25)

  elseif SCENARIO == "artmode" then
    setToggle("ArtMode", true)
    Timer.CallAfter(function() dump("IN ART MODE"); setToggle("ArtMode", false) end, 8)
    Timer.CallAfter(finish, 20)

  elseif SCENARIO == "poweroff" then
    press("PowerOff")
    Timer.CallAfter(finish, 25)

  elseif SCENARIO == "poweron" then
    press("PowerOn")
    Timer.CallAfter(finish, 60)

  else
    print("unknown SCENARIO " .. tostring(SCENARIO))
    finish()
  end
end, 8)
