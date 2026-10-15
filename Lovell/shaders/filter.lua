--
-- filter – 
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry processing filters (BOX, TNR, APF, ...)",
  }

local _log = require "logger" (_M)

local moonbridge  = require "shaders.moonbridge"   -- Moonshine proxy

-- 2024.11.07  Version 0, @akbooer
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.29  incorporate moonshine bridge shaders
-- 2025.03.21  use named buffers (possibly) in tnr() and apf()
-- 2025.05.14  consolidate apf() for different numbers of backgrounds into one single code


local love = _G.love
local lg = love.graphics


-------------------------------
--
-- GAUSSIAN
--
local Gauss = lg.newShader [[
#pragma language glsl3

#define MAX_RADIUS 64

// The precomputed weights from center out to radius (e.g. weight[0] is center)
uniform float weights[MAX_RADIUS]; 
uniform int radius; // 3 * sigma, passed from Lua
uniform vec2 direction; // (1.0, 0.0) for horizontal, (0.0, 1.0) for vertical

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 _) {
    // 1. Sample center pixel using weight[0]
    vec4 sum = Texel(tex, texture_coords) * weights[0];
    
    // 2. Query texture dimensions to calculate pixel stride offsets
    vec2 texelSize = vec2(1.0) / love_ScreenSize.xy; 
    vec2 stride = direction * texelSize;

    // 3. Bound-check the loop limit safely
    int limit = min(radius, MAX_RADIUS - 1);

    // 4. Sample symmetrically outward
    for (int i = 1; i <= limit; i++) {
        vec2 offset = vec2(float(i)) * stride;
        float w = weights[i];
        
        sum += Texel(tex, texture_coords + offset) * w;
        sum += Texel(tex, texture_coords - offset) * w;
    }

    return sum * color;
}
]]


local function updateBlurSigma(sigma)
    -- 1. Determine radius at 3 sigma
    local radius = math.floor(3 * sigma)
    if radius > 63 then radius = 63 end -- Cap to match MAX_RADIUS - 1
    
    -- 2. Compute the 1-sided Gaussian weights
    local weights = {}
    local sum = 0
    
    -- Calculate raw values
    for i = 0, radius do
        -- Standard Gaussian formula: e^(-x^2 / (2 * sigma^2))
        local w = math.exp(-(i * i) / (2 * sigma * sigma))
        weights[i + 1] = w
        
        -- Accumulate for normalization (center is counted once, sides counted twice)
        if i == 0 then
            sum = sum + w
        else
            sum = sum + (w * 2)
        end
    end
    
    -- Normalize weights so the image brightness stays perfect
    for i = 1, #weights do
        weights[i] = weights[i] / sum
    end
    
    -- 3. Send values to shader
    -- Note: unpack() works perfectly for sending arrays to love shaders
    Gauss:send("weights", unpack(weights))
    Gauss:send("radius", radius)
end

-- Example: Set up for a sigma of 4.0 (Radius of 12 pixels, 25-tap total width)
--updateBlurSigma(4.0)
function _M.gauss(workflow, sigma)
  
end


-------------------------------
--
-- GAUSSIAN, from Moonshine
--

local gaussian = {}        -- list of already built gaussians

function _M.gaussian(workflow, sigma)
  local gauss = gaussian[sigma]
  if not gauss then
    _log ("creating moonshine GaussianBlur shader, sigma = " .. sigma)
    gauss = moonbridge "gaussianblur"
    gauss.setters.sigma(sigma)
    gaussian[sigma] = gauss
  end
  
  gauss.filter(workflow)
end

-------------------------------
--
-- GAUSSIAN (fast), from Moonshine
--

local fastgaussian = {}        -- list of already built fast gaussians

function _M.fastgaussian(workflow, taps)
  local gauss = fastgaussian[taps]
  if not gauss then
    _log ("creating moonshine FastGaussianBlur shader, #taps = " .. taps)
    gauss = moonbridge "fastgaussianblur"
    gauss.setters.taps(taps)
    fastgaussian[taps] = gauss
  end
  
  gauss.filter(workflow)
end


return _M

-----
