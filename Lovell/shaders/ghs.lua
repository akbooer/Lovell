--
-- ghs.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.08.04",
  AUTHOR = "AK Booer",
  DESCRIPTION = "Generalised Hyperbolic Stretch)",
}

-- 2026.08.14  initial utilities


require "logger" (_M)



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

