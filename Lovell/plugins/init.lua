--
-- plugins.init.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.09.25",
    DESCRIPTION = "Plugin Library for processing: model, view, control (MVC)",
  }


-- 2026.06.27  Version 0, a loader and dispatcher for individual plugins
-- 2026.09.25  add default plugin configuration with iterator (for processing and display)


local _log = require "logger" (_M)

local love = _G.love
local lf = love.filesystem

-- LOAD

local folder = "plugins"

local dir = lf.getDirectoryItems(folder)


local meta = {__index = {}}
local plugins = setmetatable ({}, meta)

for _, file in ipairs(dir) do
  local name = file: match "([^%.]+)%.lua"
  if name and name ~= "init" then
    local p = require ("%s.%s" % {folder, name}) 
    if type(p) == "table" then
      p.id = p.id or name     -- ensure plugin has an id
      plugins[name] = p
    end
  end
end

-- RESET

function meta.__index: reset()
  for _, plugin in pairs(plugins) do
    if plugin.reset then plugin: reset() end
  end
end

-- DEFAULT PROCESS SEQUENCE CONFIGURATION

local default_sequence = {"balance", "bilateral", "clahe"} -- may be replaced from settings.load()

meta.__index.process_sequence = setmetatable({"balance", "bilateral", "clahe"},
  {__call = function(self)    -- iterator
      local i = 0
      return function()
        while i < self._max do
          i = i + 1
          if self[i] then 
            return i, self[i]
          end
        end
      end
    end,
  __index = {
      _max = 8,
      factory_reset = function(self)
        for i = 1, self._max do
          self[i] = default_sequence[i]    -- overwrite table, DON'T replace! (it would break other references)
        end
      end,
      clear_all = function(self)
        for i = 1, self._max do
          self[i] = nil           -- clear table, DON'T replace!
        end
      end,
      set = function(self, values)
        for i = 1, self._max do
          self[i] = values[i] 
        end
      end,
    },
  })

  
-- DRAW

function meta.__index: draw(name, suit, ...)
  local layout = suit.layout
  local plugin = self[name]
  if not plugin then error ("no such plugin: " .. (tostring(name) or "???"), 2) end
  if not plugin.draw then error ("draw method missing in plugin: " .. name, 2) end
  
  local px, py = layout: padding()
  layout: padding(20, 5)
  if plugin.selected then
    suit: Choosable(plugin, ...)
  else
    suit: Controllable(plugin, ...)
  end
  layout: padding(px, py)
  
  if plugin.extras then
    plugin: extras(suit, ...)
  end
    
end

-- RUN
 
function meta:__call (workflow, name, ...) 
  local plugin = self[name]
  if not plugin then error ("no such plugin: " .. (tostring(name) or "???"), 2) end
  if not plugin.run then error ("run method missing in plugin: " .. name, 2) end
  return plugin.run (plugin, workflow, ...) 
end


return plugins

-----
