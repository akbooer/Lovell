--
-- databases.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.09",
    DESCRIPTION = "Databases - DSOs, observing list, telescopes, ...",
  }


-- 2025.01.08  Version 0
-- 2025.01.13  add generic search function
-- 2025.01.20  separate titles in telescope loader
-- 2025.02.08  refactor autoload handling and return all module methods
-- 2025.02.09  include watchlist database code


local _log = require "logger" (_M)

local csv  = require "lib.csv"
local json = require "lib.json"

_M.dsos         = require "databases.dso"
_M.observations = require "databases.obsess"
_M.calibration  = require "databases.calibration"

local empty = _G.READONLY {}

local floor = math.floor

-- autoload database when first referenced
local function autoload(M, filename)
  return setmetatable(M,
      {__index =  function(self, name)
                    if name == "DB" then
                      _log ("autoload " .. filename)
                      local DB = self.loader(filename)
                      rawset(self, "DB", DB)
                      return DB
                    end
                  end})
end

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

  loader = function (name)
    local data = csv.read(name)
    data.titles = data[1]
    table.remove(data, 1)
    _log ("# telescopes %d" % #data)
    return data
  end,

  focal_length = function(self, scope)
    local db = self.DB
    local NAME, NUMBER = scope: lower() : match "(%w+)%D*(%d+)"  
    for i = 2, #db do          -- skip over header row
      local name, number, focus = unpack(db[i])
      if name:lower() == NAME and number == NUMBER then
        return focus
      end
    end
  end,
}

-------------------------------
--
-- WATCH LIST
--

_M.watchlist = {

  cols = {
      {"Name", w = 250, },
      {"Date", w = 100, },
    },
  
  loader = function(filename)
    local x = json.read(filename)
    local watch = {}
    for n, d in pairs(x or empty) do
      watch[#watch+1] = {n, d}
    end
    return watch
  end,

  add = function(self, catalogue)
    local date = os.date "%d %b"  -- day month
    _log(date)
    local db = self.DB
    local sel = catalogue.highlight
    local data = catalogue.grid.data
    for i in pairs(sel) do
      local item = data[i]
      if item then
        db[#db+1] = {item[1], date}  -- first element is item name
      end
    end
  end,

  remove = function(catalogue)
    
  end,
  
  save = function()
    json.write("observing_list.json", XXX)
  end,
  
}

-------------------------------
--
-- AUTOLOAD
--

autoload (_M.watchlist, "observing_list.json")
autoload (_M.telescopes, "databases/telescopes.csv")
autoload (_M.dsos, "dsos/")
autoload (_M.calibration, "masters/")
autoload (_M.observations, "sessions/")


return _M

-----

