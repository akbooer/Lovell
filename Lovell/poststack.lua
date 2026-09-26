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



local function asinh(x) return math.log(x + math.sqrt(x^2 + 1)) end


--- Computes the post-arcsinh background position and GHS parameters analytically
--- @param b_lin number: Raw linear modal sky peak (e.g., from initial moment stats)
--- @param x0_lin number: Raw linear black point offset
--- @param beta number: Arcsinh stretch factor used in pass 1
--- @return number ghs_b: The calculated symmetry point for GHS pass 2
local function calculateSecondaryGHS(b_lin, x0_lin, beta)
    -- Guard against division by negative or invalid inputs
    local effective_b = math.max(0.0, b_lin - x0_lin)
    local effective_range = math.max(1e-6, 1.0 - x0_lin)
    
    -- 1. Analytically project the linear mode through the normalized asinh function
    local norm_denom = asinh(beta * effective_range)
    local b_post = asinh(beta * effective_b) / norm_denom
    
    -- 2. Place GHS symmetry point (b) slightly above the transformed sky peak 
    -- to maximize contrast derivative right where faint structure emerges
    local offset = 0.01
    local ghs_b = math.min(1.0, b_post + offset)
    
    return ghs_b
end

--[[
-- --- Example Usage  ---
local b_lin = 0.005        -- Linear modal sky peak
local x0_lin = 0.001       -- Linear black point
local beta = 1000.0        -- Pass 1 asinh aggressiveness

local ghs_b = calculateSecondaryGHS(b_lin, x0_lin, beta)
local ghs_D = 4.0          -- Moderate secondary stretch factor
local ghs_bp = 2.0         -- Local intensity focus parameter

-- Send uniforms straight to your combined or secondary GLSL shader
ghsShader:send("u_ghs_b", ghs_b)
ghsShader:send("u_ghs_D", ghs_D)
ghsShader:send("u_ghs_bp", ghs_bp)
--]]


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
  
  local selected = controls.gammaOptions: get()
  local stretch = l.stretch.value
  
  workflow: stretch(selected, stretch, greysky) 

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


