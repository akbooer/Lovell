--
-- moonbridge.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.09",
    AUTHOR = "AK Booer",
    DESCRIPTION = "proxy wrapper for Moonshine shaders",
  }

--[[

  Proxy for the Moonshine environment (by the incomparable Matthias Richter <vrld@vrld.org>)
  
  Just the basics:
    Effect {table with name, draw, setters, and defaults fields}
    draw_shader(buffer, shader)
    
  Usage:
    
    local boxblur = moonbridge "boxblur"           -- name of Moonshine shader
    
    boxblur.setters.radius(11)
    boxblur.draw(workflow)
    
--]]

-- 2024.12.09  Version 0


local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local love = _G.love
local lg = love.graphics

-- apply the shader
-- buffer is a function which toggles between a pair of buffers, returning both

local proxy = {
  
    draw_shader = function(buffer, shader)
      local front, back = buffer()
      lg.setShader(shader)
      front: renderTo(lg.draw, back)
      lg.setShader()
    end,
      
    Effect = function(info)
      return info
    end,
  }

  
local function moonbridge(shaderName)
--  _log("loading Moonshine shader " .. shaderName)
  local moonshader = require ("moonshine." .. shaderName) (proxy)

  local moondraw = moonshader.draw        -- the Moonshader's own draw() function
  moonshader.draw = nil
  
  moonshader.filter = function(workflow)    -- replacement method
    local elapsed = newTimer()
    -- Moonshine buffer order is (output, input) rather than (input, output)
    workflow()          -- swap buffers...
    moondraw(workflow)  
--    _log (elapsed("%.3f ms" .. shaderName))
    workflow()          -- ...and back again
  end      
  
  return moonshader
end


return moonbridge

-----
