--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.12",
    AUTHOR = "AK Booer",
    DESCRIPTION = "stacks individual subs",
  }

-- 2024.10.21  Version 0
-- 2024.12.16  add separate field rotation BEFORE translation

-- 2025.01.28  rearrange parameters to better integrate into worklfow
-- 2025.02.09  use workflow: renderTo()
-- 2025.03.11  combine rotation and translation into one operation


local _log = require "logger" (_M)

local matrix    = require "lib.matrix"
local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


local stacker = lg.newShader [[
    
    uniform float alpha;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords) .rgb;
      return vec4(pixel, alpha);
    }
    
]]

local t, f = true, false

local rgb_filter = {
          R   = {t,f,f,t}, 
          G   = {f,t,f,t}, 
          B   = {f,f,t,t}, 
          L   = {t,t,t,t},    -- Luminance is stored in all channels, treat like RGB
          RGB = {t,t,t,t},
        }

local rgb_count = {
          R   = {1,0,0,0}, 
          G   = {0,1,0,0}, 
          B   = {0,0,1,0}, 
          L   = {0,0,0,1}, 
          RGB = {1,1,1,0},
        }

local index = {R = 1, G = 2, B = 3, L = 4, RGB = 1 or 2 or 3}   -- RGB has identical R,G,B channel counts!

------------------------
--
-- AVERAGE STACK
--

local function average(workflow, params)
  local p = params
  local filter = p.filter:upper()
  local filterChans = rgb_filter[filter] or rgb_filter.RGB
  local countChans  = rgb_count[filter]  or rgb_count.RGB
  local w, h = workflow.output: getDimensions()
  
  -- determine whether luminance or multi-spectral stack, and update stack count
  local mono = (filter == "L")
  local stack = mono and workflow.luminance or workflow.stack
  local RGBL = matrix {workflow.RGBL or {0, 0, 0, 0}}       -- initalise stack counts
  RGBL = (RGBL + matrix {countChans}) [1]
  workflow.RGBL = RGBL
  local idx = index[filter] or 1
  local depth = RGBL[idx]
  
  lg.setBlendMode "alpha"
  lg.setShader(stacker)
  lg.setColorMask(unpack(filterChans))
  stacker: send("alpha", 1 / depth)
  stack: renderTo(lg.draw, workflow.output, w/2 + p.xshift, h/2 + p.yshift, p.theta, 1, 1, w/2, h/2)
  lg.setColorMask(true, true, true, true)
  lg.setShader()
  
end


------------------------
--
-- MINIMUM VARIANCE WEIGHTED STACK
--
-- variance buffer contains current stack cariance estimate
--
-- image must be aligned BEFORE new variance estimate!
--

-- calculate image variance
local variance = lg.newShader [[
    
    uniform Image stack;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 new = Texel(texture, tc);
      vec4 ref = Texel(stack, tc);
      vec4 diff = new - ref;
      return diff * diff;
    }
    
]]

-- calculate minimum variance weighted stack
local minvar = lg.newShader [[
    
    uniform Image stack, stack_variance, sub_variance;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 pixel = Texel(texture, tc);
      vec4 pstack = Texel(stack, tc);
      vec4 vsub = Texel(sub_variance, tc);
      vec4 vstack = Texel(stack_variance, tc);
      vec4 new = (vstack * pixel + vsub * pstack) / (vstack + vsub);
      
      new = (pixel + pstack) / 2.0;
      new = pixel;
      
      // return new;                  // should eventually use this when chain has been completed
      return vec4(vec3(new), 1.0);    // ignore L channel for the time being
    }
    
]]

-- calculate new stack variance
local newvar = lg.newShader [[
    
    uniform Image stack_variance;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 vsub = Texel(texture, tc);
      vec4 vstack = Texel(stack_variance, tc);
      return vsub * vstack / (vsub + vstack);
    }
    
]]

local function vstacker(workflow, params)
  local p = params
  local filter = p.filter:upper()
  local filterChans = rgb_filter[filter] or rgb_filter.RGB
  local countChans  = rgb_count[filter]  or rgb_count.RGB
  local w, h = workflow.output: getDimensions()
  
  -- determine whether luminance or multi-spectral stack, and update stack count
  local mono = (filter == "L")
  local stack = mono and workflow.luminance or workflow.stack
  local RGBL = matrix {workflow.RGBL or {0, 0, 0, 0}}       -- initalise stack counts
  RGBL = (RGBL + matrix {countChans}) [1]
  workflow.RGBL = RGBL
  local idx = index[filter] or 1
  local depth = RGBL[idx]
  
  --(0) ignore alpha channel for all these shaders which operate on RGBL pixels (Alpha channel replaced by Luminance)
  lg.setColorMask(unpack(filterChans))                -- only update relevant channels
  lg.setBlendMode ("replace", "premultiplied")
  
  -- (1) rotate and shift input, saving in temp
  workflow: renderTo(lg.draw, w/2 + p.xshift, h/2 + p.yshift, p.theta, 1, 1, w/2, h/2)
  workflow: save "temp"

  -- (2) calculate new image variance, save in temp1 (and output)
  lg.setShader(variance)
  variance: send("stack", stack)
  workflow: renderTo(lg.draw)
  workflow: save "temp1"
 
  -- (3) variance weighted stack of rotated and shifted image in temp
  lg.setShader(minvar)
  minvar: send("stack", stack)
  minvar: send("stack_variance", workflow.variance)
  minvar: send("sub_variance", workflow.temp1)
  workflow: newInput "temp"
  workflow: renderTo(lg.draw)
  workflow: save "stack"

  -- (4) update stack variance
  lg.setShader(newvar)
  newvar: send("stack_variance", workflow.variance)
  workflow: newInput "temp1"
  workflow: renderTo(lg.draw)
  workflow: save "variance"
  
  -- (5) reset graphics defaults
  lg.reset()
  
end


local function stack(workflow, params)
  local elapsed = newTimer()
  local fct = params.minVar and vstacker or average
  fct(workflow, params)
  local rgbl = "%dR %dG %dB %dL" % workflow.RGBL
  _log(elapsed ("%.3f ms, %s %s stack", rgbl, fct == average and "average" or "minimum variance"))
end

return stack

-----
