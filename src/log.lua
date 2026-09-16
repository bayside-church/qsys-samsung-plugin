-- Debug printing gated by the "Debug Print" property.
--   Log.tx(...)  outbound traffic      (Tx, Tx/Rx, All)
--   Log.rx(...)  inbound traffic       (Rx, Tx/Rx, All)
--   Log.fn(...)  function-level trace  (Function Calls, All)
--   Log.err(...) always printed

Log = {}

local mode = (Properties["Debug Print"] and Properties["Debug Print"].Value) or "None"

local function on(kind)
  if mode == "All" then return true end
  if kind == "tx" then return mode == "Tx" or mode == "Tx/Rx" end
  if kind == "rx" then return mode == "Rx" or mode == "Tx/Rx" end
  if kind == "fn" then return mode == "Function Calls" end
  return false
end

local function emit(prefix, ...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
  print(prefix .. " " .. table.concat(parts, " "))
end

function Log.tx(...)  if on("tx") then emit("[TX]", ...) end end
function Log.rx(...)  if on("rx") then emit("[RX]", ...) end end
function Log.fn(...)  if on("fn") then emit("[FN]", ...) end end
function Log.err(...) emit("[ERR]", ...) end
