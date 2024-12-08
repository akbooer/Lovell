--
-- poststack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.03",
    AUTHOR = "AK Booer",
    DESCRIPTION = "poststack processing (background, stretch, scnr, ...)",
  }
-- 24.11.06  Version 0
-- 24.12.03  and TNR noise reduction and sharpening


local _log = require "logger" (_M)

local buffer      = require "utils" .buffer
local background  = require "shaders.background"
local stretch     = require "shaders.stretcher"
local filter      = require "shaders.filter"
local colour      = require "shaders.colour"
local stats       = require "shaders.stats"

local smooth = filter.smooth

local lum       -- luminance
local smoothed  -- smoothed image
local final     -- final image

-- toggle input/output workflow between two buffers,
-- matched and initialised to input canvas type
local workflow do    
  local b1, b2
  local controls
  function workflow(canvas, ctrl)
    local special
    if type(canvas) == "table" then
      special = canvas                  -- one-off override of controls
    elseif canvas then                  -- create buffers first time around,,,
      b1  = buffer(canvas, b1)
      b2  = buffer(canvas, b2)
      controls = ctrl
      return canvas, b1, controls   -- ... and use input canvas as first input
    end
    b1, b2 = b2, b1  -- toggle buffer input/output
    return b2, b1, special or controls
  end
end


local function poststack(stackframe, controls)
  
  if not stackframe then return end
  
  local stack = stackframe.image
  lum = buffer(stack, lum, {format = "r16f", dpiscale = 1})    -- single floating-point channel

  -- TODO: pre-compute gradients after stack
  background(workflow(stack, controls))   -- set up workflow buffers and parameters and remove background gradient
--  stats.normalise(workflow())
   
  local bayer = stackframe.bayer
  if bayer and bayer ~= "NONE" then
    
    controls.synth = {1,1,1}    -- synthetic lum, or could be {.7,.2,.1}, etc.
    local mono = colour.synthL(workflow())
    colour.copy(mono, lum)
    workflow()                        -- revert to previous input buffer, for colour
   
    controls.filter = {radius = 4}
    filter.boxblur(workflow())        -- reduce colour noise
    colour.scnr(workflow())   

    stats.normalise(workflow())
    colour.rgb2hsl(workflow())
    colour.hsl2rgb(workflow())        -- apply saturation stretch
    
    colour.balance_R_GB(workflow())
    colour.selector(workflow())         -- select channel for display (LRGB, L, R, G, B)

    colour.lrgb(lum, workflow())      -- create LRBG image
   
  end
  
  -- apply gamma stretch (of various kinds)
  stats.normalise(workflow())
  local gamma = (controls.gammaOptions[controls.gamma] or '?') : lower()
  gamma = stretch[gamma] or stretch.asinh
  local stretched = gamma(workflow())
  final = buffer(stretched, final)
  colour.copy(stretched, final)
  
  -- post-post processing
  local span = 25

  local blur = filter.boxblur(workflow {filter = {radius = span}})
  smoothed = buffer(blur, smoothed)
  colour.copy(blur, smoothed)
 
  filter.tnr(smoothed, final, (workflow()), controls)
  workflow()    -- revert to workflow
  
  filter.apf0(smoothed, workflow())
  
  return (workflow())      -- just return the workflow result
end

return poststack

-----


