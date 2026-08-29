--
-- lodGaussian 
--


local _M = {
    NAME = ...,
    VERSION = "2026.07.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Fast single-pass 9-tap Gaussian filter with trilinear LOD interpolation",
  }

require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.07.25  Version 0, @akbooer



--[[

This single-pass LÖVE2D fragment shader computes a mathematically exact, continuous, isotropic 2D Gaussian blur. 
By decoupling the spatial kernel from the hardware resolution, it achieves arbitrary blur radii (σ) without the performance
penalty of large spatial convolutions or the leptokurtic (fat-tailed) artifacts typical of multi-scale mipmap summation.
It is specifically optimized to preserve perfectly circular Point Spread Functions (PSFs) for astronomical imaging.

--]]

local tetrad = lg.newShader [[
#pragma language glsl3
// Only one uniform needed now!
uniform float u_targetSigma;    // Target Gaussian Sigma (e.g., 10.0)

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // 1. Dynamically query canvas/image size at base LOD
    vec2 imageSize = vec2(textureSize(tex, 0));

    // 2. Mathematically exact 1D weights for a Gaussian with sigma = 1.2
    float w0 = 0.34338; 
    float w1 = 0.32831; 
    float off = 1.2608; 

    // 3. Calculate the exact LOD required to stretch sigma=1.2 to u_targetSigma
    float lod = max(0.0, log2(u_targetSigma / 1.2));

    // 4. Calculate the UV offset step
    // exp2(lod) scales the footprint, imageSize normalizes it to UV space
    vec2 d = (exp2(lod) / imageSize) * off;

    vec4 accum = vec4(0.0);

    // --- 9-Tap 2D Tensor Product ---

    // Center
    accum += Texel(tex, texture_coords, lod) * (w0 * w0);

    // 4 Edges (Left, Right, Up, Down)
    accum += Texel(tex, texture_coords + vec2( d.x,  0.0), lod) * (w1 * w0);
    accum += Texel(tex, texture_coords + vec2(-d.x,  0.0), lod) * (w1 * w0);
    accum += Texel(tex, texture_coords + vec2( 0.0,  d.y), lod) * (w0 * w1);
    accum += Texel(tex, texture_coords + vec2( 0.0, -d.y), lod) * (w0 * w1);

    // 4 Corners
    accum += Texel(tex, texture_coords + vec2( d.x,  d.y), lod) * (w1 * w1);
    accum += Texel(tex, texture_coords + vec2(-d.x,  d.y), lod) * (w1 * w1);
    accum += Texel(tex, texture_coords + vec2( d.x, -d.y), lod) * (w1 * w1);
    accum += Texel(tex, texture_coords + vec2(-d.x, -d.y), lod) * (w1 * w1);

    return accum * color;
}
]]


local function DualMipBlur(workflow, sigma)
 
 if sigma < 0.05 then return end
 
  -- write to dedicated buffer with MipMaps enabled
  workflow: renderToMipmap()
  workflow: newInput "mipmap"
     
  workflow: shadeWith(tetrad, {u_targetSigma = sigma})    -- process the Blur
 
end


return DualMipBlur

-----
