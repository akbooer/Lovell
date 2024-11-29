--
-- poststack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.09",
    AUTHOR = "AK Booer",
    DESCRIPTION = "poststack processing (background, stretch, scnr, ...)",
  }
-- 24.11.06  Version 0

local _log = require "logger" (_M)

local buffer      = require "utils" .buffer
local background  = require "shaders.background"
local stretch     = require "shaders.stretcher"
local smooth      = require "shaders.smoother"
local colour      = require "shaders.colour"
local stats       = require "shaders.stats"

local b1     -- general rgb buffer
local b2 
local lum     -- luminance

local final   -- final image

-- toggle input/output workflow between two buffers,
-- matched and initialised to input canvas type
local workflow do    
  local b1, b2
  local controls
  function workflow(canvas, ctrl)
    if canvas then                  -- create buffers first time around,,,
      b1  = buffer(canvas, b1)
      b2  = buffer(canvas, b2)
      controls = ctrl
      return canvas, b1, controls   -- ... and use input canvas as first input
    end
    b1, b2 = b2, b1  -- toggle buffer input/output
    return b2, b1, controls
  end
end

local function poststack(stackframe, controls)
  
  if not stackframe then return end
  
  local stack = stackframe.image
  lum = buffer(stack, lum, {format = "r16f", dpiscale = 1})    -- single floating-point channel

  background(workflow(stack, controls))   -- set up workflow buffers and parameters and remove background gradient
--  stats.normalise(workflow())
   
  local bayer = stackframe.bayer
  if bayer and bayer ~= "NONE" then
    
--    colour.synthL(b1, lum, {1,1,1})    -- synthetic lum, or could be {.7,.2,.1}, etc.
    colour.scnr(workflow())    
    colour.rgb2hsl(workflow())
    colour.hsl2rgb(workflow())
    
--    smooth(workflow())

--    colour.lrgb(lum, workflow())    -- create LRBG image
   
    colour.balance_R_GB(workflow())
  end
  
  do  -- select channel for display (LRGB, L, R, G, B)
    colour.selector(workflow())
  end

  do -- apply gamma stretch (of various kinds)
    local gamma = (controls.gammaOptions[controls.gamma] or '?') : lower()
    gamma = stretch[gamma] or stretch.asinh
    gamma(workflow())
  end
  
 return (workflow())      -- just return the workflow result
end

return poststack

-----


