--[[
  Unit tests for src/rpc.lua — the pure parts (envelope, classify,
  isUnauthorized) plus the queue, using a fake HTTP function. No TV needed.

  Run in the emulator (there is no standalone Lua on the dev PC):
    python tools/qrc_push_run.py tools/test_rpc.lua 10
]]

Properties = { ["Debug Print"] = { Value = "None" } }
LOG = {}
local rawprint = print
print = function(...) LOG[#LOG + 1] = table.concat({ ... }, " ") end

--[[ #include "src/log.lua" ]]
--[[ #include "src/rpc.lua" ]]

local json = require("rapidjson")
local pass, fail = 0, 0
local function check(name, cond, detail)
  if cond then pass = pass + 1 else fail = fail + 1; LOG[#LOG + 1] = "FAIL " .. name .. (detail and (": " .. tostring(detail)) or "") end
end

-- envelope ----------------------------------------------------------------
local e = Rpc.envelope("getTVStates", nil, "tok")
check("envelope basic", e.jsonrpc == "2.0" and e.id == 1 and e.method == "getTVStates")
check("envelope token merged", e.params and e.params.AccessToken == "tok")
e = Rpc.envelope("createAccessToken", nil, nil)
check("envelope no params when nothing to send", e.params == nil)
e = Rpc.envelope("powerControl", { power = "powerOn" }, "tok")
check("envelope params + token", e.params.power == "powerOn" and e.params.AccessToken == "tok")
local orig = { power = "powerOn" }
Rpc.envelope("powerControl", orig, "tok")
check("envelope does not mutate caller params", orig.AccessToken == nil)
e = Rpc.envelope("x", { a = 1 }, "")
check("envelope empty token omitted", e.params.AccessToken == nil and e.params.a == 1)

-- classify ----------------------------------------------------------------
local r = Rpc.classify(200, '{"jsonrpc":"2.0","id":"1","result":{"power":"powerOn"}}', nil)
check("classify success", r.ok and r.result.power == "powerOn")
r = Rpc.classify(200, '{"jsonrpc":"2.0","id":"1","error":{"code":-32601,"message":"Method not found"}}', nil)
check("classify wrapped error", not r.ok and r.kind == "rpc" and r.code == -32601)
r = Rpc.classify(200, '{"code": -32700, "message": "Parse error"}', nil)
check("classify flat error", not r.ok and r.kind == "rpc" and r.code == -32700 and r.message == "Parse error")
r = Rpc.classify(0, nil, "Timeout was reached")
check("classify transport error", not r.ok and r.kind == "transport" and r.message:find("Timeout"))
r = Rpc.classify(200, "", nil)
check("classify empty body", not r.ok and r.kind == "transport")
r = Rpc.classify(200, "<html>nope</html>", nil)
check("classify garbage", not r.ok and r.kind == "parse")
r = Rpc.classify(200, '{"jsonrpc":"2.0","id":"1"}', nil)
check("classify bare envelope", not r.ok and r.kind == "empty")
r = Rpc.classify(200, '{"jsonrpc":"2.0","id":"1","result":{"volume":0}}', nil)
check("classify result with zero survives", r.ok and r.result.volume == 0)

-- isUnauthorized ----------------------------------------------------------
check("unauth -32010", Rpc.isUnauthorized({ ok = false, kind = "rpc", code = -32010 }, false))
check("unauth -32700 with token", Rpc.isUnauthorized({ ok = false, kind = "rpc", code = -32700 }, true))
check("no unauth -32700 without token", not Rpc.isUnauthorized({ ok = false, kind = "rpc", code = -32700 }, false))
check("no unauth on -32601", not Rpc.isUnauthorized({ ok = false, kind = "rpc", code = -32601 }, true))
check("no unauth on transport", not Rpc.isUnauthorized({ ok = false, kind = "transport", code = 0 }, true))
check("no unauth on success", not Rpc.isUnauthorized({ ok = true }, true))

-- queue: one in flight, in order, callback errors don't stall --------------
local sent, handlers = {}, {}
Rpc.init({ ip = "1.2.3.4", port = 1516, token = "tok", http = function(t)
  sent[#sent + 1] = json.decode(t.Data)
  handlers[#handlers + 1] = t.EventHandler
end })
local got = {}
Rpc.call("a", nil, function(resp) got[#got + 1] = "a"; error("boom") end)
Rpc.call("b", { x = 1 }, function(resp) got[#got + 1] = "b:" .. tostring(resp.result.y) end)
Rpc.call("c", nil, function() got[#got + 1] = "c" end, false)
check("only one request in flight", #sent == 1 and Rpc.pending() == 3)
check("first request is a with token", sent[1].method == "a" and sent[1].params.AccessToken == "tok")
handlers[1](nil, 200, '{"jsonrpc":"2.0","id":"1","result":{}}', nil)
check("callback error does not stall queue", #sent == 2 and sent[2].method == "b")
check("params carried", sent[2].params.x == 1 and sent[2].params.AccessToken == "tok")
handlers[2](nil, 200, '{"jsonrpc":"2.0","id":"1","result":{"y":7}}', nil)
check("third sent without token", #sent == 3 and sent[3].params == nil)
handlers[3](nil, 200, '{"jsonrpc":"2.0","id":"1","result":{}}', nil)
check("all callbacks in order", table.concat(got, ",") == "a,b:7,c", table.concat(got, ","))
check("queue drained", Rpc.pending() == 0)
check("url", Rpc.url() == "https://1.2.3.4:1516/")

rawprint(string.format("FULL TRANSCRIPT\nrpc tests: %d passed, %d failed\n%s", pass, fail, table.concat(LOG, "\n")))
