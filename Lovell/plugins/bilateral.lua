--
-- bilateral.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.04",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – bilateral filter",
  }

local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.06.24 Version 0
-- 2026.07.04  use workflow:shadeWith()


local bilateral = lg.newShader [[

#pragma language glsl3

// bilateral_denoise.glsl

// Hyperparameters to tune your denoising
uniform int RADIUS = 4;             // Size of the blur kernel (higher = more denoising, heavier)
uniform float SIGMA_SPATIAL = 3.0;  // Controls spatial blur width
uniform float SIGMA_COLOR = 0.1;    // Controls edge preservation (lower = protects stars better)

// Gaussian weight
float gaussian(float x, float sigma) {
    return exp(-(x * x) / (2.0 * sigma * sigma));
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 screen_coords) {
    vec2 texelSize = 1.0 / vec2(textureSize(tex, 0));     // 0 is mipmap level
    vec4 centerColor = Texel(tex, tc);
    
    vec4 sumColor = vec4(0.0);
    float sumWeight = 0.0;

    // Loop through the pixel neighborhood
    for (int x = -RADIUS; x <= RADIUS; x++) {
        for (int y = -RADIUS; y <= RADIUS; y++) {
            // Calculate sample coordinates
            vec2 offset = vec2(float(x), float(y)) * texelSize;
            vec4 sampleColor = Texel(tex, tc + offset);

            // 1. Spatial Weight (how far away is the pixel geometrically?)
            float spatialDist = length(vec2(float(x), float(y)));
            float wSpatial = gaussian(spatialDist, SIGMA_SPATIAL);

            // 2. Color/Intensity Weight (how different is the brightness/color?)
            // This is critical for astronomy: prevents blurring bright stars into dark space
            float colorDist = length(sampleColor.rgb - centerColor.rgb);
            float wColor = gaussian(colorDist, SIGMA_COLOR);

            // Total weight for this neighbor
            float weight = wSpatial * wColor;

            sumColor += sampleColor * weight;
            sumWeight += weight;
        }
    }

    // Return the normalized denoised color, preserving the original alpha channel
    return vec4(sumColor.rgb / sumWeight, centerColor.a) * color;
}
]]

local left = {align = "left"}

local plugin = {
    id = "Bilateral",
    documentation = [[
Bilateral filtering smooths background noise without blurring shrap-edged features.

Sigma_s is the spatial blur width as for a normal spatial filter.

Sigma_r is the 'range' dimension (intensity) and controls the smoothing in the intensity domain.
]],

    sigma_s  = {id = "sigma_s", value = 0, max = 10, default = 0},
    sigma_r   = {id = "sigma_r", value = 0.1, min = 0.01, max = 0.3, default = 0.1},
  }


function plugin:run(workflow)
  local sxy, sc = self.sigma_s.value, self.sigma_r.value
  if sxy < 0.02 then return end
  
  -- make radius extend to twice spatial sigma (amplitude 13.5% of centre) up to limit
  local radius = math.min(10,  2 * sxy)  
    
  workflow: shadeWith (bilateral, {
                SIGMA_SPATIAL = sxy,
                SIGMA_COLOR = sc,
                RADIUS = radius})
end
  
  
function plugin:draw(suit)
  local sl = suit.layout
  sl:padding(20, 5)
  left.color = suit.theme.color.bluetext
  self.centre = self.centre or {color = suit.theme.color.inactive }
  local W = 180 - 20
  
  suit: Label("space / intensity", sl:row(W, 20))
  
  suit: Slideable(self.sigma_s, sl:row(W, 10))
  suit: Slideable(self.sigma_r, sl:row())
end


return plugin

-----


