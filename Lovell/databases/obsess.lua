--
-- obsess.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "observations and sessions database manager",
  }

-- 2025.01.12  Version 0
-- 2025.01.20  separate title line


local _log = require "logger" (_M)

local csv = require "lib.csv"
local json = require "lib.json"
local newTimer = require "utils" .newTimer

local love = _G.love
local lf = love.filesystem

-----

local Nsess = 0

local observations = {
      titles = {"Object", "Session", "Telescope", "Notes"}  -- , "Path"}
    }

_M.cols = {
        {"Object",    w = 200, },
        {"Session",   w = 100, type = "number", align = "center"},
        {"Telescope", w = 200, },
        {"Notes",     w = 400, },
      }

-------------------------
--
-- LOADER
--

function _M.loader(sess_path)
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
        observations[#observations + 1] = {
            obs.object or '?', 
            sess_name,
            obs.telescope or '', 
            obs.notes or '',
--            path,
          }
      end
    end
  end
  _log(elapsed("%.3f ms, loaded %d observations from %d sessions",#observations, Nsess))
  return observations
end


return _M

-----
