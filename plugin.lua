-- Samsung TV Control plugin for Q-SYS Designer.
-- Built on QSC's Basic Framework Plugin (October 2020, updated April 2026).
-- Source modules are combined by PLUGCC via the #include directives below.

-- Information block for the plugin
--[[ #include "info.lua" ]]

-- Define the color of the plugin object in the design
function GetColor(props)
  return { 20, 40, 160 }
end

-- The name that will initially display when dragged into a design
function GetPrettyName(props)
  return "Samsung TV v" .. PluginInfo.Version
end

-- Define User configurable Properties of the plugin
function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end

-- Optional function to update available properties when properties are altered by the user
function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
  return props
end

-- Optional function to define model if plugin supports more than one model. Uncomment if you have a Property named "Model" and don't define Model in PluginInfo
-- function GetModel(props)
--   local model = {}
--   return model
-- end

-- Optional function used if plugin has multiple pages
PageNames = { "Control", "Setup" }  --List the pages within the plugin
function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end

-- Defines the Controls used within the plugin
function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

--Layout of controls and graphics for the plugin UI to display
function GetControlLayout(props)
  local layout = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

-- Optional function to define components used within the plugin
function GetComponents(props)
  local components = {}
  --[[ #include "components.lua" ]]
  return components
end

-- Optional function to define pins on the plugin that are not connected to a Control
function GetPins(props)
  local pins = {}
  --[[ #include "pins.lua" ]]
  return pins
end

-- Optional function to define wiring of components used within the plugin
function GetWiring(props)
  local wiring = {}
  --[[ #include "wiring.lua" ]]
  return wiring
end

--Start event based logic
if Controls then
  --[[ #include "runtime.lua" ]]
end
