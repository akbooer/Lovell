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

  -------------------------------
  --
  -- INITIALISE WORKFLOW, and remove gradient
  --
  
  workflow: newInput(frame.image)
  workflow: background(frame.gradients) 

  -------------------------------
  --
  -- COLOUR WORKFLOW
  --
   
  local bayer = frame.bayer
  if bayer and bayer ~= "NONE" then
    local w = controls.workflow
    workflow: balance {w.Rweight.value, w.Gweight.value, w.Bweight.value}
    
    workflow: synthL {1,1,1}                    -- synthetic lum, or could be {.7,.2,.1}, etc.
    workflow: saveOutput ("mono", mono)         -- fork into a monochrome buffer
    workflow: undo()                            -- revert to previous input buffer
   
    workflow: gaussian(1)                       -- reduce colour noise
    workflow: scnr()                            -- Subtractive Chromatic Noise Reduction

    workflow: normalise()
    workflow: rgb2hsl()
    workflow: hsl2rgb()                         -- apply saturation stretch
    workflow: tint()                            -- R / GB balance
    workflow: selector()                        -- select channel for display (LRGB, L, R, G, B)
    workflow: lrgb (workflow.mono)              -- create LRBG image

  end
  
  -------------------------------
  --
  -- GAMMA STRETCH (of various kinds)
  --
  
  workflow: normalise()
  workflow: stretch ()
  
  -------------------------------
  --
  -- POST-POST PROCESSING,  noise reduction / sharpening
  --
  
  workflow: saveOutput "final"
  workflow: gaussian(1)
  workflow: saveOutput "smoothedabit"
  workflow: gaussian(2)
  workflow: saveOutput "smoothed"
  workflow: newInput (workflow.final)
  workflow: tnr(workflow.smoothed)                              -- noise reduction
  workflow: apf(workflow.smoothedabit, workflow.smoothed)       -- sharpening
    
  workflow: invert()   -- ...if selected  
  
  return workflow.output      -- just return the workflow result
end

return poststack

-----


