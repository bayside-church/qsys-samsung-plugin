-- Samsung IP Control: JSON-RPC 2.0 over HTTPS (port 1516, 1515 on older sets).
--
-- The pure parts (Rpc.envelope, Rpc.classify) have no Q-SYS dependencies so
-- they can be unit tested. The transport part (Rpc.call) serializes requests —
-- one in flight at a time — through Rpc.http, which defaults to
-- HttpClient.Upload and can be swapped for a fake in tests.
--
-- Verified behavior (research doc §3.1, §7.9):
--   * Self-signed cert is accepted by HttpClient with no options.
--   * Success:  {"jsonrpc":"2.0","id":"1","result":{...}}      (id comes back as a string)
--   * RPC err:  {"jsonrpc":"2.0","id":"1","error":{"code":-32601,"message":"..."}}
--   * Bad token:{"code":-32700,"message":"Parse error"}       (flat, not wrapped)

Rpc = {}

local json = require("rapidjson")

Rpc.ERR_METHOD_NOT_FOUND = -32601
Rpc.ERR_INVALID_PARAMS   = -32602
Rpc.ERR_FAILED           = -32002
Rpc.ERR_UNAUTHORIZED     = -32010
Rpc.ERR_PARSE            = -32700 -- what the TV actually returns for a bad token

Rpc.timeout = 10     -- seconds per request
Rpc.http = nil       -- set in Rpc.init; tests inject their own

-- Build the request table. `params` may be nil; the token is merged in when given.
function Rpc.envelope(method, params, token)
  local p = nil
  if params or token then
    p = {}
    if params then for k, v in pairs(params) do p[k] = v end end
    if token and token ~= "" then p.AccessToken = token end
  end
  return { jsonrpc = "2.0", id = 1, method = method, params = p }
end

-- Turn an HttpClient callback into one of:
--   { ok = true,  result = <table or value> }
--   { ok = false, kind = "rpc",       code = <int>, message = <string> }
--   { ok = false, kind = "transport", code = <http code>, message = <string> }
--   { ok = false, kind = "parse",     message = <string> }
function Rpc.classify(code, data, err)
  if err and err ~= "" then
    return { ok = false, kind = "transport", code = code or 0, message = tostring(err) }
  end
  if not data or data == "" then
    return { ok = false, kind = "transport", code = code or 0, message = "empty response (HTTP " .. tostring(code) .. ")" }
  end
  local okDecode, body = pcall(json.decode, data)
  if not okDecode or type(body) ~= "table" then
    return { ok = false, kind = "parse", message = "unparseable body: " .. tostring(data) }
  end
  if body.result ~= nil then
    return { ok = true, result = body.result }
  end
  local e = body.error or body -- wrapped or flat
  if type(e) == "table" and e.code then
    return { ok = false, kind = "rpc", code = tonumber(e.code), message = tostring(e.message or "") }
  end
  if body.jsonrpc then
    -- Observed once on a 2025 Frame right after a set: a bare envelope with
    -- neither result nor error. Treat as a transient failure, not a parse error.
    return { ok = false, kind = "empty", message = "empty JSON-RPC reply" }
  end
  return { ok = false, kind = "parse", message = "unrecognized body: " .. tostring(data) }
end

-- The TV answers a bad/revoked token with -32700 on tested firmware and the
-- reference doc says -32010. Treat both as "re-pair" whenever a token was sent.
function Rpc.isUnauthorized(resp, hadToken)
  if resp.ok or resp.kind ~= "rpc" then return false end
  if resp.code == Rpc.ERR_UNAUTHORIZED then return true end
  return hadToken and resp.code == Rpc.ERR_PARSE
end

-- Transport ------------------------------------------------------------------

local queue = {}
local inflight = false

function Rpc.init(opts)
  Rpc.ip = opts.ip
  Rpc.port = opts.port or 1516
  Rpc.token = opts.token or ""
  Rpc.timeout = opts.timeout or Rpc.timeout
  Rpc.http = opts.http or (HttpClient and HttpClient.Upload)
  queue = {}
  inflight = false
end

function Rpc.url()
  return string.format("https://%s:%d/", Rpc.ip, Rpc.port)
end

local function dispatch()
  if inflight or #queue == 0 then return end
  local job = table.remove(queue, 1)
  inflight = true
  local body = json.encode(job.envelope)
  Log.tx("RPC", body)
  Rpc.http({
    Url = Rpc.url(),
    Method = "POST",
    Headers = { ["Accept"] = "application/json", ["Content-Type"] = "application/json" },
    Data = body,
    Timeout = Rpc.timeout,
    EventHandler = function(_, code, data, err)
      inflight = false
      Log.rx("RPC", "code=" .. tostring(code), err and ("err=" .. tostring(err)) or "", data or "")
      local resp = Rpc.classify(code, data, err)
      resp.raw = data
      resp.hadToken = job.hadToken
      resp.method = job.envelope.method
      local okCb, cbErr = pcall(job.cb, resp)
      if not okCb then Log.err("RPC callback error:", cbErr) end
      dispatch()
    end,
  })
end

-- Queue a call. cb(resp) fires with a classified response. Passing withToken=false
-- sends without the AccessToken (only createAccessToken wants that).
function Rpc.call(method, params, cb, withToken)
  if withToken == nil then withToken = true end
  local env = Rpc.envelope(method, params, withToken and Rpc.token or nil)
  queue[#queue + 1] = { envelope = env, cb = cb or function() end, hadToken = withToken and Rpc.token ~= "" }
  dispatch()
end

function Rpc.pending()
  return #queue + (inflight and 1 or 0)
end

function Rpc.clear()
  queue = {}
end
