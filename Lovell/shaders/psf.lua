--
-- psf.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.10",
  AUTHOR = "AK Booer",
  DESCRIPTION = "global PSF calculation for entire image",
}

-- 2026.09.10  Version 0


--local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics


local psf = lg.newShader [[
// GLSL 3 code for LÖVE (love_PixelShader)
#pragma language glsl3

uniform float u_bg_floor;  // Sky background floor to subtract

vec2 texel_size = 1.0 / vec2(textureSize(MainTex));

// Output:
// Red   = A(0,0) -> I(x,y)^2  [Zero Lag]
// Green = A(1,0) -> I(x,y) * I(x+1,y) [Horizontal Lag]
// Blue  = A(0,1) -> I(x,y) * I(x,y+1) [Vertical Lag]
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // 1. Fetch center pixel and subtract sky floor
    float c = max(0.0, Texel(tex, texture_coords).r - u_bg_floor);

    // 2. Fetch 1-pixel right and 1-pixel down neighbors
    float r = max(0.0, Texel(tex, texture_coords + vec2(texel_size.x, 0.0)).r - u_bg_floor);
    float d = max(0.0, Texel(tex, texture_coords + vec2(0.0, texel_size.y)).r - u_bg_floor);

    // 3. Output products
    float a00 = c * c;
    float a10 = c * r;
    float a01 = c * d;

    return vec4(a00, a10, a01, 1.0);
}
]]



//
--[[

To use this, render the whole image to a single 1x1 canvas using this shader and the "add" mode.

]]


function _M.psf()

  -- Summed values read back from mipmap top level / strided reduction:
  local A00 = global_sum_R  -- Zero lag energy
  local A10 = global_sum_G  -- Horizontal 1-pixel lag
  local A01 = global_sum_B  -- Vertical 1-pixel lag

  -- Average horizontal and vertical lag ratios to account for ellipticity
  local ratio = (A10 + A01) / (2.0 * math.max(1e-6, A00))

  -- Clamp ratio to valid mathematical range (0 < ratio < 1)
  ratio = math.min(math.max(ratio, 0.01), 0.98)

  -- Calculate sigma_1 (psf sigma) directly
  local sigma_1 = math.sqrt(-1.0 / (4.0 * math.log(ratio)))

  -- Optional: Clamp to sensible production boundaries
  sigma_1 = math.min(math.max(sigma_1, 0.8), 3.5)

end


return _M

-----
