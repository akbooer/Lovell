--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.11",
    AUTHOR = "AK Booer",
    DESCRIPTION = "stacks individual subs",
  }

-- 2024.10.21  Version 0
-- 2024.12.16  add separate field rotation BEFORE translation

-- 2025.01.28  rearrange parameters to better integrate into workflow
-- 2025.02.09  use workflow: renderTo()
-- 2025.03.11  combine rotation and translation into one operation
-- 2025.03.25  prototype minimum variance stack
-- 2025.04.01  add RGBL exposure (issue #6)
-- 2025.05.01  add displayname to stack options
-- 2025.05.09  refine minimum variance stack implementation (no free parameters)


local _log = require "logger" (_M)

local matrix    = require "lib.matrix"
local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


_M.stackOptions = {"Average", "Min Variance", "Sigma Clip", selected = 1,
                    displayname = {"average", "min var", "sigma"}}


------------------------
--
-- AVERAGE STACK
--

--[=[

-- this is the straight-forward way with RGB and alpha used as expected

local stacker = lg.newShader [[
    
    uniform float alpha;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords) .rgb;
      return vec4(pixel, alpha);
    }
    
]]

local function average(workflow, stack, depth, _, ...)
  lg.setBlendMode "alpha"
  lg.setShader(stacker)
  stacker: send("alpha", 1 / depth)
  stack: renderTo(lg.draw, workflow.output, ...)
end

--]=]


-- RGBA version, with separate luminance channel stored in A
-- requires read access to existing stack...

local stacker = lg.newShader [[
    
    uniform vec4 rgbl;
    uniform Image stack;
    
    const float eps = 1e-4;
    vec4 alpha = 1.0 / (rgbl + eps);
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 pixel  = Texel(texture, tc);
      vec4 pstack = Texel(stack, tc);
      return mix(pstack, pixel, alpha);
    }
    
]]

local function average(workflow, rgbl, ...)
  
  -- (1) rotate and shift input...
  --      ...image must be aligned BEFORE stacking!
  workflow: clear "input"   -- actually, the next output buffer
  workflow: renderTo(lg.draw, ...)
  
  -- (3) stack shifted image
  lg.setShader(stacker)
  stacker: send("rgbl", rgbl)
  stacker: send("stack", workflow.stack)
  workflow.stack: renderTo(lg.draw, workflow.output)
end

------------------------
--
-- MINIMUM VARIANCE WEIGHTED STACK
--

-- standard deviation
local sigma = lg.newShader [[
    
    uniform Image stack;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 new = Texel(texture, tc);
      vec4 ref = Texel(stack, tc);
      vec4 var = 1000.0 * abs(new - ref);  // use innovation as proxy for sigma, scaled to retain precision for half float
      return var;
    }
    
]]

-- calculate minimum variance weighted stack, input is new sub
local minvar = lg.newShader [[
    
    uniform vec4 rgbl;
    uniform Image stack, stack_variance, sub_variance;
    
    const float eps = 1e-4;
    vec4 alphamax = 1.0 / (rgbl + eps);
   
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 pixel  = Texel(texture, tc);
      vec4 pstack = Texel(stack, tc);
      vec4 vsub   = Texel(sub_variance, tc) ;
      vec4 vstack = Texel(stack_variance, tc);
      
      vec4 alpha = vstack / (vstack + vsub + eps);
 //     alpha = min(alpha, alphamax);
      return mix(pstack, pixel, alpha);

    }
    
]]

-- calculate new stack variance, input is sub variance
local newvar = lg.newShader [[
    
    uniform Image stack_variance;    
     
    const float eps = 1e-4;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 vsub = Texel(texture, tc);
      vec4 vstack = Texel(stack_variance, tc); 
      
      return vsub * vstack / (vstack + vsub + eps);;
    }
    
]]

local function min_variance(workflow, rgbl, ...)
  
  -- (1) rotate and shift input, saving in temp...
  --      ...image must be aligned BEFORE new variance estimate!
  workflow: clear "input"   -- actually, the next output buffer
  workflow: renderTo(lg.draw, ...)
  workflow: save "temp"

  -- (2) calculate sub variance, save in temp1
  lg.setShader(sigma)
  sigma: send("stack", workflow.stack)
  workflow.temp1: renderTo(lg.draw, workflow.output)
  
  -- (3) variance weighted stack of rotated and shifted image in temp
  lg.setShader(minvar)
  minvar: send("rgbl", rgbl)
  minvar: send("stack", workflow.stack)
  minvar: send("stack_variance", workflow.stack_variance)
  minvar: send("sub_variance", workflow.temp1)
  workflow.stack: renderTo(lg.draw, workflow.temp)

  -- (4) update stack variance
  lg.setShader(newvar)
  newvar: send("stack_variance", workflow.stack_variance)
  workflow.output: renderTo(lg.draw, workflow.temp1)    -- temp1 is sub variance
  workflow: gaussian(3)                                 -- spatial average as proxy for temporal average
  workflow: save "stack_variance"
  
--  lg.reset()
--  workflow: stats(true)
end

------------------------
--
-- SIGMA CLIP STACKING
--

local clip = lg.newShader [[
    
    uniform vec4 rgbl;
    uniform Image stack, sub_variance, ref_variance;
    
    const float eps = 1e-4;
    vec4 alpha = 1.0 / (rgbl + eps);
   
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 pixel  = Texel(texture, tc);
      vec4 pstack = Texel(stack, tc);
      vec4 vsub   = Texel(sub_variance, tc) ;
      vec4 vref   = Texel(ref_variance, tc);
      vref = vec4(0.001);
      
      bvec4 ok = lessThan(vsub, 2.0 * vref);
//      vec4 foo = mix(pstack, pixel, ok);   // not available in GLSL 1.1
      pixel.r = ok.r ? pixel.r : 0.0; //pstack.r;
      pixel.g = ok.g ? pixel.g : 0.0; //pstack.g;
      pixel.b = ok.b ? pixel.b : 0.0; //pstack.b;
      pixel.a = ok.a ? pixel.a : 1.0; //pstack.a;
      
      return mix(pstack, pixel, alpha);
    }
    
]]
local function sigma_clip(workflow, rgbl, ...)
  
  -- (1) rotate and shift input, saving in temp...
  --      ...image must be aligned BEFORE new variance estimate!
  workflow: clear "input"   -- actually, the next output buffer
  workflow: renderTo(lg.draw, ...)
  workflow: save "temp"

  -- (2) calculate sub variance, save in temp1
  lg.setShader(sigma)
  sigma: send("stack", workflow.stack)
  workflow: renderTo()
  workflow: save "temp1"
--  workflow: gaussian(3)                                 -- spatial average as proxy for temporal average
  
  -- (3) stack of rotated and shifted image in temp
  lg.setShader(clip)
  clip: send("rgbl", rgbl)
  clip: send("stack", workflow.stack)
  clip: send("ref_variance", workflow.output)
  clip: send("sub_variance", workflow.temp1)
  workflow.stack: renderTo(lg.draw, workflow.temp)
 
end

------------------------
--
-- GENERIC STACKING
--

local t, f = true, false

local rgb_filter = {
          R   = {t,f,f,f}, 
          G   = {f,t,f,f}, 
          B   = {f,f,t,f}, 
          L   = {f,f,f,t},    -- Luminance is stored in alpha channel
          RGB = {t,t,t,f},
        }

local rgb_count = {
          R   = {1,0,0,0}, 
          G   = {0,1,0,0}, 
          B   = {0,0,1,0}, 
          L   = {0,0,0,1}, 
          RGB = {1,1,1,0},
        }

local process = {average, min_variance, sigma_clip}

function _M.stack(workflow, p)
  local elapsed = newTimer()
  
  local controls = workflow.controls
  local sel = controls.stackOptions.selected
  local fct = process[sel] or average
  
  local filter = p.filter:upper()
  local filterChans = rgb_filter[filter] or rgb_filter.RGB
  local countChans  = rgb_count[filter]  or rgb_count.RGB
  
  local theta, xshift, yshift = unpack(p)
  local w, h = workflow: getDimensions()
  local geometry = {w/2 + xshift, h/2 + yshift, theta, 1, 1, w/2, h/2} -- rotate and shift parameters
    
  local RGBL = matrix {workflow.RGBL or {0,0,0,0,  0,0,0,0}}       -- initalise stack counts, and exposures
  RGBL = (RGBL + (matrix {countChans} .. (matrix {countChans} * p.exposure))) [1]
  workflow.RGBL = RGBL
  _log("RGBL exposures (s):", unpack(RGBL))
  
  lg.setBlendMode ("replace", "premultiplied")        -- don't treat alpha channel as normal (it's separate Lum)
  lg.setColorMask(unpack(filterChans))                -- only update relevant channel(s)
  fct(workflow, RGBL, unpack(geometry))
  lg.reset()
  
  local rgbl = "%dR %dG %dB %dL" % RGBL
  _log(elapsed ("%.3f ms, %s %s stack", rgbl, controls.stackOptions[sel]))
end


return _M

-----
