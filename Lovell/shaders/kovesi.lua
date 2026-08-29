--
-- Kovesi blur
--


local _M = {
    NAME = ...,
    VERSION = "2026.07.01",
    AUTHOR = "AK Booer / Kovesi",
    DESCRIPTION = "Fast (almost-)Gaussian filter [Kovesi 2010]",
  }

require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.07.01  Version 0, @akbooer

--[[

Kovesi blur:

The implementation is about the highest efficiency and quality possible within a fragment-shader. 
It fuses Peter Kovesi's box-convolution theory with native GPU hardware bilinear interpolation.

Kovesi, P., 2010. Fast Almost-Gaussian Filtering. 2010 International Conference on Digital Image Computing: Techniques and Applications (DICTA), pp. 121–125. 

--]]


local KovesiBlur_1D = lg.newShader [[
#pragma language glsl3

uniform float u_stepScale;   
uniform vec2 u_dir;        

vec4 effect(vec4 color, sampler2D tex, vec2 tc, vec2 _) {
    vec2 texelSize = 1.0 / vec2(textureSize(tex, 0));     // 0 is mipmap level
    vec2 offset = texelSize * u_stepScale * u_dir;

    vec3 original = Texel(tex, tc) .rgb;
    vec3 result = vec3(0.0);
    // the 1.5 / 3.5 offset scale uses hardware to interpolate offsets 1 & 2, 3 & 4, respectively, 
    // thereby sampling 9 pixels in just 5 Texel fetches
    // however... take care of the weights for averaging carefully
    result += Texel(tex, tc + (offset * 1.5)) .rgb;
    result += Texel(tex, tc - (offset * 1.5)) .rgb;
    result += Texel(tex, tc + (offset * 3.5)) .rgb;
    result += Texel(tex, tc - (offset * 3.5)) .rgb;
    return vec4((2.0 * result + original) / 9.0, 1.0);
}
]]


--[[

local filterTaps = 9.0 -- Explicit parameter mapping our 1.5 & 3.5 hardware offsets

-- Dynamically scales the exact stride based on BOTH Iterations and physical Filter Taps
function calculate_calibrated_pass_scale(sigma, iterations, filterTaps)
    -- Calculate discrete box variance: (T^2 - 1) / 12
    local singlePassVariance = (filterTaps * filterTaps - 1.0) / 12.0
    
    -- Compound across the cascading loops
    local accumulatedVarianceDenominator = singlePassVariance * iterations
    
    -- Complete the exactPassScale isolation
    local exactPassScale = sigma / math.sqrt(accumulatedVarianceDenominator)
    
    -- Absolute zero safeguard to prevent shader divisions errors
    return math.max(0.01, exactPassScale)
end

--]]


local function almostGaussian(workflow, sigma)
 
 if sigma < 0.05 then return end
 
  -- 1. DYNAMIC ITERATION SCALER GOVERNOR
  -- We scale iterations up for macro layers to keep the step stride tight and safe
  local kovesiIterations = 3
  if sigma > 6.0 then
      kovesiIterations = 5  -- Compress step sizes for medium nebular filaments
  elseif sigma > 12.0 then
      kovesiIterations = 8  -- Compress step sizes heavily for sweeping macro waves
  end
  
  -- 2. CALIBRATED DISTANCE FORMULA
  -- Uses 6.666666 due to our optimized 9-pixel uniform box footprint variance
  -- hard-coded for 9-tap filter... see above:  calculate_calibrated_pass_scale() 
  local exactPassScale = sigma / math.sqrt(6.66666667 * kovesiIterations)
  
  local hor  = {u_stepScale = exactPassScale, u_dir = {1, 0}}
  local vert = {u_stepScale = exactPassScale, u_dir = {0, 1}}
  
  for _ = 1, kovesiIterations do
    workflow: shadeWith(KovesiBlur_1D, hor)
    workflow: shadeWith(KovesiBlur_1D, vert)
  end
  
end


return almostGaussian

-----
