--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.02",
    AUTHOR = "AK Booer",
    DESCRIPTION = "stacks individual subs",
  }

-- 2024.10.21  Version 0
-- 2024.12.16  add separate field rotation BEFORE translation

-- 2025.01.28  rearrange parameters to better integrate into worklfow
-- 2025.02.09  use workflow: renderTo()
-- 2025.03.11  combine rotation and translation into one operation
-- 2025.03.25  prototype minimum variance stack
-- 2025.04.01  add RGBL exposure (issue #6)


local _log = require "logger" (_M)

local matrix    = require "lib.matrix"
local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics

--_M.stackOptions = {"Average", "Sigma Clipping", "Min Variance", selected = 1}
_M.stackOptions = {"Average", "Sigma Clipping", "Min Variance", selected = 1}


local stacker = lg.newShader [[
    
    uniform float alpha;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords) .rgb;
      return vec4(pixel, alpha);
    }
    
]]

------------------------
--
-- AVERAGE STACK
--

local function average(workflow, stack, depth, _, ...)
  lg.setBlendMode "alpha"
  lg.setShader(stacker)
  stacker: send("alpha", 1 / depth)
  stack: renderTo(lg.draw, workflow.output, ...)
end

------------------------
--
-- MINIMUM VARIANCE WEIGHTED STACK
--
-- variance buffer contains current stack covariance estimate
--

local variance = lg.newShader [[
    
    uniform Image stack;
    uniform vec4 channels;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec3 new = Texel(texture, tc) .rgb;
      vec3 ref = Texel(stack, tc) .rgb;
      vec3 foo =  vec3(channels);
      vec3 diff = 10.0 * abs(new - ref);  // scale to avoid underflow
      float var = dot(diff, foo);
      return vec4(vec3(var), 1.0);
    }
    
]]

--local variance = lg.newShader [[
    
--    uniform Image stack;
--    uniform vec4 channels;
    
--    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
--      vec4 new = Texel(texture, tc);
--      vec4 ref = Texel(stack, tc);
--      vec4 foo =  channels;
--      vec4 diff = 10.0 * abs(new - ref);  // scale to avoid underflow
--      return diff;
--    }
    
--]]

-- calculate minimum variance weighted stack, input is new sub
local minvar = lg.newShader [[
    
    uniform Image stack, stack_variance, sub_variance;
    
    uniform float min_variance;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec3 pixel = Texel(texture, tc) .rgb;
      vec3 pstack = Texel(stack, tc) .rgb;
      float vsub = Texel(sub_variance, tc) .r ;
      vsub = max(min_variance, vsub);
      float vstack = Texel(stack_variance, tc) .r;
      vec3 new = (vstack * pixel + vsub * pstack) / (vstack + vsub);
      return vec4(new, 1.0);    // ignore L channel for the time being
    }
    
]]

-- calculate new stack variance, input is sub variance
local newvar = lg.newShader [[
    
    uniform Image stack_variance;
    
    const float eps = 1e-4;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      float vsub = Texel(texture, tc) .r;
      float vstack = Texel(stack_variance, tc) .r;
      float var = vsub * vstack / (vsub + vstack + eps);
      return vec4(vec3(var), 1.0);
    }
    
]]


local function min_variance(workflow, stack, _, channels, ...)
  
  --(0) ignore alpha channel for all these shaders which operate on RGBL pixels (Alpha channel replaced by Luminance)
  lg.setBlendMode ("replace", "premultiplied")
  workflow: clear "input"   -- actually, the next output buffer
  
  -- (1) rotate and shift input, saving in temp...
  --      ...image must be aligned BEFORE new variance estimate!
  workflow: renderTo(lg.draw, ...)
  workflow: save "temp"

--  -- (2) calculate sub variance, save in temp1 (and output)
  lg.setShader(variance)
  variance: send("stack", stack)
  variance: send("channels", channels)
  workflow: renderTo(lg.draw)
  workflow: save "temp1"
  
--  _log "MINIMUM VARIANCE"
--  workflow: stats(true) 
  
  -- (3) variance weighted stack of rotated and shifted image in temp
  lg.setShader(minvar)
  lg.setBlendMode ("replace", "premultiplied")
  minvar: send("stack", stack)
  minvar: send("stack_variance", workflow.stack_variance)
  minvar: send("sub_variance", workflow.temp1)
  minvar: send("min_variance", 1);
  stack: renderTo(lg.draw, workflow.temp)

  -- (4) update stack variance
  lg.setShader(newvar)
  lg.setBlendMode ("replace", "premultiplied")
  newvar: send("stack_variance", workflow.stack_variance)
  workflow.stack_variance: renderTo(lg.draw, workflow.temp1)    -- temp1 is sub variance
  
--  workflow: copy("stack_variance", "output")
--  _log "Stack variance"
--  workflow: stats(true) 
   
end


------------------------
--
-- SIGMA STACK
--

local sigma = lg.newShader [[
    
    uniform Image stack, sub_variance;
    
    uniform float alpha, min_variance;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec3 pixel = Texel(texture, tc) .rgb;
      vec3 pstack = Texel(stack, tc) .rgb;
      float vsub = Texel(sub_variance, tc) .r ;
      vsub = min(vsub, min_variance);
      float beta = alpha * 1.0 / (1.0 + pow(vsub, 4.0));
      vec3 new = (beta * pixel + (1.0 - beta) * pstack) ;
      return vec4(new, 1.0);    // ignore L channel for the time being
    }
    
]]

local function sigma_clip(workflow, stack, depth, channels, ...)
  
  --(0) ignore alpha channel for all these shaders which operate on RGBL pixels (Alpha channel replaced by Luminance)
  lg.setBlendMode ("replace", "premultiplied")
  workflow: clear "input"   -- actually, the next output buffer
  
  -- (1) rotate and shift input, saving in temp...
  --      ...image must be aligned BEFORE new variance estimate!
  workflow: renderTo(lg.draw, ...)
  workflow: save "temp"
  
--  -- (2) calculate sub variance
  lg.setShader(variance)
  variance: send("stack", stack)
  variance: send("channels", channels)
--  workflow: renderTo(lg.draw)
--  workflow: save "temp1"
  
--  _log "SIGMA CLIP"
--  workflow: stats(true) 
  
  -- (3) sigma-clipped stack of rotated and shifted image in temp
  lg.setShader(sigma)
  lg.setBlendMode ("replace", "premultiplied")
  sigma: send("stack", stack)
--  Ssigma: send("sub_variance", workflow.output)
  sigma: send("min_variance", 0);
  sigma: send("alpha", 1 / depth)
  stack: renderTo(lg.draw, workflow.temp)
   
end


------------------------
--
-- GENERIC STACKING
--


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

local process = {average, sigma_clip, min_variance}

function _M.stack(workflow, params)
  local elapsed = newTimer()
  
  local p = params
  local controls = workflow.controls
  local theta, xshift, yshift = unpack(p)
  local filter = p.filter:upper()
  local filterChans = rgb_filter[filter] or rgb_filter.RGB
  local countChans  = rgb_count[filter]  or rgb_count.RGB
  local w, h = workflow: getDimensions()
  
  -- determine whether luminance or multi-spectral stack, and update stack count and exposures
  local mono = (filter == "L")
  local stack = mono and workflow.luminance or workflow.stack
  
  local RGBL = matrix {workflow.RGBL or {0,0,0,0,  0,0,0,0}}       -- initalise stack counts, and exposures
  RGBL = (RGBL + (matrix {countChans} .. (matrix {countChans} * p.exposure))) [1]
  workflow.RGBL = RGBL
  local idx = index[filter] or 1
  local depth = RGBL[idx]
  
  _log("RGBL exposures (s):", unpack(RGBL))
  local x, y, r, sx, sy, ox, oy = w/2 + xshift, h/2 + yshift, theta, 1, 1, w/2, h/2 -- rotate and shift parameters
  
  lg.setColorMask(unpack(filterChans))                -- only update relevant channels
  local sel = controls.stackOptions.selected
  local fct = process[sel] or average
  fct(workflow, stack, depth, countChans, x, y, r, sx, sy, ox, oy)
  lg.reset()
  
  local rgbl = "%dR %dG %dB %dL" % workflow.RGBL
  _log(elapsed ("%.3f ms, %s %s stack", rgbl, controls.stackOptions[sel]))
end


return _M

-----
