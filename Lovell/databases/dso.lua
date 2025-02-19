--
-- dso.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    AUTHOR = "AK Booer",
    DESCRIPTION = "DSO database manager",
  }

-- 2024.11.21  Version 0
-- 2024.11.27  load DSO catalogues
-- 2024.12.02  separate module from session
-- 2024.12.11  add numeric RA and DEC to DSO table

-- 2025.01.12  move RA and DEC formatting to GUI
-- 2025.01.20  separate title line
-- 2025.02.15  ensure Mag and Diam are numeric


local _log = require "logger" (_M)

local csv  = require "lib.csv"

local love = _G.love
local lf = love.filesystem


_M.dsos = {}

local function isNan(x)
  return x ~= x
end

local function one_dp(x)
--  if isNan(x) then _log "NaN" end
  x = (not isNan(x)) and tonumber(x) or 0
  return x - x % 0.1
end


-------------------------
--
-- SEARCH
--

-- search for exact match with object name, returning object info and RA,DEC (or blanks)
function _M.search(text)
  if #text > 0 then 
    local dsos = _M.dsos
    local text = text: lower()            -- case insensitive search
    for i = 1, #dsos do
      local dso = dsos[i]                 -- { Name, RA, Dec, Con, OT, Mag, Diam, Other } 
      local name = dso[1]: lower()
      if name == text then                                      -- exact matched from the start
        local mag = dso[6]
        mag = (not isNan(mag)) and ("Mag " .. mag .. ' ') or ''    -- ie. not NaN
        local object = "%s%s in %s" % {mag, dso[5], dso[4]}
        local RA, DEC = dso[2], dso[3]
        return object, RA, DEC
      end
    end
  end
  return '', '', ''
end

-------------------------
--
-- LOADER
--

function _M.loader (dir)
  local dsos = {}
  dsos.titles = {"Name", "RA", "DEC", "Con", "OT", "Mag", "Diam", "Other"}
  local names = lf.getDirectoryItems(dir)
  for _, filename in ipairs(names or {}) do
    if filename: match "%.csv$" then
      local catalogue = csv.read(dir .. filename)
      
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
        RA, DEC = tonumber(dso[ra]), tonumber(dso[dec])
        CON, OT = dso[con], dso[ot]
        MAG, DIAM = tonumber(dso[mag]), tonumber(dso[diam])
        OTHER = dso[other]
        
        dso[1] = NAME
        dso[2] = RA
        dso[3] = DEC
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
  _M.dsos = dsos
  return dsos
end


return _M

-----
