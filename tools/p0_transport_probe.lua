--[[
  P0 transport probe — run in a plain Control Script component on a real Core.

  Answers the make-or-break Phase 0 questions before any plugin code is written:
    P0-1  Can HttpClient POST to https://<tv>:1516/ against the TV's self-signed cert?
    P0-2  Can WebSocket open wss://<tv>:8002 and receive a token from ms.channel.connect?

  Plus two controls so a failure can be attributed:
    T0    Plain HTTP GET http://<tv>:8001/api/v2/  — proves the Core can reach the TV at all.
    T3    Plain HTTP POST http://<tv>:1516/         — only runs if P0-1 fails; tells us whether
                                                    a non-TLS path exists as a fallback.

  Before running (all three matter — see research doc §3.1):
    * Core must be on the TV's subnet. Pairing prompts never draw cross-subnet.
    * TV must be ON, not in Art Mode.
    * IP Remote enabled: Settings → Connection → Network → Expert Settings → IP Remote.

  Both pairing steps draw an approval prompt on the TV. Someone has to press
  Allow within the timeout. Watch the Control Script's debug output.

  Nothing here is stored. Tokens are printed once so they can be copied by hand.
]]

TV_IP    = "192.168.1.50"   -- <<< set this
RPC_PORT = 1516
WS_PORT  = 8002
WS_NAME  = "Q-SYS Probe"    -- name the TV shows in its device list
TIMEOUT  = 30               -- seconds to wait for someone to press Allow on the TV

json = require("rapidjson")

-- Every line is also accumulated here and emitted as one block at the end, so the
-- whole transcript survives in the script's last log entry (readable over QRC).
LOG = {}
local rawprint = print
local function print(line)
  LOG[#LOG + 1] = tostring(line)
  rawprint(line)
end

-- Never scope sockets locally: Lua's GC will collect them mid-use.
ws = nil

results = {}
local function record(name, ok, detail)
  results[#results + 1] = { name = name, ok = ok, detail = detail }
  print(string.format("[%s] %s — %s", ok and "PASS" or "FAIL", name, detail or ""))
end

local function summary()
  print("\n================ P0 PROBE SUMMARY ================")
  for _, r in ipairs(results) do
    print(string.format("  %-5s %s", r.ok and "PASS" or "FAIL", r.name))
  end
  print("==================================================")
  rawprint("FULL TRANSCRIPT\n" .. table.concat(LOG, "\n"))
end

-------------------------------------------------------------------------------
-- T0: reachability. Plain HTTP; no TLS, no pairing. If this fails, nothing
-- below means anything — it's a network/VLAN problem, not a Q-SYS TLS problem.
-------------------------------------------------------------------------------
local function t0_reachability(next)
  print("\n--- T0: GET http://" .. TV_IP .. ":8001/api/v2/ ---")
  HttpClient.Download {
    Url = "http://" .. TV_IP .. ":8001/api/v2/",
    Timeout = 10,
    EventHandler = function(tbl, code, data, err, headers)
      if code == 200 and data then
        local ok, info = pcall(json.decode, data)
        local dev = ok and type(info) == "table" and info.device or {}
        record("T0 reachability :8001", true,
          string.format("model=%s name=%s fw=%s PowerState=%s",
            tostring(dev.modelName), tostring(dev.name),
            tostring(dev.firmwareVersion), tostring(dev.PowerState)))
      else
        record("T0 reachability :8001", false,
          string.format("code=%s err=%s", tostring(code), tostring(err)))
      end
      next()
    end,
  }
end

-------------------------------------------------------------------------------
-- P0-1: HTTPS JSON-RPC createAccessToken against the self-signed cert.
-------------------------------------------------------------------------------
rpc_ok = false

-- P0-1a: prove the TLS round-trip without needing a pairing prompt. A call with a
-- bogus token makes the TV answer -32010 (unauthorized) as JSON — any JSON-RPC
-- reply at all means HTTPS against the self-signed cert works end to end.
-- This is the test that still works cross-subnet.
local function p0_1a_rpc_tls_noprompt(next)
  print("\n--- P0-1a: POST https://" .. TV_IP .. ":" .. RPC_PORT .. "/ getTVStates (bogus token, no prompt) ---")
  HttpClient.Upload {
    Url = "https://" .. TV_IP .. ":" .. RPC_PORT .. "/",
    Method = "POST",
    Headers = {
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
    },
    Data = json.encode({ jsonrpc = "2.0", id = 1, method = "getTVStates",
                         params = { AccessToken = "not-a-real-token" } }),
    Timeout = 15,
    EventHandler = function(tbl, code, data, err, headers)
      print("    raw: code=" .. tostring(code) .. " err=" .. tostring(err))
      print("    body: " .. tostring(data))
      local ok, resp = pcall(json.decode, data or "")
      if ok and type(resp) == "table" and (resp.error or resp.result) then
        rpc_ok = true
        record("P0-1a HTTPS :1516 TLS round-trip", true,
          "TV answered JSON-RPC over TLS: " .. tostring(data))
      else
        record("P0-1a HTTPS :1516 TLS round-trip", false,
          "code=" .. tostring(code) .. " err=" .. tostring(err) ..
          "  (a cert/TLS error here means Q-SYS refuses self-signed certs)")
      end
      next()
    end,
  }
end

local function p0_1_rpc_tls(next)
  print("\n--- P0-1: POST https://" .. TV_IP .. ":" .. RPC_PORT .. "/ createAccessToken ---")
  print("    >>> Press ALLOW on the TV when the prompt appears (" .. TIMEOUT .. "s) <<<")
  HttpClient.Upload {
    Url = "https://" .. TV_IP .. ":" .. RPC_PORT .. "/",
    Method = "POST",
    Headers = {
      ["Accept"] = "application/json",
      ["Content-Type"] = "application/json",
    },
    Data = json.encode({ jsonrpc = "2.0", id = 1, method = "createAccessToken" }),
    Timeout = TIMEOUT,
    EventHandler = function(tbl, code, data, err, headers)
      print("    raw: code=" .. tostring(code) .. " err=" .. tostring(err))
      print("    body: " .. tostring(data))
      local ok, resp = pcall(json.decode, data or "")
      local token = ok and type(resp) == "table" and resp.result and resp.result.AccessToken
      if token then
        rpc_ok = true
        record("P0-1 HTTPS :1516 self-signed", true, "AccessToken=" .. token)
      elseif code == 200 or (ok and type(resp) == "table" and resp.error) then
        -- TLS worked; the TV just declined (e.g. prompt not approved, Art Mode).
        rpc_ok = true
        record("P0-1 HTTPS :1516 self-signed", true,
          "TLS OK but no token — TV error: " .. tostring(data))
      else
        record("P0-1 HTTPS :1516 self-signed", false,
          "code=" .. tostring(code) .. " err=" .. tostring(err) ..
          "  (a cert/TLS error here means Q-SYS refuses self-signed certs)")
      end
      next()
    end,
  }
end

-------------------------------------------------------------------------------
-- T3: fallback probe — does 1516 answer plain HTTP? Only runs if P0-1 failed.
-------------------------------------------------------------------------------
local function t3_rpc_plain(next)
  if rpc_ok then return next() end
  print("\n--- T3: POST http://" .. TV_IP .. ":" .. RPC_PORT .. "/ (plain, fallback check) ---")
  HttpClient.Upload {
    Url = "http://" .. TV_IP .. ":" .. RPC_PORT .. "/",
    Method = "POST",
    Headers = { ["Content-Type"] = "application/json" },
    Data = json.encode({ jsonrpc = "2.0", id = 1, method = "createAccessToken" }),
    Timeout = 15,
    EventHandler = function(tbl, code, data, err, headers)
      record("T3 plain HTTP :1516", code ~= nil and code ~= 0,
        "code=" .. tostring(code) .. " err=" .. tostring(err) .. " body=" .. tostring(data))
      next()
    end,
  }
end

-------------------------------------------------------------------------------
-- P0-2: wss on 8002, no token → TV prompts → ms.channel.connect carries data.token.
-------------------------------------------------------------------------------
local function p0_2_ws_tls(next)
  local path = "/api/v2/channels/samsung.remote.control?name=" .. Crypto.Base64Encode(WS_NAME)
  print("\n--- P0-2: wss://" .. TV_IP .. ":" .. WS_PORT .. path .. " ---")
  print("    >>> Press ALLOW on the TV when the prompt appears (" .. TIMEOUT .. "s) <<<")

  local done = false
  local function finish(ok, detail)
    if done then return end
    done = true
    record("P0-2 WSS :8002 self-signed", ok, detail)
    if ws then pcall(function() ws:Close() end) end
    next()
  end

  ws = WebSocket.New()
  ws.Connected = function(s)
    print("    socket open (TLS handshake succeeded); waiting for ms.channel.connect")
  end
  ws.Data = function(s, data)
    print("    frame: " .. tostring(data))
    local ok, msg = pcall(json.decode, data)
    if ok and type(msg) == "table" and msg.event == "ms.channel.connect" then
      local token = msg.data and msg.data.token
      if token then
        finish(true, "token=" .. tostring(token))
      else
        finish(true, "connected, but no token in reply (already paired? denied?)")
      end
    end
  end
  ws.Error = function(s, err)
    finish(false, "error=" .. tostring(err) ..
      "  (a cert/TLS error here means Q-SYS refuses self-signed certs on wss)")
  end
  ws.Closed = function(s)
    finish(false, "socket closed before ms.channel.connect")
  end

  Timer.CallAfter(function()
    finish(false, "timed out after " .. TIMEOUT .. "s — no prompt approved, or no frames received")
  end, TIMEOUT)

  ws:Connect("wss", TV_IP, path, WS_PORT)
end

-------------------------------------------------------------------------------
-- Run sequentially. Each step calls the next when its callback fires.
-------------------------------------------------------------------------------
print("P0 transport probe — target " .. TV_IP)
t0_reachability(function()
  p0_1a_rpc_tls_noprompt(function()
    p0_1_rpc_tls(function()
      t3_rpc_plain(function()
        p0_2_ws_tls(summary)
      end)
    end)
  end)
end)
