--
-- fitsheaders.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.18",
    DESCRIPTION = "FITS headers for current observation",
  }

-- 2026.06.06  Version 0
-- 2026.06.18  access stack object directly


local _log = require "logger" (_M)

local stacking = require "stacking"


------------------------------
--
-- HEADERS
--

local cols = {
        {"Name",    w = 120, },
        {"Value",   w = 360, align = "left"},
        {"Comment", w = 600, },
      }

local widget = {cols = cols, data = {}}    -- SUIT-able Table widget


local stack

function _M.update(suit)
--  local layout = suit.layout
--  local function col(...) return layout: col(...) end
  
  local new_stack = stacking: get()
  if stack ~= new_stack then
    stack = new_stack
    if not stack then return end
    
    _log "loading new FITS headers"
    local data = {}
    widget = {cols = cols, data = data}
    
--    local db = controls.stack.headers
    local db = stack.headers
    for i, info in ipairs(db) do
      local name, equals, value, slash, comment = info: match "([A-Z0-9-_]+)%s*(=?)%s*([^/]+)(/?)%s*(.*)"
      local eq = equals == "="
      data[i] = {name, eq and value or '', eq and comment or value}
    end
    
  end
  
--TODO: add slider to move through frames
end

function _M.load()
  return widget
end


return _M

-----

