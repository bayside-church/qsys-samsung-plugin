-- Runtime half of the plugin. Everything here runs inside `if Controls then`
-- on the Core (or the emulator). Module order matters: each file assumes the
-- globals defined by the ones before it.

--[[ #include "src/log.lua" ]]
--[[ #include "src/rpc.lua" ]]
--[[ #include "src/ws.lua" ]]
--[[ #include "src/device.lua" ]]
--[[ #include "src/ui.lua" ]]

Device.start()
