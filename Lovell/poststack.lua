--
-- poststack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "poststack processing (background, stretch, scnr, ...)",
  }
  
-- 2024.11.06  Version 0
-- 2024.12.03  and TNR noise reduction and sharpening

-- 2025.01.25  only remove gradients if defined
-- 2025.01.29  integrate colour and filter methods into workflow 
-- 2025.02.24  added invert() option in workflow


local _log = require "logger" (_M)

local mono = {format = "r16f", dpiscale = 1}    -- Luminance buffer options

local function poststack(frame)
  if not frame then return end
  
  local workflow = frame.workflow
  local controls = workflow.controls

--  local elapsed = require "utils" .newTimer()
  
  -------------------------------
  --
  -- INITIALISE WORKFLOW, and remove gradient
  --
  local R, G, B, L = unpack(workflow.RGBL)
  controls.workflow.RGBL = workflow.RGBL                  -- so that GUI infopanel has access
  local ratio = (R + G + B) / (3 * L + 1e-6)             --  is there a Luminance filter? (avoid zero division)
--  _log("RGB:L ratio %.2f" % ratio)
  workflow: newInput(frame.image)
  workflow: background(frame.gradients, controls.gradient.value) 

  workflow: stats()   -- give CPU something to do
  
  -------------------------------
  --
  -- COLOUR WORKFLOW
  --
   
  local bayer = frame.bayer
  if R > 0 and G > 0 and B > 0 then
    local w = controls.workflow
    workflow: balance {w.Rweight.value, w.Gweight.value, w.Bweight.value}
--    workflow: synthL({1,1,1}, frame.luminance, ratio)                   -- synthetic lum, or could be {.7,.2,.1}, etc.
    workflow: synthL({.7,.2,.1}, workflow.luminance, ratio)          -- synthetic lum, or could be {.7,.2,.1}, etc.
    workflow: save "temp"                       -- fork into a monochrome buffer
    workflow: undo()                            -- revert to previous input buffer
   
    workflow: gaussian(1)                       -- reduce colour noise
    workflow: scnr()                            -- Subtractive Chromatic Noise Reduction
    workflow: normalise()
--    workflow: stretch("ModGamma", 2)
--    workflow: rgb2hsl()
--    workflow: hsl2rgb(controls.saturation.value * 5)                         -- apply saturation stretch
    workflow: satboost(controls.saturation.value * 5)                         -- apply saturation stretch
    workflow: tint()                            -- R / GB balance
    workflow: selector()                        -- select channel for display (LRGB, L, R, G, B)
    workflow: lrgb "temp"                       -- create LRBG image

  else -- mono
    workflow: newInput "luminance"
    workflow: normalise()
  end
  
  -------------------------------
  --
  -- GAMMA STRETCH (of various kinds)
  --
  
  workflow: stretch ()
  
  -------------------------------
  --
  -- POST-POST PROCESSING,  noise reduction / sharpening
  --
  
  workflow: save "temp"
  workflow: gaussian(1)
  workflow: save "temp1"
  workflow: gaussian(2)
  workflow: save "temp2"
  workflow: newInput "temp"
  workflow: tnr "temp2"                             -- noise reduction using temp2 as smoothed background
  workflow: apf("temp1", "temp2")                   -- sharpening. using two background scales
    
  workflow: invert()   -- ...if selected  
  
--  _log(elapsed())
  return workflow.output      -- just return the workflow result
end

return poststack

-----


