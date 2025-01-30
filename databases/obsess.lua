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
-- 2025.01.20  separate tile line


local _log = require "logger" (_M)

local csv = require "databases.csv"
local newTimer = require "utils" .newTimer

local json = _G.json

local love = _G.love
local lf = love.filesystem

-----

local Nsess = 0

local observations = {
      titles = {"Object", "Session", "Telescope", "Notes"}  -- , "Path"}
    }

-------------------------
--
-- LOADER
--

function _M.loader(sess_path)
  local elapsed = newTimer()
  local sessions = lf.getDirectoryItems(sess_path)
  for _, filename in ipairs(sessions) do
    local sess_name = filename: match "(%d+)%.json$"
    if sess_name then
      local session = json.read (sess_path .. filename)
--      _log("session", filename)
      Nsess  =Nsess + 1
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
