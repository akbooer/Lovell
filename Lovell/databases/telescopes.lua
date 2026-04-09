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

_M.cols = {
      {"Name",   w = 250, },
      {"Diameter", w = 120, type = "number", align = "center"},
      {"Focal length (mm)", w = 200, type = "number", align = "right"},
    }

function _M:load()
  local data = csv.read "databases/telescopes.csv"
  data.titles = data[1]
  table.remove(data, 1)
  _log ("# loaded database, total: %d" % #data)
  return data
end

function _M:focal_length(scope)
  local db = self.DB or self.load()
  self.DB = db
  local NAME, NUMBER = scope: lower() : match "(%w+)%D*(%d+)"  
  for i = 2, #db do          -- skip over header row
    local name, number, focus = unpack(db[i])
    if name:lower() == NAME and number == NUMBER then
      return focus
    end
  end
end


return _M

-----

