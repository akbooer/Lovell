--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.16",
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

local rotator = lg.newShader [[
    // Pixel Shader
   
     
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return pixel;
    }
]]

local rgb_filter = {R = {1,0,0}, G = {0,1,0}, B = {0,0,1}, L = {1,1,1}}

local function renderToWorkflow(workflow, ...)
  local input, output = workflow()
  output: renderTo(lg.draw, input, ...)
end

function _M.stack(stackframe, params)
  local stack = stackframe.image
  local workflow = stackframe.workflow
  local p = params
  local elapsed = newTimer()
  
--  lg.setColor(1,1,1)
  lg.setShader(rotator)
--  lg.setBlendMode("alpha", "premultiplied")
--  renderToWorkflow(workflow, 0, 0, -p.theta)                           -- rotation FIRST...

  lg.setShader(stacker)                   -- merge with previous stack
  local filter = rgb_filter[p.filter: upper()] or rgb_filter.L
  stacker: send("rgb_filter", filter)  
  stacker: send("alpha", 1 / p.depth)
  lg.setBlendMode "alpha"
  stack: renderTo(lg.draw, workflow.output, p.xshift, p.yshift)       -- ...THEN translation
  lg.setShader()
 
  _log(elapsed "%.2f ms")
  
end

-----

return _M

-----
