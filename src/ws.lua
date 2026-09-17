-- Tizen websocket remote: key presses only, no state reads (research doc §3.2).
--
--   wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<b64>&token=<token>
--
-- First connect without a token draws an approval prompt on the TV; the
-- ms.channel.connect reply then carries data.token, which we persist. The TV
-- refuses to pair from off its subnet (immediate ms.channel.timeOut) — that is
-- a network fact, not a bug here.
--
-- The socket object is a global on purpose: Q-SYS documents that a locally
-- scoped WebSocket gets garbage-collected mid-use.

Ws = {}

local json = require("rapidjson")

Ws.state = "disconnected"   -- disconnected | connecting | connected
Ws.token = ""
Ws.keyGap = 0.1             -- seconds between key presses
Ws.enabled = false

local sock = nil
local keyQueue = {}
local keyTimer = nil
local sending = false
local reconnectTimer = nil
local backoff = 2
local onEvent = function(...) end   -- Device hooks this: onEvent(name, detail)

local function b64(s)
  if Crypto and Crypto.Base64Encode then return Crypto.Base64Encode(s) end
  return s
end

function Ws.init(opts)
  Ws.ip = opts.ip
  Ws.port = opts.port or 8002
  Ws.name = opts.name or "Q-SYS"
  Ws.token = opts.token or ""
  onEvent = opts.onEvent or onEvent
  keyQueue = {}
  sending = false
  if not reconnectTimer then
    reconnectTimer = Timer.New()
    reconnectTimer.EventHandler = function()
      reconnectTimer:Stop()
      if Ws.enabled and Ws.state == "disconnected" then Ws.connect() end
    end
  end
  if not keyTimer then
    keyTimer = Timer.New()
    keyTimer.EventHandler = function()
      keyTimer:Stop()
      sending = false
      Ws.flush()
    end
  end
end

function Ws.path()
  local p = "/api/v2/channels/samsung.remote.control?name=" .. b64(Ws.name)
  if Ws.token ~= "" then p = p .. "&token=" .. Ws.token end
  return p
end

local function setState(s, detail)
  if Ws.state ~= s then
    Ws.state = s
    Log.fn("WS state", s, detail or "")
    onEvent("state", s, detail)
  end
end

function Ws.connect()
  if not Ws.ip or Ws.ip == "" then return end
  if Ws.state ~= "disconnected" then return end
  Ws.enabled = true
  if sock then pcall(function() sock:Close() end) end
  sock = WebSocket.New()
  WsSocket = sock -- keep a global reference; see header comment
  setState("connecting")

  sock.Connected = function()
    Log.fn("WS socket open")
    -- stay "connecting" until ms.channel.connect confirms the TV accepted us
  end
  sock.Data = function(_, data)
    Log.rx("WS", data)
    local ok, msg = pcall(json.decode, data)
    if not ok or type(msg) ~= "table" then return end
    if msg.event == "ms.channel.connect" then
      local tok = msg.data and msg.data.token
      if tok and tok ~= "" and tok ~= Ws.token then
        Ws.token = tok
        onEvent("token", tok)
      end
      backoff = 2
      setState("connected")
      Ws.flush()
    elseif msg.event == "ms.channel.timeOut" then
      if Ws.token == "" then
        -- No token: the TV refused to pair (off-subnet, or nobody pressed Allow).
        -- Don't hammer it with prompts — wait for Pair (WebSocket).
        Ws.enabled = false
        onEvent("pairing_refused", "ms.channel.timeOut")
      else
        -- With a token this is the TV in standby (or momentarily busy); keep
        -- reconnecting on backoff so control resumes when it wakes.
        onEvent("standby", "ms.channel.timeOut")
      end
    elseif msg.event == "ms.channel.unauthorized" then
      onEvent("unauthorized", "ms.channel.unauthorized")
    end
  end
  sock.Error = function(_, err)
    Log.err("WS error:", err)
    onEvent("error", tostring(err))
  end
  sock.Closed = function()
    Log.fn("WS closed")
    setState("disconnected")
    if Ws.enabled then
      reconnectTimer:Stop()
      reconnectTimer:Start(backoff)
      backoff = math.min(backoff * 2, 30)
    end
  end

  Log.tx("WS connect", Ws.ip, Ws.port, Ws.path())
  sock:Connect("wss", Ws.ip, Ws.path(), Ws.port)
end

function Ws.disconnect()
  Ws.enabled = false
  if reconnectTimer then reconnectTimer:Stop() end
  keyQueue = {}
  if sock then pcall(function() sock:Close() end) end
  setState("disconnected")
end

-- Queue a keycode (e.g. "KEY_HDMI"). Paced by Ws.keyGap. cb(ok, err) optional.
function Ws.sendKey(key, cb)
  keyQueue[#keyQueue + 1] = { key = key, cb = cb }
  Ws.flush()
end

function Ws.flush()
  if sending or #keyQueue == 0 then return end
  if Ws.state ~= "connected" then
    -- fail everything queued rather than silently holding keys forever
    local q = keyQueue; keyQueue = {}
    for _, item in ipairs(q) do
      if item.cb then item.cb(false, "websocket not connected") end
    end
    return
  end
  local item = table.remove(keyQueue, 1)
  local frame = json.encode({
    method = "ms.remote.control",
    params = { Cmd = "Click", DataOfCmd = item.key, Option = "false", TypeOfRemote = "SendRemoteKey" },
  })
  Log.tx("WS", frame)
  local ok, err = pcall(function() sock:Write(frame) end)
  if item.cb then item.cb(ok, err) end
  sending = true
  keyTimer:Start(Ws.keyGap)
end
