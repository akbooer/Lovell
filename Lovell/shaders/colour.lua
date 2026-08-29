--
-- colour.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.08.06",
    AUTHOR = "AK Booer",
    DESCRIPTION = "colour processing (saturation, colour balance, scnr...)",
  }
  
-- 2024.11.10  Version 0
-- 2024.11.26  add colourise() to apply colour filter
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.07  add selected to channelOptions
-- 2025.01.29  integrate into workflow
-- 2025.02.24  add invert()
-- 2025.03.23  recoding of synthL(), lrgb(), added satboost, removed HSL processing
-- 2024.04.08  add RGB weighting to lrgb()
-- 2025.05.04  make balance() RGBA ready
-- 2025.05.05  add thumbnail()
-- 2025.05.11  correct lrgb() colour normalisation
-- 2025.05.14  modify thumbnail LRGB processing

-- 2026.04.27  move thumbnail() to workflow module
-- 2026.05.28  added mixing amount to scnr processing and combined tint / colour temperature
-- 2026.06.14  add scaling by max to Lsynth(), to handle sum, not qverage, stack

-- 2026.06.15  add mono() and chroma()
-- 2026.07.04  use workflow:shadeWith()
-- 2026.07.24  selector() and invert() moved to plugin 'channel'
-- 2026.08.01  add get_balanced_chroma(), combining peak alignment, gains adjustment, and black/white points
-- 2026.08.06  removed a lot of redundant shaders.


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics


-------------------------

--[[ 

Oklab space saturation 

  ...explicitly requires Linear RGB to work correctly.

Because GLSL matrices are column-major, the matrices in this shader are transposed in their constructors compared 
to how you would write them on a whiteboard. This implementation converts your linear RGB astro-image into Oklab, 
scales the Chroma (a and b channels) to boost faint deep-sky colors without distorting hue, 
and maps it back to linear RGB for display.

--]]

local oksat = lg.newShader [[
#pragma language glsl3

// The saturation multiplier. 
// 1.0 = Original color. 1.5 = 50% boost in deep-sky saturation. 0.0 = Grayscale.
uniform float u_chroma_boost; 

// 1. Linear RGB to LMS Cone Space (Column-major format)
const mat3 RGB_TO_LMS = mat3(
    0.4122214708, 0.2119034982, 0.0883024619,
    0.5363325363, 0.6806995451, 0.2817188376,
    0.0514459929, 0.1073969566, 0.6299787005
);

// 2. Non-Linear LMS to Oklab (Column-major format)
const mat3 LMS_TO_OKLAB = mat3(
    0.2104542553, 1.9779984951, 0.0259040371,
    0.7936177850, -2.4285922050, 0.7827717662,
    -0.0040720468, 0.4505937099, -0.8086757660
);

// 3. Oklab back to Non-Linear LMS (Column-major format)
const mat3 OKLAB_TO_LMS = mat3(
    1.0, 1.0, 1.0,
    0.3963377774, -0.1055613458, -0.0894841775,
    0.2158037573, -0.0638541728, -1.2914855480
);

// 4. LMS back to Linear RGB (Column-major format)
const mat3 LMS_TO_RGB = mat3(
    4.0767416621, -1.2684380046, -0.0041960863,
    -3.3077115913, 2.6097574011, -0.7034186147,
    0.2309699292, -0.3413193965, 1.7076147010
);

// --- Core Conversion Functions ---

vec3 rgb_to_oklab(vec3 rgb) {
    // Convert to LMS cone responses
    vec3 lms = RGB_TO_LMS * rgb;
    
    // Apply non-linear cube root. 
    // We use sign() and abs() to safely handle tiny negative noise fluctuations safely.
    vec3 lms_cbrt = sign(lms) * pow(abs(lms), vec3(1.0 / 3.0));
    
    // Convert to Lightness (L) and color opponent channels (a, b)
    return LMS_TO_OKLAB * lms_cbrt;
}

vec3 oklab_to_rgb(vec3 lab) {
    // Revert to non-linear LMS
    vec3 lms_cbrt = OKLAB_TO_LMS * lab;
    
    // Reverse the cube root (pow 3)
    vec3 lms = lms_cbrt * lms_cbrt * lms_cbrt;
    
    // Return to Linear RGB space
    return LMS_TO_RGB * lms;
}

// --- LÖVE Entry Point ---

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
    // 1. Sample the incoming pixel (assumes linear data from your 16f/32f stack)
    vec4 texel = Texel(tex, tc) * color;
    
    // 2. Transform into Oklab
    vec3 lab = rgb_to_oklab(texel.rgb);
    
    // 3. Dynamic Color Adjustments (Oklch mapping)
    // The 'a' (Green-Red) and 'b' (Blue-Yellow) channels dictate Chroma. 
    // Scaling them evenly boosts saturation without touching Lightness (L) or shifting Hue.
    lab.y *= u_chroma_boost;
    lab.z *= u_chroma_boost;
    
    // 4. Return to Linear RGB
    vec3 rgb_out = oklab_to_rgb(lab);
    
    // Preserve the original alpha
    return vec4(rgb_out, texel.a);
}
]]


function _M.oksat(workflow, boost)
  workflow: shadeWith(oksat, {u_chroma_boost = boost})
end

-------------------------


--[[
      LMS (long, medium, short), is a color space which represents the response of the three types of cone cells 
      of the human eye, named for their responsivity (sensitivity) peaks at long, medium, and short wavelengths.
--]]

local temp_tint = lg.newShader [[
#pragma language glsl3

// GLSL v3 / LÖVE compatible shader

uniform float u_temp;
uniform float u_tint;

// Matrices for color space conversion (Column-major format)
const mat3 RGB_TO_LMS = mat3(
    0.3139902, 0.1516932, 0.0502444,  // Column 0 (R)
    0.6395129, 0.7482059, 0.3065847,  // Column 1 (G)
    0.0464975, 0.1001009, 0.6431709   // Column 2 (B)
);

const mat3 LMS_TO_RGB = mat3(
     5.432622, -1.105179,  0.020213,  // Column 0 (L)
    -4.679103,  2.311198, -1.107621,  // Column 1 (M)
     0.246481, -0.206019,  2.087408   // Column 2 (S)
);

// Vectorized sRGB to Linear conversion
vec3 toLinear(vec3 srgb) {
    vec3 higher = pow((srgb + vec3(0.055)) / vec3(1.055), vec3(2.4));
    vec3 lower = srgb / vec3(12.92);
    
    // step(edge, x) returns 1.0 if x >= edge, else 0.0. 
    // mix() uses that to seamlessly blend between 'lower' and 'higher' per channel.
    return mix(lower, higher, step(vec3(0.04045), srgb));
}

// Vectorized Linear to sRGB conversion
vec3 toSRGB(vec3 linear) {
    vec3 higher = vec3(1.055) * pow(linear, vec3(1.0 / 2.4)) - vec3(0.055);
    vec3 lower = linear * vec3(12.92);
    
    return mix(lower, higher, step(vec3(0.0031308), linear));
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 texColor = Texel(tex, texture_coords);
    
    // Uncomment if working with sRGB textures in a linear pipeline
    // vec3 r_lin = toLinear(texColor.rgb);
    vec3 r_lin = texColor.rgb;
    
    // 1. Convert to LMS color space using matrix multiplication
    vec3 LMS = RGB_TO_LMS * r_lin;
    
    // 2. Group the scaling factors into a single vector
    vec3 f_LMS = vec3(
        1.0 + (u_temp * 0.1) - (u_tint * 0.05),
        1.0 + (u_tint * 0.1),
        1.0 - (u_temp * 0.1) - (u_tint * 0.05)
    );
    
    // 3. Apply temp/tint adjustments via element-wise multiplication
    vec3 LMS_new = LMS * f_LMS;
    
    // 4. Convert back to RGB using matrix multiplication
    vec3 r_lin_new = LMS_TO_RGB * LMS_new;
    
    // Optional: vec3 final_rgb = clamp(toSRGB(r_lin_new), 0.0, 1.0);
    vec3 final_rgb = clamp(r_lin_new, 0.0, 1.0);
    
    // Multiplied by 'color' to respect global LÖVE color settings
    return vec4(final_rgb, texColor.a) * color;
}

]]


function _M.temp_tint(workflow, temp, tint)
  workflow: shadeWith(temp_tint, {
              u_temp = temp,
              u_tint = -tint})    -- yes, minus
end

-------------------------

--[[
% SCNR - Subtractive Chromatic Noise Reduction
%
% Average Neutral Protection method: min(g, r/2 + b/2)
% see: https://pixinsight.com/doc/legacy/LE/21_noise_reduction/scnr/scnr.html
%
--]]

local scnrShader = lg.newShader[[

  uniform float amount;
  
  vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
    vec4 pixel = Texel(texture, texture_coords);
    pixel.g = mix(pixel.g, min(pixel.g, 0.5*(pixel.r + pixel.b)), amount);
    return pixel;
  }
  ]]

function _M.scnr(workflow, amount)
  amount = amount or 1
  if amount < 0.02 then return end
  workflow:shadeWith(scnrShader, {amount = amount})
end



return _M

-----
