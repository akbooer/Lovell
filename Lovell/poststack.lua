--
-- poststack.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.25",
  AUTHOR = "AK Booer",
  DESCRIPTION = "poststack processing (background, stretch, scnr, ...)",
}

-- 2024.11.06  Version 0
-- 2024.12.03  add TNR noise reduction and sharpening

-- 2025.01.25  only remove gradients if defined
-- 2025.01.29  integrate colour and filter methods into workflow 
-- 2025.02.24  added invert() option in workflow
-- 2025.03.24  show insufficient RGB as mono
-- 2025.03.31  fix halos round coloured stars (issue #3)

-- 2026.06.11  access stack object directly, rather than poststack() parameter list
-- 2026.08.04  complete refactor using "synth" plugin
-- 2026.09.25  use plugins.process_sequence() iterator


require "logger" (_M)

local controls  = require "controls"
local stacking  = require "stacking"
local plugins   = require "plugins"


local newTimer = require "utils" .newTimer


-------------------------------
--
-- POSTSTACK
--

local function poststack(workflows)
--  local elapsed = newTimer()
  local workflow = workflows.main
  local wstack = workflows.wstack
  
  local stack = stacking.get()
  if not stack then return end

  -- get LRGB composite image from stack
  
  local b = controls.balance            -- channel gains
  local l = controls.luminance          -- brightness, etc.
  local background = stack.background
  local gradient = 1 + 2 * l.gradient.value    -- gradient strength (slider zero at centre)
  local whitepoint = l.whitepoint.value
  local vignette = l.vignette.value
  local balance = {b.R.value, b.G.value, b.B.value, 1}
  local offset = 1 + 2 * (l.background.value - 0.5)

  local greysky = workflow: plugin ("synth", wstack, background, gradient, balance, offset, whitepoint, vignette)
  
  -- STRETCH
  
  local gamma = controls.gammaOptions
  local selected = gamma: get()
  local stretch = l.stretch.value
  local luminance = gamma.luminance.checked    -- false means RGB mode
  
  workflow: stretch(selected, stretch, luminance, greysky) 

  -- POST-PROCESS

  local name = controls.palette: get()                -- selected chroma workflow name: rgb, sho, ...
  workflow: plugin (name)
  
-- CONFIGURABLE PLUGINS

  for _, plugin in plugins.process_sequence() do
    workflow: plugin(plugin)
  end
  
  workflow: plugin "channel"            -- channel selection and inversion

--_log(elapsed "%.3f ms")

end


return poststack

-----


