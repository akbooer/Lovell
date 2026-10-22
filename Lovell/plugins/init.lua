--
-- plugins.init.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.20",
    DESCRIPTION = "Plugin Library for processing: model, view, control (MVC)",
  }


-- 2026.06.27  Version 0, a loader and dispatcher for individual plugins
-- 2026.09.25  add default plugin configuration with iterator (for processing and display)
-- 2026.10.05  change plugin default configuration to include GHS (NB. filename is 'ghs')
-- 2026.10.12  add performance profiling
-- 2026.10.20  add process_sequence: get_splits() and set_splits() for plugin menus


local _log = require "logger" (_M)

local profiler    = require "utils" .profiler

local love = _G.love
local lf = love.filesystem
local lt = love.timer

local EMPTY = _G.READONLY {}

-- EXTRAS

local right = {align = "right"}

local function menu_split(self, suit)
  local sl = suit.layout
  local x,y, w = sl:row(nil, 5)  
  if suit: Checkbox(self._split, x + w - 5,y, 20, 20) .hovered then
    suit: Label("split menu", right, x + w - 100, y, 90, 20)
  end

  if not self._split.checked and self._extras then
    sl: row(0,0)
    self: _extras(suit, w)       -- ...include them here (otherwise defer)
  end
end


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
      p._extras = p.extras      -- save user-defined additional menu
      p.extras = menu_split
      p._split = {checked = p.split }   -- initialise to user requirement
      plugins[name] = p
    end
  end
end

-- RESET

-- reset named, or all, plugins
function meta.__index: reset(name, ...)
  if name and plugins[name] then
    plugins[name]: newframe(...)
  else
    for _, plugin in pairs(plugins) do
      if plugin.reset then plugin: reset(...) end
    end
  end
end

-- DEFAULT PROCESS SEQUENCE CONFIGURATION

local default_sequence = {"ghs", "bilateral", "clahe"} -- filenames may be replaced from settings.load()

meta.__index.process_sequence = setmetatable({"balance", "bilateral", "clahe"},
  {__call = function(self)    -- iterator
      local i = 0
      return function()
        while i < self._max do
          i = i + 1
          if plugins[self[i]] then    -- existential check! (eg. maybe invalid sequence loaded at startup)
            -- returns: sequence number, plugin
            return i, self[i]
          else
            self[i] = nil             -- remove nonexistent one from list
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
      set = function(self, values)    -- set to given values
        for i = 1, self._max do
          self[i] = values[i] 
        end
      end,
      get_splits  = function(self)    -- get names of split plugins
        local s = {}
        for name, plugin in pairs(plugins) do
          if (plugin._split or EMPTY) .checked then
            s[#s+1] = name
          end
        end
        return #s > 0 and s or nil
      end,
      set_splits  = function(self, names)    -- set split plugins by name
        local index = {}
        for _, name in ipairs(names or EMPTY) do
          index[name] = true
        end
        for name, plugin in pairs(plugins) do
          if plugin._split then 
            if names then
              plugin._split.checked = not not index[name]
            else
                -- leave as it is
            end
          end
        end
      end,
      
    },
  })

-- PROFILING

local profile = profiler(200e-6)    -- ignore anything under 200 microseconds

function meta.__index: profile()
  return profile: report()
end

  
-- DRAW

function meta.__index: draw(name, suit, ...)
  local layout = suit.layout
  local plugin = self[name]
  if not plugin then error ("no such plugin: " .. (tostring(name) or "???"), 2) end
  if not plugin.draw then error ("draw method missing in plugin: " .. name, 2) end
  
  local px, py = layout: padding()
  layout: padding(20, 5)
  if plugin.selected then           -- it's simple list of menu choices, or...
    suit: Choosable(plugin, ...)
  else                              -- ...it's a user-defined panel
    if suit: Controllable(plugin, ...) .hit and suit.optionKey() then 
      -- toggle split if option key pressed
      if plugin._split then
        plugin._split.checked = not plugin._split.checked
      end
    end
  end
  layout: padding(px, py)
  
  if plugin._extras and plugin._split and plugin._split.checked  then
    layout: row(0,0)
    plugin: _extras(suit)
    layout: row(nil,5)
  end
    
end

-- RUN
 
function meta:__call (workflow, name, ...) 
  local plugin = self[name]
  if not plugin then error ("no such plugin: " .. (tostring(name) or "???"), 2) end
  if not plugin.run then error ("run method missing in plugin: " .. name, 2) end
  -- gather stats on plugin runtimes and invocations...
  local t = lt.getTime()
  local reply =  plugin.run (plugin, workflow, ...) 
  profile: add(name, lt.getTime() - t)
  return reply
end


return plugins

-----
