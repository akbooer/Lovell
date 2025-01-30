--
-- databases.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.20",
    DESCRIPTION = "Databases - DSOs, telescopes, ...",
  }


-- 2025.01.08  Version 0
-- 2025.01.13  add generic search function
-- 2025.01.20  separate titles in telescoppe loader


local _log = require "logger" (_M)

local csv = require "databases.csv"
local dso = require "databases.dso"
local obs = require "databases.obsess"

local watch = require "databases.obslist"

local floor = math.floor

-- autoload database when first referenced
local function autoload(filename, reader)
  reader = reader or csv.read_column_wise
  return setmetatable({},
      {__index =  function(self, db)
                    if db == "DB" then
                      _log ("autoload " .. filename)
                      local DB = reader(filename)
                      rawset(self, db, DB)
                      return DB
                    end
                  end})
end

-------------------------------
--
-- TELESCOPE database (CSV)
--

local function teleread(name)
  local data = csv.read(name)
  data.titles = data[1]
  table.remove(data, 1)
  return data
end

local telescopes = autoload ("databases/telescopes.csv", teleread)

_M.telescopes = telescopes

function telescopes.focal_length(scope)
  local db = telescopes.DB
  local NAME, NUMBER = scope: lower() : match "(%w+)%D*(%d+)"  
  for i = 2, #db do          -- skip over header row
    local name, number, focus = unpack(db[i])
    if name:lower() == NAME and number == NUMBER then
      return focus
    end
  end
end

-------------------------------
--
-- DSOs
--

_M.dsos = autoload("dsos/", dso.loader)


-------------------------------
--
-- OBSERVATIONS
--

_M.observations = autoload("sessions/", obs.loader)


-------------------------------
--
-- SEARCHES
--

function _M.searchDSO(text)
  local _ = _M.dsos.DB    -- ensure database loaded
  return dso.search(text)
end


-------------------------
--
-- FORMATTING
--

-- convert decimal degrees to DDD MM SS
local function deg_to_dms(deg)
  local sign = 1
  if deg < 0 then
    sign = -1
    deg = -deg
  end
  local d, m, s
  d = floor(deg)
  m = 60 * (deg - d)
  s = floor(60 * (m % 1) + 0.5)
  m = floor(m)
  return sign * d, m, s
end

-- convert decimal RA to HH MM SS
local function formatRA(RA)
  local ra = tonumber(RA)
  return ra and string.format ("%02dh %02d %02d", deg_to_dms(ra / 15)) or RA
end

-- convert decimal DEC to ±DDº MM SS
local function formatDEC(DEC)
  local dec = tonumber(DEC)
  return dec and string.format("%+02dº %02d %02d", deg_to_dms(dec)) or DEC
end

_M.formatRA  = formatRA
_M.formatDEC = formatDEC


return _M

-----

