--
-- obsession.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "observations and sessions database manager",
  }

-- 2025.01.12  Version 0
-- 2025.01.20  separate title line
-- 2024.02.24  add tally of unique object names


local _log = require "logger" (_M)

local json = require "lib.json"
local utils = require "utils"

local newTimer = utils.newTimer
local formatSeconds = utils.formatSeconds

local love = _G.love
local lf = love.filesystem

-----

local Nsess = 0

local tally = {}          -- {name = count, name2 = count2, ...},   used by observing list

local observations = {
      titles = {"Object", "Session", "Telescope", "Notes"} ,  -- , "Path"}
      tally = tally, 
    }



local function formatSession(x)
--  return string.format("%d-%d-%d", x: sub(1,4) , x:sub(5,6), x:sub(7,8))
end

_M.cols = {
        {"Name",      w = 200, },
        {"OT",        w =  40, },
        {"Con",       w =  50, },
        {"Session",   w =  90, type = "text", format = formatSession, align = "center", },
        {'Time',      w =  50, align = "center", },
        {"Frames",    w =  40, align = "center", type = "number", label = 'N'},
        {"Expo",      w =  70, align = "center", type = "number", format = formatSeconds, },
        {"Filts",     w =  60, },
        {"Size",      w = 100, align = "center", },
        {"Telescope", w = 200, },
        {"Notes",     w = 300, },
        {"Path",      w = 300, },   -- not shown on screen
      }
      
_M.col_index = {1, --[[2,3,]] 4,5,6,7, --[[8,]] 9, 10, 11}

-------------------------
--
-- LOADER
--

function _M.load()
  
  if #observations > 0 then return observations end
  
  local sess_path = "sessions/"
  local tally = tally
  local elapsed = newTimer()
  local sessions = lf.getDirectoryItems(sess_path)
  --
  -- for each session
  --
  for _, filename in ipairs(sessions) do
    local sess_name = filename: match "(%d+)%.json$"
    if sess_name then
      local session = json.read (sess_path .. filename)
      Nsess = Nsess + 1
      --
      -- for each observation
      --
      for path, obs in pairs(session.observations) do
        local name = obs.object or '?'
        tally[name] = (tally[name] or 0) + 1
        observations[#observations + 1] = {
            name, 
            'ot',
            'con',
            sess_name,
            obs.time or '',
            obs.frames or '',     -- number of frames
            obs.exposure or '',
            'filt',
            obs.size,
            obs.telescope or '', 
            obs.notes or '',
            path,
          }
      end
    end
  end
  
  local Nobs = #observations
  for _ in pairs(tally) do
    Nobs = Nobs + 1
  end
  tally.n = Nobs
    
  _log(elapsed("%.3f ms, loaded %d observations from %d sessions", Nobs, Nsess))
  return observations
end


return _M

-----
