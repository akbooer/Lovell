--
-- poststack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.16",
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
local moonbridge  = require "shaders.moonbridge"   -- Moonshine proxy
local newTimer    = require "utils" .newTimer 

local gaussian  = moonbridge "fastgaussianblur" 
local gaussianWide  = moonbridge "fastgaussianblur" 
local gaussianVeryWide  = moonbridge "fastgaussianblur" 

gaussian.setters.taps(5)            -- narrow Gaussian
gaussianWide.setters.taps(17)       -- wider one
--gaussianVeryWide.setters.taps(19)   -- even wider one

local lum             -- luminance
local smoothed        -- smoothed image
local verysmoothed   -- smoothed image
local final           -- final image


local function poststack(stackframe, controls)
  if not stackframe then return end
  
  local stack = stackframe.image
  local workflow = stackframe.workflow
  
  lum = buffer(stack, lum, {format = "r16f", dpiscale = 1}, "luminance")    -- single floating-point channel

  -- reset workflow buffers with latest stack, and remove gradients
  background.remove (stackframe.gradients, workflow(stack))   
--  stats.normalise(workflow())
   
  local bayer = stackframe.bayer
  if bayer and bayer ~= "NONE" then
--    local elapsed = newTimer()
    controls.synth = {1,1,1}    -- synthetic lum, or could be {.7,.2,.1}, etc.
    colour.synthL(workflow)
    workflow.saveOutput(lum)    -- fork into a monochrome buffer
    workflow()                  -- revert to previous input buffer
   
--    controls.filter = {radius = 4}
    
    filter.smooth(workflow)
--    gaussian.filter(workflow)        -- reduce colour noise
    colour.scnr(workflow)   

    stats.normalise(workflow)
    colour.rgb2hsl(workflow)
    colour.hsl2rgb(workflow)        -- apply saturation stretch
    
    colour.balance_R_GB(workflow)
    colour.selector(workflow)         -- select channel for display (LRGB, L, R, G, B)

    colour.lrgb(lum, workflow)      -- create LRBG image
--    _log(elapsed "%.3f ms, synthL, colour smooth, rgb/hsl")
  end
  
  -- apply gamma stretch (of various kinds)
  stats.normalise(workflow)
--  local elapsed = newTimer()
  local gamma = (controls.gammaOptions[controls.gamma] or '?') : lower()
  gamma = stretch[gamma] or stretch.asinh
  gamma(workflow())
  final = workflow.saveOutput(final)
  
  -- post-post processing, noise reduction / sharpening

  gaussianWide.filter(workflow)
  smoothed = workflow.saveOutput(smoothed)
  
  filter.tnr(smoothed, workflow(final))     -- noise reduction

  filter.apf(smoothed, workflow)            -- sharpening
    
--  _log(elapsed "%.3f ms, stretch, gaussian smooth, noise reduction, sharpen")
  
  return workflow.output      -- just return the workflow result
end

return poststack

-----


