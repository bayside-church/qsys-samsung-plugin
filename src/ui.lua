-- Wire controls to the device model. Programmatic writes to a control do not
-- fire its EventHandler, so feedback updates in device.lua never loop back here.

local json = require("rapidjson")

Controls.PowerOn.EventHandler     = function() Log.fn("PowerOn");     Device.powerOn() end
Controls.PowerOff.EventHandler    = function() Log.fn("PowerOff");    Device.powerOff() end
Controls.PowerToggle.EventHandler = function() Log.fn("PowerToggle"); Device.powerToggle() end

Controls.InputSelect.EventHandler = function(ctl)
  Log.fn("InputSelect", ctl.String)
  Device.steer(ctl.String)
end
Controls.HDMICycle.EventHandler = function()
  Ws.sendKey("KEY_HDMI", function(ok, err)
    if not ok then Device.setError("HDMI cycle: " .. tostring(err)) end
  end)
end

Controls.VolumeUp.EventHandler   = function() Device.volumeUp() end
Controls.VolumeDown.EventHandler = function() Device.volumeDown() end
Controls.Mute.EventHandler       = function(ctl) Device.setMute(ctl.Boolean) end
Controls.Volume.EventHandler     = function(ctl) Device.setVolume(ctl.Value) end
Controls.ArtMode.EventHandler    = function(ctl) Device.setArtMode(ctl.Boolean) end

-- Pairing ---------------------------------------------------------------------

Controls.PairRPC.EventHandler = function(ctl)
  if not ctl.Boolean then return end -- momentary: act on press only
  if Device.state == "Disconnected" and Controls.Status.Value == 3 then return end -- no IP
  Device.pair()
end

Controls.PairWS.EventHandler = function(ctl)
  if not ctl.Boolean then return end
  Ws.token = ""
  Controls.WSToken.String = ""
  Ws.disconnect()
  Ws.connect()
end

Controls.ClearTokens.EventHandler = function(ctl)
  if not ctl.Boolean then return end
  Controls.RPCToken.String = ""
  Controls.WSToken.String = ""
  Ws.disconnect()
  Device.start()
end

-- Escape hatches --------------------------------------------------------------

Controls.RawKeySend.EventHandler = function(ctl)
  if not ctl.Boolean then return end
  local key = Controls.RawKey.String
  if key == "" then return end
  Ws.sendKey(key, function(ok, err)
    Controls.RawResponse.String = ok and ("sent " .. key) or ("failed: " .. tostring(err))
  end)
end

-- RawRPC accepts either `method` or `method {"json":"params"}`.
Controls.RawRPCSend.EventHandler = function(ctl)
  if not ctl.Boolean then return end
  local text = Controls.RawRPC.String
  local method, rest = text:match("^%s*(%S+)%s*(.*)$")
  if not method then return end
  local params = nil
  if rest and rest ~= "" then
    local ok, parsed = pcall(json.decode, rest)
    if not ok or type(parsed) ~= "table" then
      Controls.RawResponse.String = "params must be a JSON object"
      return
    end
    params = parsed
  end
  Rpc.call(method, params, function(resp)
    Controls.RawResponse.String = tostring(resp.raw or resp.message)
  end)
end
