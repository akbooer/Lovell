--
-- poststack.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.04.01",
  AUTHOR = "AK Booer",
  DESCRIPTION = "poststack processing (background, stretch, scnr, ...)",
}

-- 2024.11.06  Version 0
-- 2024.12.03  add TNR noise reduction and sharpening

-- 2025.01.25  only remove gradients if defined
-- 2025.01.29  integrate colour and filter methods into workflow 
-- 2025.02.24  added invert() option in workflow
-- 2025.03.24  show insufficient RGB as mono
-- 2025.03.31  fix halos round coloured star (issue #3)
-- 2025.04.01  add RGBL exposure (issue #6)


local zeros = _G.READONLY {0,0,0,0}

local _log = require "logger" (_M)

local function poststack(frame)
  if not frame then return end

  local workflow = frame.workflow
  local controls = workflow.controls
  local RGBL = workflow.RGBL
  if not RGBL then return end

  local w = controls.workflow
  w.RGBL = RGBL                                           -- so that GUI infopanel has access

  local R, G, B, L, Re, Ge, Be, Le = unpack(RGBL)         -- get exposure counts AND times
  if Re + Ge + Be + Le > 0 then                           --  use exposure times if available (issue #6)
      R, G, B, L = Re, Ge, Be, Le            
  end

  local ratio = (R + G + B) / (3 * L + 1e-6)             -- is there a Luminance filter? (avoid zero division)

--  local elapsed = require "utils" .newTimer()

  -------------------------------
  --
  -- INITIALISE WORKFLOW, and remove gradient
  --

  workflow: newInput(frame.image)  
  workflow: background(frame.gradients, controls.gradient.value) 

  -------------------------------
  --
  -- MONO WORKFLOW / SYNTH LUM
  --
  
  workflow: balance {w.Rweight.value, w.Gweight.value, w.Bweight.value}   -- apply RGB balance presets
  workflow: synthL({.7,.2,.1}, workflow.luminance, ratio)                 -- mix synthetic and real lum (if any)

  -------------------------------
  --
  -- COLOUR WORKFLOW
  --  

  if R > 0 and G > 0 and B > 0 then                  -- enough for LRGB
    workflow: save "temp"                             -- save lum
    workflow: undo()                                  -- revert to previous input buffer
    workflow: gaussian(0.5)                           -- reduce colour noise
    workflow: normalise()
--    workflow: stretch("Asinh", 1)
    workflow: scnr()                                  -- Subtractive Chromatic Noise Reduction
    workflow: satboost(controls.saturation.value * 5) -- apply saturation stretch
    workflow: tint(controls.tint.value)               -- R / GB balance
--    workflow: colour_magic()
    workflow: selector(controls.channelOptions)       -- select channel for display (LRGB, L, R, G, B)
    workflow: lrgb "temp"                             -- create LRBG image
  end

  -------------------------------
  --
  -- GAMMA STRETCH (of various kinds)
  --
  
  workflow: stretch ()

  -------------------------------
  --
  -- POST PROCESSING,  noise reduction / sharpening
  --

  workflow: save "temp"                             -- save stretched image
  workflow: gaussian(1)
  workflow: save "temp1"                            -- one level of smoothing...
  workflow: gaussian(2)
  workflow: save "temp2"                            -- ...and another
  workflow: newInput "temp"                         -- restore original image
  workflow: tnr "temp2"                             -- noise reduction using temp2 as smoothed background
  workflow: apf("temp1", "temp2")                   -- sharpening, using two background scales

  workflow: invert(controls.channelOptions)         -- invert, if "Inverted" selected  

--  _log(elapsed())
  return workflow.output                            -- return the workflow result
end

return poststack

-----


