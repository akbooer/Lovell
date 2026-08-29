--
-- telescopes.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.03.29",
    DESCRIPTION = "Telescopes - name, diameter, focal length, ...",
  }

-- 2025.01.08  Version 0

-- 2026.03.29  separate from databases.init


local _log = require "logger" (_M)

local csv  = require "lib.csv"

-------------------------------
--
-- TELESCOPE database (CSV)
--

local cols = {
      {"Name",   w = 250, },
      {"Diameter", w = 120, type = "number", align = "center"},
      {"Focal length (mm)", w = 200, type = "number", align = "right"},
    }

local widget = {cols = cols}    -- SUIT-able Table widget


function _M:load()
  
  if widget.data then return widget end     -- only load data once
  
  local data = csv.read "resources/telescopes.csv"
  table.remove(data, 1)                             -- don't want the title line
  _log ("loaded database, total: %d" % #data)
  widget = {cols = cols, data = data}
  return widget
end

function _M:focal_length(scope)
  if not widget.data then self.load() end
  local data = widget.data
  local NAME, NUMBER = scope: lower() : match "(%w+)%D*(%d+)"  
  for i = 2, #data do          -- skip over header row
    local name, number, focus = unpack(data[i])
    if name:lower() == NAME and number == NUMBER then
      return focus
    end
  end
end

return _M

-----

