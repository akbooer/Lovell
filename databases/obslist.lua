--
-- obslist.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "observing watch list manager",
  }

-- 2025.01.21  Version 0


local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local json = _G.json

local love = _G.love
local lf = love.filesystem

-------------------------
--
-- LOADER
--


return _M

-----
