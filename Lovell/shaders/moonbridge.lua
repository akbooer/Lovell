--
-- moonbridge.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.08.28",
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

-- 2025.05.06  use setBlendMode("replace", "premultiplied")

-- 2026.06.28  update workflow calls to follow latest changes


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- apply the shader
-- buffer is a function which toggles between a pair of buffers, returning both

local proxy = {
  
    draw_shader = function(workflow, shader)
      lg.setShader(shader)
      local r,g,b,a = lg.getColorMask()
      lg.setColorMask(true, true, true, true)
      lg.setBlendMode("replace", "premultiplied")
      workflow: renderTo()
      lg.setBlendMode "alpha"
      lg.setColorMask(r,g,b,a)
      lg.setShader()
    end,
      
    Effect = function(info)
      return info
    end,
  }

  
local function moonbridge(shaderName)
  local moonshader = require ("moonshine." .. shaderName) (proxy)

  local moondraw = moonshader.draw        -- the Moonshader's own draw() function
  moonshader.draw = nil
  
  moonshader.filter = function(workflow)    -- replacement method
    -- Moonshine buffer order is (output, input) rather than (input, output)
    workflow: swap ("input", "output")         -- swap buffers...
    moondraw(workflow)  
    workflow: swap ("input", "output")         -- ...and back again
  end      
  
  return moonshader
end


return moonbridge

-----
