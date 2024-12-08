--
-- dso.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.02",
    AUTHOR = "AK Booer",
    DESCRIPTION = "DSO manager",
  }

-- 2024.11.21  Version 0
-- 2024.11.27  load DSO catalogues
-- 2024.12.02  separate module from session


local _log = require "logger" (_M)

local CSV = require "lib.csv"
local observer        = require "observer"
local channelOptions  = require "shaders.colour"  .channelOptions
local gammaOptions    = require "shaders.stretcher" .gammaOptions

local love = _G.love
local lf = love.filesystem


_M.dsos = {}

local function one_dp(x)
  x = tonumber(x) or 0
  return x - x % 0.1
end

-- convert decimal degrees to DDD MM SS
local floor = math.floor
local function deg_to_dms(deg)
  deg = tonumber(deg)
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

function _M.load()
  local dsos = _M.dsos
  local names = lf.getDirectoryItems "dsos"
  for _, filename in ipairs(names or {}) do
    if filename: match "%.csv$" then
      local catalogue = CSV.read("dsos/" .. filename)
      
      -- read headers
      -- Name, RA, Dec, Con, OT, Mag, Diam, Other  (but not always!)
      
      local col = catalogue[1]
      for i = 1, #col do                     -- index the (lowercase) column names
        col[col[i]: lower()] = i
      end
      
      local name , ra,  dec, con, ot, mag, diam, other
      
      name      = col.name 
      ra,  dec  = col.ra,  col.dec 
      con, ot   = col.con, col.ot
      mag, diam = col.mag, col.diam
      other     = col.other
      
      local NAME, RA, DEC, CON, OT, MAG, DIAM, OTHER    -- temporaries
      
      -- read rows
      for i = 2, #catalogue do                           -- skip over title line
        local dso = catalogue[i]
--        _log (i, table.concat(dso, ' '))
        
        NAME = dso[name]
        RA, DEC = dso[ra], dso[dec]
        CON, OT = dso[con], dso[ot]
        MAG, DIAM = dso[mag], dso[diam]
        OTHER = dso[other]
        
        dso[1] = NAME
        dso[2] =  "%02dh %02d %02d" % {deg_to_dms(RA / 15)}
        dso[3] = "%+02dº %02d %02d" % {deg_to_dms(DEC)}
        dso[4] = CON
        dso[5] = OT
        dso[6] = one_dp(MAG)
        dso[7] = one_dp(DIAM)
        dso[8] = OTHER or ''
        
        dsos[#dsos+1] = dso
      end
    end
  end
  _log ("# DSOs %d" % #dsos)
end

-----

return _M

-----
