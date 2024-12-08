--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.01",
    AUTHOR = "AK Booer",
    DESCRIPTION = "stacks individual subs",
  }

-- 2024.10.21  Version 0

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


local stacker = lg.newShader [[
    // Pixel Shader
   
    uniform float alpha;
    uniform vec3 rgb_filter;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords ) .rgb;
      return vec4(rgb_filter * pixel, alpha);
    }
]]

local rgb_filter = {R = {1,0,0}, G = {0,1,0}, B = {0,0,1}, L = {1,1,1}}

function _M.stack(input, output, params)
  local p = params
  local elapsed = newTimer()
  
  local filter = rgb_filter[p.filter: upper()] or rgb_filter.L
  
  lg.setShader(stacker)
  stacker: send("rgb_filter", filter)  
  stacker: send("alpha", 1 / p.depth)
  lg.setBlendMode "alpha"
  output: renderTo(lg.draw, input, p.xshift, p.yshift, p.theta)
  lg.setShader()
 
  _log(elapsed "%.2f ms")
  
  return output
end

-----

return _M

-----
