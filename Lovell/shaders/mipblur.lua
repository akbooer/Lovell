--
-- DualMipBlur 
--


local _M = {
    NAME = ...,
    VERSION = "2026.07.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Fast Dual Mip Blur filter",
  }

require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.07.09  Version 0, @akbooer
-- 2026.07.14  use renderToMipmap() 



--[[

    DualMipBlur.glsl
    
    An ultra-fast, single-pass background estimation filter designed to approximate 
    large-sigma Gaussian convolutions (e.g., Kovesi almost-Gaussian profiles).
    
    Mechanics:
    - Utilizes a 13-tap low-discrepancy Weyl sequence with screen-space dither 
      to eliminate spatial patterns.
    - Employs a cross-level trilinear mipmap blend (55/45) to smooth out 
      hardware interpolation "tent" profiles and eliminate aliasing contours.
    - Achieves macro-scale gradient smoothing with exactly 26 texture lookups.

--]]

local DualMipBlurShader = lg.newShader [[
#pragma language glsl3

extern float u_targetSigma; 

const float PI = radians(180.0);
const float GOLDEN_RATIO = (sqrt(5.0) + 1.0) / 2.0;

// High-performance interleaved gradient noise for spatial dither baseline
float interleaved_gradient_noise(vec2 screen_coords) {
    vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(screen_coords, magic.xy)));
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // 1. Establish the base mathematical mip level from user sigma
    float mipBase = log2(u_targetSigma);
    mipBase = max(0.0, mipBase);

    // 2. Setup the secondary macro mip layer (1.5 octaves deeper) 
    // This creates the broad "shoulders" of our approximated Gaussian curve
    float mipWide = mipBase + 1.5;

    // Introduce a subtle coordinate shift to loosen screen-space grid ties
    vec2 baseTexelSize = vec2(1.0) / vec2(love_ScreenSize.xy);
    float baseNoise = interleaved_gradient_noise(screen_coords + texture_coords * 0.1);
    
    vec4 blurAccum = vec4(0.0);
    float weightAccum = 0.0;

    // Execute 13 low-discrepancy Weyl sequence taps (yielding 26 lookups total)
    const int totalTaps = 13;
    for (int i = 0; i < totalTaps; i++) {
        // --- GOLDEN-RATIO WEYL SEQUENCE ---
        float t = fract(baseNoise + float(i) * GOLDEN_RATIO);
        
        float r = 0.0;
        float currentWeight = 0.0;

        // Distribute the 13 taps across 3 spatial zones
        if (i == 0) {
            // Zone 0: Tight sub-pixel core jitter
            r = t * 0.4; 
            currentWeight = 0.26; 
        } else if (i < 7) {
            // Zone 1: Inner Ring (0.8 to 1.4 texel stride)
            r = 0.8 + (float(i - 1) / 5.0) * 0.6;
            currentWeight = 0.08; 
        } else {
            // Zone 2: Outer Ring (1.5 to 2.5 texel stride)
            r = 1.5 + (float(i - 7) / 5.0) * 1.0;
            currentWeight = 0.043; 
        }

        // Interleave the sampling angles uniformly around the unit circle
        float angle = (float(i) * (2.0 * PI / 6.0)) + (baseNoise * (PI / 3.0));
        vec2 baseStep = vec2(cos(angle), sin(angle)) * r;
        
        // Map the offsets relative to our base mip scaling factor
        vec2 finalOffset = baseTexelSize * baseStep * pow(2.0, mipBase);
        vec2 sampleCoords = texture_coords + finalOffset;

        // --- DUAL-MIP CROSS BLEND ---
        // Fetch the narrow/sharp core profile
        vec4 sampleNarrow = textureLod(tex, sampleCoords, mipBase);
        
        // Fetch the broad/highly-diffused macro profile
        vec4 sampleWide = textureLod(tex, sampleCoords, mipWide);

        // Mix the two profiles together (55% core + 45% broad tail)
        // This effectively transforms the hardware's rigid triangular tent 
        // reconstruction profile into a multi-sloped Gaussian-like decay curve.
        vec4 multiSlopeTap = mix(sampleNarrow, sampleWide, 0.45);
        
        blurAccum += multiSlopeTap * currentWeight;
        weightAccum += currentWeight;
    }

    // Precise normalization against the accumulated weight sum
    return (blurAccum / weightAccum) * color;
}
]]


local function DualMipBlur(workflow, sigma)
 
 if sigma < 0.05 then return end
 
  -- write to dedicated buffer with MipMaps enabled
  workflow: renderToMipmap()
  workflow: newInput "mipmap"
     
  workflow: shadeWith(DualMipBlurShader, {u_targetSigma = sigma})    -- process the Blur
 
end


return DualMipBlur

-----
