--
-- databases.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    DESCRIPTION = "Databases - DSOs, observing list, telescopes, ...",
  }


-- 2025.01.08  Version 0
-- 2025.01.20  separate titles in telescope loader
-- 2025.02.09  include watchlist database code


local _log = require "logger" (_M)

local csv  = require "lib.csv"
local json = require "lib.json"

_M.dsos         = require "databases.dso"
_M.observations = require "databases.obsessions"
_M.calibration  = require "databases.calibration"

local empty = _G.READONLY {}


-------------------------------
--
-- TELESCOPE database (CSV)
--

_M.telescopes = {

  cols = {
      {"Name",   w = 250, },
      {"Diameter", w = 120, type = "number", align = "center"},
      {"Focal length (mm)", w = 200, type = "number", align = "right"},
    },

  load = function()
    local data = csv.read "databases/telescopes.csv"
    data.titles = data[1]
    table.remove(data, 1)
    _log ("# telescopes %d" % #data)
    return data
  end,

  focal_length = function(self, scope)
    local db = self.DB or self.load()
    self.DB = db
    local NAME, NUMBER = scope: lower() : match "(%w+)%D*(%d+)"  
    for i = 2, #db do          -- skip over header row
      local name, number, focus = unpack(db[i])
      if name:lower() == NAME and number == NUMBER then
        return focus
      end
    end
  end,
}


return _M

-----

