--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.26",
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
-- 2025.11.23  add HSO filters to stacker tables (issue #16)

-- 2026.05.03  calculate enough_RGB and (corrected) Lratio here, rather than poststack
-- 2026.06.03  use vector library, not matrix
-- 2026.06.11  move RGBL calculations to stack module...
-- 2026.07.15  ...but add RGBL parameter to revert to unity scaling for stack
-- 2026.07.26  use mipmap canvas as temporary stack and average calculator
-- 2026.08.07  use new internal stack workflow (wstack)


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics


_M.stackOptions = {
    "Average", "Min Variance", "-Sigma Clip", 
    selected = 1,
    default = 1,
    id = "Mode: ",    -- for Menu widget
    displayname = {"average", "min var", "sigma"}
  }


------------------------
--
-- ALIGN -= rotate and shift image prior to stacking
--

function _M.align(workflow, geometry)  
  local theta, xshift, yshift = unpack(geometry)
  local w, h = workflow: getDimensions()  
  lg.setBlendMode ("replace", "premultiplied")        -- don't treat alpha channel as normal (it's separate Lum)
  workflow: clear "input"                                                           -- actually, the next output buffer
  workflow: renderTo(lg.draw, w/2 + xshift, h/2 + yshift, theta, 1, 1, w/2, h/2)    -- rotate and shift parameters
end

------------------------
--
-- AVERAGE STACK
--

-- RGBA version, with separate luminance channel stored in A
-- MainTex is existing stack
local stacker = lg.newShader [[
    
    uniform vec4 rgbl;
    uniform Image sub;
    
    const float eps = 1e-4;
    vec4 alpha = 1.0 / (rgbl + eps);
    
    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec4 pixel  = Texel(sub, tc);
      vec4 pstack = Texel(tex, tc);
      return mix(pstack, pixel, alpha);
    }
    
]]

local function average(wstack, workflow, rgbl, ...)
  wstack: shadeWith(stacker, {sub = workflow.output, rgbl = rgbl})
end

------------------------
--
-- MINIMUM VARIANCE WEIGHTED STACK
--

-- standard deviation
-- MainTex is new sub
local sigma = lg.newShader [[
    
    uniform Image stack;
    
    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec4 new = Texel(tex, tc);
      vec4 ref = Texel(stack, tc);
      
      return abs(new - ref);  // use innovation as proxy for sigma
    }
 
]]

-- calculate minimum variance weighted stack, 
-- MainTex is existing stack
local minvar = lg.newShader [[

    uniform vec4 rgbl;
    uniform Image sub, stack_sigma, sub_sigma;
    
    const float eps = 1e-5;
    vec4 alphamax = 1.0 / (rgbl + eps);
   
    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec4 pixel  = Texel(sub, tc);
      vec4 pstack = Texel(tex, tc);
      vec4 ssub = Texel(sub_sigma, tc);   
      vec4 sstack = Texel(stack_sigma, tc);
      
      // convert sigma to variance
      vec4 vsub = ssub;               // * ssub;   
      vec4 vstack = sstack;           // * sstack;
      
      vec4 alpha = vstack / (vstack + vsub + eps);
      alpha = min(alpha, alphamax);
      
      return mix(pstack, pixel, alpha);

    }
    
]]

-- calculate new stack sigma, 
-- MainTex is sub sigma
local newsigma = lg.newShader [[
    
    uniform Image stack_sigma;    
     
    const float eps = 1e-5;
    
    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec4 ssub = Texel(tex, tc);
      vec4 sstack = Texel(stack_sigma, tc); 
     
      // convert sigma to variance
      vec4 vsub = ssub;               // * ssub;   
      vec4 vstack = sstack;           // * sstack;
      
      vstack = vsub * vstack / (vstack + vsub + eps);
      
 //     return sqrt(vstack);
      return vstack;
    }
    
]]

-- sigma, not variance, is stored to retain dynamic range in fixed 16-bit format,
-- at the cost of a little extra maths in the shaders.
-- input star image has already been aligned (rotated and translated)
local function min_variance(wstack, workflow, rgbl)
  -- (0) allocate temporary buffer names
  local stars = "temp"
  local sstack = "stack_sigma"
  
  -- (1) save pre-aligned star image...
  workflow: save(stars)

  -- (2) calculate sub sigma
  workflow: shadeWith(sigma, {stack = wstack.output}) 
  
  -- (3) variance weighted stack
  wstack: shadeWith(minvar, {
      rgbl = rgbl,
      sub = workflow[stars], 
      stack_sigma = workflow[sstack],  
      sub_sigma = workflow.output})

  -- (4) update stack variance
  workflow: shadeWith(newsigma, {stack_sigma = workflow[sstack]})
  workflow: gaussian(3)         -- spatial average as proxy for temporal average (or use bilteral?)
  workflow: save "stack_sigma"
  
end

------------------------
--
-- SIGMA CLIP STACKING
--

-- MainTex is existing stack
local clip = lg.newShader [[
   #pragma language glsl3
   
    uniform vec4 rgbl;
    uniform Image ref_sigma, sub_sigma, stars;
    
    const float eps = 1e-5;
    vec4 alpha = 1.0 / (rgbl + eps);
   
    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec4 pstack = Texel(tex, tc);
      vec4 pixel  = Texel(stars, tc);
      vec4 vsub   = Texel(sub_sigma, tc) ;
      vec4 vref   = Texel(ref_sigma, tc);
      
      bvec4 ok = lessThan(vsub, 2.0 * vref);
      pixel = mix(pstack, pixel, vsub / vref);   // not available in GLSL 1.1

      return mix(pstack, pixel, alpha);
    }
    
]]

local function sigma_clip(wstack, workflow, rgbl)
  -- (0) allocate temporary buffer names
  local stars = "temp"
  local ssub = "temp1"
  
  -- (1) save pre-aligned star image...
  workflow: save(stars)

  -- (2) calculate sub variance  
  workflow: shadeWith(sigma, {stack = wstack.output}) 
  workflow: save(ssub)
  workflow: gaussian(3)               -- spatial average as proxy for temporal average (or use bilteral?)
  
  -- (3) stack using sigma clip
  wstack: shadeWith(clip, {
      rgbl = rgbl,
      ref_sigma = workflow.output,           -- smoothed local variance
      sub_sigma = workflow[ssub],
      stars = workflow[stars]})
end


------------------------
--
-- GENERIC STACKING - input frame has already been aligned
--

local process = {average, min_variance, sigma_clip}


function _M.stack(wstack, workflow, filterChans, RGBL)
  local sel = _M.stackOptions.selected
  local stack = process[sel] or average
  
  lg.setBlendMode ("replace", "premultiplied")        -- don't treat alpha channel as normal (it's separate Lum)
  lg.setColorMask(unpack(filterChans))                -- only update relevant channel(s)
  stack(wstack, workflow, RGBL)
  lg.reset()
end


return _M

-----
