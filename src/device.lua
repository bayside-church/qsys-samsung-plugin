-- Device model: connection state machine, capability probe, polling, and the
-- multi-step behaviors (power-on sequence, input cycle-and-verify).
--
-- States:  Disconnected → Connecting → Pairing → Connected
-- Status (Q-SYS inventory, research doc §7.5):
--   OK           connected, authorized, polling
--   Compromised  connected but degraded (websocket unavailable → no input steering)
--   Fault        unreachable, or unauthorized (needs re-pair)
--   Not Present  no IP address configured
--   Initializing connecting / probing

Device = {}

local json = require("rapidjson")

local STATUS = { OK = 0, Compromised = 1, Fault = 2, NotPresent = 3, Missing = 4, Initializing = 5 }
local INPUT_CHOICES = { "HDMI1", "HDMI2", "HDMI3", "HDMI4", "TV" }

Device.state = "Disconnected"
Device.power = nil          -- true / false / nil (unknown)
Device.input = nil
Device.artMode = nil
Device.isFrame = false
Device.caps = {}
Device.steering = false

local BACKOFF_MIN, BACKOFF_MAX = 2, 30
local backoff = BACKOFF_MIN
local reconnectTimer = Timer.New()
local pollTimer = Timer.New()
local pollFailures = 0
local wsDegraded = false

-- Control plumbing ------------------------------------------------------------

local function setStatus(level, msg)
  Controls.Status.Value = STATUS[level]
  Controls.Status.String = msg or ""
end

local function setState(s)
  if Device.state ~= s then
    Log.fn("Device state", Device.state, "->", s)
    Device.state = s
  end
  Controls.ConnectionState.String = s
  Controls.Online.Boolean = (s == "Connected")
end

function Device.setError(msg)
  Controls.LastError.String = msg or ""
  if msg and msg ~= "" then Log.err(msg) end
end

local function refreshStatus()
  if Device.state ~= "Connected" then return end
  if wsDegraded and Device.caps.inputSourceControl == false then
    setStatus("Compromised", "Connected; websocket not paired — input switching unavailable")
  else
    setStatus("OK", "Connected")
  end
end

local function setPower(on)
  Device.power = on
  Controls.PowerState.Boolean = on == true
  Controls.PowerStateText.String = on == nil and "Unknown" or (on and "On" or "Off")
end

local function addChoice(list, v)
  for _, c in ipairs(list) do if c == v then return list end end
  local out = {}
  for i, c in ipairs(list) do out[i] = c end
  out[#out + 1] = v
  return out
end

-- Apply a getTVStates result to the feedback controls.
function Device.applyStates(st)
  if type(st) ~= "table" then return end
  if st.inputSource then
    Device.input = st.inputSource
    Controls.InputState.String = st.inputSource
    if not Device.steering then
      Controls.InputSelect.Choices = addChoice(Controls.InputSelect.Choices or INPUT_CHOICES, st.inputSource)
      Controls.InputSelect.String = st.inputSource
    end
  end
  if st.volume ~= nil then Controls.Volume.Value = tonumber(st.volume) or 0 end
  if st.mute then Controls.Mute.Boolean = (st.mute == "muteOn") end
end

local function applyArtMode(v)
  Device.artMode = (v == "artModeOn")
  Controls.ArtMode.Boolean = Device.artMode
end

-- Reconnect / failure handling ------------------------------------------------

local function scheduleReconnect()
  reconnectTimer:Stop()
  Log.fn("reconnect in", backoff, "s")
  reconnectTimer:Start(backoff)
  backoff = math.min(backoff * 2, BACKOFF_MAX)
end

reconnectTimer.EventHandler = function()
  reconnectTimer:Stop()
  Device.connect()
end

-- Connection lost or never established: Fault, back off, retry.
function Device.lost(msg)
  pollTimer:Stop()
  Ws.disconnect()
  setPower(nil)
  setState("Disconnected")
  setStatus("Fault", msg)
  Device.setError(msg)
  scheduleReconnect()
end

-- Token rejected: stop everything and wait for a human to press Pair.
function Device.unauthorized()
  pollTimer:Stop()
  setState("Pairing")
  setStatus("Fault", "Unauthorized — press Pair (RPC) at the TV")
  Device.setError("TV rejected the RPC token; re-pair required")
end

-- Entry points ----------------------------------------------------------------

function Device.start()
  local ip = Properties["IP Address"].Value
  Controls.InputSelect.Choices = INPUT_CHOICES
  setPower(nil)
  if not ip or ip == "" then
    setState("Disconnected")
    setStatus("NotPresent", "No IP address configured")
    return
  end
  Rpc.init({
    ip = ip,
    port = Properties["RPC Port"].Value,
    token = Controls.RPCToken.String,
  })
  Ws.init({
    ip = ip,
    port = Properties["WebSocket Port"].Value,
    name = Properties["Friendly Name"].Value,
    token = Controls.WSToken.String,
    onEvent = Device.onWsEvent,
  })
  Device.connect()
end

-- Stop all activity (design stop, harness teardown).
function Device.stop()
  pollTimer:Stop()
  reconnectTimer:Stop()
  Rpc.clear()
  Ws.disconnect()
end

function Device.connect()
  reconnectTimer:Stop()
  setState("Connecting")
  setStatus("Initializing", "Connecting")
  Device.fetchInfo(function()
    if Rpc.token == "" then
      Device.pair()
    else
      Device.probe()
    end
  end)
end

-- GET :8001/api/v2/ — plain HTTP, no auth. Model and MAC. Non-fatal.
function Device.fetchInfo(next)
  local url = string.format("http://%s:8001/api/v2/", Rpc.ip)
  Log.tx("HTTP GET", url)
  HttpClient.Download({
    Url = url,
    Timeout = 5,
    EventHandler = function(_, code, data, err)
      Log.rx("HTTP", code, err or "", data or "")
      if code == 200 and data then
        local ok, info = pcall(json.decode, data)
        local dev = ok and type(info) == "table" and info.device or nil
        if dev then
          Controls.Model.String = tostring(dev.modelName or dev.name or "")
          Controls.MAC.String = tostring(dev.wifiMac or "")
        end
      end
      next()
    end,
  })
end

-- createAccessToken. The TV issues the token and draws its approval prompt.
function Device.pair()
  setState("Pairing")
  setStatus("Initializing", "Pairing — approve the prompt on the TV")
  Rpc.call("createAccessToken", nil, function(resp)
    if resp.ok and type(resp.result) == "table" and resp.result.AccessToken then
      Rpc.token = resp.result.AccessToken
      Controls.RPCToken.String = Rpc.token
      Device.setError("")
      Device.probe()
    elseif resp.kind == "transport" then
      Device.lost("Unreachable while pairing: " .. resp.message)
    else
      setStatus("Fault", "Pairing failed — press Pair (RPC) to retry")
      Device.setError("createAccessToken: " .. tostring(resp.message) .. " (" .. tostring(resp.code) .. ")")
    end
  end, false)
end

-- Capability probe (research doc §7.1). Each optional method is called once
-- with a benign get. artModeControl present ⇒ Frame.
--
-- Verified 2026-09-16 on a 2025 Frame: inputSourceControl and
-- directVolumeControl answer -32601 "Method not found" while the TV is in
-- standby, and work normally once it is on. So -32601 only means "absent" when
-- the TV was on at the time; otherwise the capability stays unknown (nil) and
-- the probe re-runs on the next off→on transition.
local PROBE_METHODS = { "artModeControl", "inputSourceControl", "directVolumeControl" }
local capsProbedWhileOn = false

local function publishCaps()
  local caps = Device.caps
  Device.isFrame = caps.artModeControl == true
  local parts = { "rpc" }
  for _, m in ipairs(PROBE_METHODS) do
    local v = caps[m]
    parts[#parts + 1] = m .. (v == true and "" or (v == false and ":no" or ":?"))
  end
  if not capsProbedWhileOn then parts[#parts + 1] = "(probed in standby)" end
  Controls.Capabilities.String = table.concat(parts, " ")
  Controls.ArtMode.IsDisabled = not Device.isFrame
  Controls.Volume.IsDisabled = caps.directVolumeControl == false
end

-- Probe the optional methods. cb() when done. Safe to call again at any time.
function Device.probeMethods(cb)
  cb = cb or function() end
  local caps = Device.caps
  local i = 0
  local function nextProbe()
    i = i + 1
    local m = PROBE_METHODS[i]
    if not m then
      capsProbedWhileOn = capsProbedWhileOn or (Device.power == true)
      publishCaps()
      return cb()
    end
    Rpc.call(m, nil, function(resp)
      if resp.ok then
        caps[m] = true
        if m == "artModeControl" and type(resp.result) == "table" then applyArtMode(resp.result.artMode) end
      elseif resp.kind == "rpc" and resp.code == Rpc.ERR_METHOD_NOT_FOUND then
        if Device.power == true then caps[m] = false elseif caps[m] ~= true then caps[m] = nil end
      elseif Rpc.isUnauthorized(resp, resp.hadToken) then
        return Device.unauthorized()
      elseif resp.kind == "transport" then
        return Device.lost("Unreachable while probing: " .. resp.message)
      end
      -- any other error: leave the cap as it was
      nextProbe()
    end)
  end
  nextProbe()
end

-- Initial probe after (re)connect: auth check, power, then the method probe.
function Device.probe()
  setStatus("Initializing", "Probing capabilities")
  Device.caps = { rpc = true }
  capsProbedWhileOn = false
  -- getTVStates first: it doubles as the auth check.
  Rpc.call("getTVStates", nil, function(resp)
    if resp.ok then
      Device.applyStates(resp.result)
    elseif Rpc.isUnauthorized(resp, resp.hadToken) then
      return Device.unauthorized()
    elseif resp.kind == "transport" then
      return Device.lost("Unreachable: " .. resp.message)
    else
      Device.setError("getTVStates: " .. tostring(resp.message))
    end
    Rpc.call("powerControl", nil, function(r2)
      if r2.ok and type(r2.result) == "table" then setPower(r2.result.power == "powerOn") end
      Device.probeMethods(Device.connected)
    end)
  end)
end

function Device.connected()
  setState("Connected")
  backoff = BACKOFF_MIN
  pollFailures = 0
  refreshStatus()
  Ws.connect()
  local interval = Properties["Poll Interval"].Value
  pollTimer:Stop()
  if interval and interval > 0 then pollTimer:Start(interval) end
  Device.poll()
end

-- Polling ---------------------------------------------------------------------

pollTimer.EventHandler = function() Device.poll() end

local function pollFailed(resp, what)
  if Rpc.isUnauthorized(resp, resp.hadToken) then return Device.unauthorized() end
  if resp.kind == "transport" then
    pollFailures = pollFailures + 1
    if pollFailures >= 2 then Device.lost("Lost contact: " .. resp.message) end
    return
  end
  Device.setError(what .. ": " .. tostring(resp.message))
end

function Device.poll()
  if Device.state ~= "Connected" then return end
  if Rpc.pending() > 2 then return end -- don't pile up behind a stalled TV
  Rpc.call("powerControl", nil, function(resp)
    if not resp.ok then return pollFailed(resp, "powerControl") end
    pollFailures = 0
    local wasOn = Device.power
    setPower(type(resp.result) == "table" and resp.result.power == "powerOn")
    if Device.power and not wasOn and not capsProbedWhileOn then
      Log.fn("TV came on; re-probing capabilities")
      Device.probeMethods(function() refreshStatus() end)
    end
    Rpc.call("getTVStates", nil, function(r2)
      if not r2.ok then return pollFailed(r2, "getTVStates") end
      Device.applyStates(r2.result)
      if Device.isFrame then
        Rpc.call("artModeControl", nil, function(r3)
          if r3.ok and type(r3.result) == "table" then applyArtMode(r3.result.artMode) end
        end)
      end
    end)
  end)
end

-- Websocket events (from Ws.init onEvent) -----------------------------------

function Device.onWsEvent(kind, a, b)
  if kind == "token" then
    Controls.WSToken.String = a
    Log.fn("WS token stored")
  elseif kind == "state" then
    wsDegraded = (a ~= "connected")
    refreshStatus()
  elseif kind == "pairing_refused" then
    wsDegraded = true
    Device.setError("Websocket pairing refused — pair from the TV's own subnet (ms.channel.timeOut)")
    refreshStatus()
  elseif kind == "unauthorized" then
    wsDegraded = true
    Device.setError("Websocket token rejected — press Pair (WebSocket)")
    refreshStatus()
  elseif kind == "error" then
    wsDegraded = true
    refreshStatus()
  end
end

-- Simple commands ------------------------------------------------------------

local function simple(method, params, after)
  Rpc.call(method, params, function(resp)
    if resp.ok then
      Device.setError("")
      if after then after(resp) end
    elseif Rpc.isUnauthorized(resp, resp.hadToken) then
      Device.unauthorized()
    else
      Device.setError(method .. ": " .. tostring(resp.message) .. " (" .. tostring(resp.code) .. ")")
    end
  end)
end

function Device.volumeUp()   simple("volumeUpDnControl", { control = "volumeUp" }, function() Device.poll() end) end
function Device.volumeDown() simple("volumeUpDnControl", { control = "volumeDn" }, function() Device.poll() end) end
function Device.setMute(on)  simple("muteControl", { mute = on and "muteOn" or "muteOff" }) end
function Device.setVolume(v)
  if Device.caps.directVolumeControl == false then
    return Device.setError("Absolute volume not supported on this set; use Volume Up/Down")
  end
  simple("directVolumeControl", { volume = math.floor(tonumber(v) or 0) }, function() Device.poll() end)
end
-- Leaving Art Mode lands the Frame on the Smart Hub while getTVStates keeps
-- reporting the previous input (verified 2026-09-16). So an art-mode exit is
-- always followed by re-issuing an input: `after` if the caller supplies one
-- (the power-on sequence does), otherwise the input the TV claims to be on.
function Device.setArtMode(on, after)
  simple("artModeControl", { artMode = on and "artModeOn" or "artModeOff" }, function()
    applyArtMode(on and "artModeOn" or "artModeOff")
    if on then
      if after then after() end
    elseif after then
      Timer.CallAfter(after, 1.5)
    elseif Device.input and Device.input ~= "" then
      Timer.CallAfter(function() Device.steer(Device.input) end, 1.5)
    end
  end)
end

-- Power -----------------------------------------------------------------------

-- Poll powerControl every 2 s until it reports `target`, or give up.
local function waitForPower(target, deadline, cb)
  local function tick()
    Rpc.call("powerControl", nil, function(resp)
      if resp.ok and type(resp.result) == "table" then
        local on = resp.result.power == "powerOn"
        setPower(on)
        if on == target then return cb(true) end
      end
      deadline = deadline - 2
      if deadline <= 0 then return cb(false) end
      Timer.CallAfter(tick, 2)
    end)
  end
  tick()
end

function Device.powerOff()
  simple("powerControl", { power = "powerOff" }, function()
    Device.steering = false
    waitForPower(false, 20, function(ok)
      if not ok then Device.setError("TV did not report off within 20 s") end
    end)
  end)
end

-- powerOn → wait for on → (Frame) art mode off → steer input.
function Device.powerOn()
  if Properties["Power-On Method"].Value == "None" then return end
  simple("powerControl", { power = "powerOn" }, function()
    waitForPower(true, 40, function(ok)
      if not ok then return Device.setError("TV did not report on within 40 s") end
      local function steer()
        local target = Properties["Input After Power-On"].Value
        if not target or target == "None" then target = Device.input end -- after art mode, re-issue even the current one
        if target and target ~= "" then Device.steer(target) end
      end
      local function afterProbe()
      if Device.isFrame then
        Rpc.call("artModeControl", nil, function(resp)
          if resp.ok and type(resp.result) == "table" and resp.result.artMode == "artModeOn" then
            Device.setArtMode(false, steer)
          else
            steer()
          end
        end)
      else
        steer()
      end
      end
      -- Methods like inputSourceControl only appear once the TV is fully up.
      Timer.CallAfter(function() Device.probeMethods(afterProbe) end, 3)
    end)
  end)
end

function Device.powerToggle()
  if Device.power then Device.powerOff() else Device.powerOn() end
end

-- Input ------------------------------------------------------------------------

-- Preferred path: inputSourceControl (present on current Frame firmware and on
-- commercial panels). Verified with a getTVStates read; falls back to the
-- websocket cycle-and-verify loop if the method is absent or the set fails.
function Device.steer(target, cb)
  cb = cb or function() end
  if not target or target == "" or target == "None" then return cb(true) end
  Device.steering = true
  if Device.caps.inputSourceControl ~= false then -- true or unknown: try the direct path
    Rpc.call("inputSourceControl", { inputSource = target }, function(resp)
      if resp.ok then
        Timer.CallAfter(function()
          Rpc.call("getTVStates", nil, function(r2)
            if r2.ok then Device.applyStates(r2.result) end
            if r2.ok and r2.result.inputSource == target then
              Device.steering = false
              Device.setError("")
              Controls.InputSelect.String = target
              return cb(true)
            end
            Log.fn("inputSourceControl did not take; falling back to key cycling")
            Device.steerByCycling(target, cb)
          end)
        end, 2)
      elseif Rpc.isUnauthorized(resp, resp.hadToken) then
        Device.steering = false
        Device.unauthorized()
        cb(false)
      else
        if resp.kind == "rpc" and resp.code == Rpc.ERR_METHOD_NOT_FOUND and Device.power == true then
          Device.caps.inputSourceControl = false
          publishCaps()
        end
        Device.steerByCycling(target, cb)
      end
    end)
  else
    Device.steerByCycling(target, cb)
  end
end

-- Fallback: press KEY_HDMI (or KEY_TV) over the websocket, read inputSource
-- over RPC, repeat until it matches. Bounded by the attempt cap.
function Device.steerByCycling(target, cb)
  cb = cb or function() end
  local cap = Properties["Input Cycle Attempt Cap"].Value or 6
  local attempts = 0
  Device.steering = true

  local function done(ok, err)
    Device.steering = false
    if ok then
      Device.setError("")
      Controls.InputSelect.String = target
    else
      Device.setError(err)
      if Device.input then Controls.InputSelect.String = Device.input end
    end
    cb(ok)
  end

  local function check()
    Rpc.call("getTVStates", nil, function(resp)
      if not resp.ok then return done(false, "Input steer aborted: " .. tostring(resp.message)) end
      Device.applyStates(resp.result)
      if resp.result.inputSource == target then return done(true) end
      if attempts >= cap then
        return done(false, string.format("Input %s not reached after %d attempts (at %s)", target, attempts, tostring(Device.input)))
      end
      attempts = attempts + 1
      local key = (target == "TV") and "KEY_TV" or "KEY_HDMI"
      Ws.sendKey(key, function(ok, err)
        if not ok then return done(false, "Cannot switch input: " .. tostring(err)) end
        Timer.CallAfter(check, 2.5)
      end)
    end)
  end
  check()
end
