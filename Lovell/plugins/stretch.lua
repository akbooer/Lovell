--
-- stretch.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.04",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Types of stretch",
  }

require "logger" (_M)

-- 2026.10.04  Version 0

local gammaOptions = require "shaders.stretcher" .gammaOptions

local love = _G.love
local lg = love.graphics


local plugin = {
    id = "Stretch",
    static = true,
    lum_only = {checked = false, default = false, text = "lum only", },
}


-- RUN and DRAW methods


function plugin: run()
  -- required, but does nothing
end

 
function plugin: draw(suit)  
  
end


return plugin

-----

