--
-- settings.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    DESCRIPTION = "settings database",
  }


-- 2025.02.19  Version 0


local _log = require "logger" (_M)

--local session = require "session"
local json    = require "lib.json"

--local controls = session.controls

local love = _G.love
local lf = love.filesystem

local fname = "settings.json"

-------------------------------
--
-- SETTINGS database
--

function _M.load(controls)
  _log "loading"
  local s = controls.settings
  local f = json.read(fname) or controls.settings   -- use defaults if file read fails
  for n,v in pairs(f) do
    s[n] = v
  end
end

function _M.save(controls)
  _log "saving"
  json.write(fname, controls.settings)
end

return _M

-----

