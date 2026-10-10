--
-- stretcher.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.09",
    AUTHOR = "Martin Meredith / AK Booer",
    DESCRIPTION = "stretches of various sorts on final stack",
  }

local _log = require "logger" (_M)

-- 2024.10.18  Version 0, copied from Jocular stretches
-- 2024.11.12  add modgamma() and the rest!

-- 2025.01.29  integrate into workflow chain
-- 2025.05.11  add bw_points() adjustment (separated from stretch)

-- 2026.04.14  add midtone() and black/white parameters to stretch()
-- 2026.07.04  use workflow:shadeWith()
-- 2026.10.04  add 'luminance' / 'chrominance' checkboxes to gamma options
-- 2026.10.07  scale stretch parameters to map median level to 0.09 at default stretch level
-- 2026.10.09  add Lua implementations and use numerical solver for target background levels


local vector = require "lib.vector"
local solver = require "lib.solver"


local love = _G.love
local lg = require "love.graphics"

local eps = 1e-6;
local GREY_SKY = 0.09

local luminance   = {checked = false, action = nil, text = "protect RGB"}   -- Lupton processing

--[[

  Dual implementation of each of the stretch functions (in GLSL and Lua) allows both statistic value adjustments
  between cascaded stretches, and the inversion of the stretch parameter to achieve a given level.
  
--]]
_M.gammaOptions = {"MidTone", "Asinh", "Hyper", "Gamma", "ModGamma", "Log", "Linear",
                      '-'..('–'): rep(20),            -- unselectable divider
                      luminance,                      -- special checkbox
                      luminance   = luminance,
                      id = "Stretch: ", selected = 1, default = 1}

-------------------------

local glsl3_rec709 = [[
#pragma language glsl3

    // Standard CIE Rec.709 luminance weights
    const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
    
    const float eps = 1.0e-6;

    vec3 rgb_limit(vec3 rgb) {
        // Soft highlight roll-off: If a channel bleeds past 1.0, 
        // smoothly blend it down instead of letting it hard-clip and cause hue shifts.
        float maxChannel = max(rgb.r, max(rgb.g, rgb.b));
        return (maxChannel > 1.0) ? rgb /= maxChannel : rgb;
    }

]]

local function newShader(glsl)
  return love.graphics.newShader(glsl3_rec709 .. glsl)
end

-------------------------

-- Generic root finder using the direct forward stretch fct(x, c) 
-- x: input level, target_T: desired output level, c0: starting guess
local function solve_stretch_parameter(fct, x, target_T, c0)
  return solver.find_root(function(c) return target_T - fct(x, c) end, c0)
end

-------------------------

local asinh = {
  
  GLSL = newShader [[

    uniform float c;
    uniform bool lum;
    
    float inv_denom = 1.0 / asinh(c + eps);

    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec4 raw = Texel(tex, texture_coords);
      raw.a = dot(raw.rgb, LUMA_WEIGHTS) + eps;  // add synthetic luminance
      vec4 rgbl = asinh(raw * c) * inv_denom;    // stretch both RGB and synthetic :
      if (lum) {
          // use Lupton scaling factor (S = L_stretched / L_orig)   
          rgbl = raw * rgbl.a / raw.a;
      }
      rgbl.a = 1.0;
      return clamp(rgbl, 0.0, 1.0);
    }
  ]],
  
  Lua = function(x, c)
    return math.asinh(x * c) / math.asinh(c + eps)
  end,
    
}

function _M.asinh(stretch, luminance, median)  
  local c0 = 0.17 * median ^ -1.2  -- initial guess  
  local c = solve_stretch_parameter(asinh.Lua, median, GREY_SKY, c0)  
  c = c  * stretch ^ 4      -- expand top end range
  
  local shader = asinh.GLSL
  shader: send("c", c)
  shader: send("lum", luminance)
  return shader
end


-------------------------

local gamma = {
  
  GLSL = newShader [[
  
    uniform vec3 c;

    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec3 x = Texel(tex, tc) .rgb;
      return vec4(pow(x, c), 1.0);      
    }
  ]],
  
  Lua = function(x, c)
    return x ^ c
  end,
 
}

function _M.gamma(stretch, luminance, median)  
  -- exact inverse formula for median level and gamma stretch
  local c = math.log(GREY_SKY) / math.log(median)
  c = c * math.max (0.01, 2 - stretch)
  local shader = gamma.GLSL
  shader: send("c", {c, c, c})
  return shader
end


-------------------------

local modgamma = {
  
  GLSL = newShader [[
  
    uniform float a0, g;
    
    float s = g / (a0 * (g - 1) + pow(a0, (1 - g)));
    float d = (1 / (pow(a0, g) * (g - 1) + 1)) - 1;
    
    #define gamma(x) x >= a0 ? (1 + d) * pow(x, g) - d : x * s
    
    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec3 x = Texel(tex, texture_coords) .rgb;    
      return vec4(gamma(x.r), gamma(x.g), gamma(x.b), 1.0);
    }
  ]],
  
  Lua = function(x, g, a0)
    a0 = a0 or 0.001
    local s = g / (a0 * (g - 1) + a0 ^ (1 - g))
    local d = (1 / (a0 ^ g * (g - 1) + 1)) - 1
    return x >= a0 and (1 + d) * x^g - d or x * s
  end,
  
}

-- This is used for processing colour channels
-- with noise reduction, linear from x=0-a, with slope s
function _M.modgamma(stretch, luminance, median)    
  local a0 = median / 4
  local g = math.log(GREY_SKY) / math.log(median)
  g = g * (2 - stretch + 1e-6)

  local shader = modgamma.GLSL
  shader: send("a0", a0)
  shader: send("g",  g)
  return shader
end


-------------------------

local midtone = {
  
  GLSL = newShader [[
    uniform vec3 m;
    uniform bool lum;
      
    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(tex, texture_coords ) .rgb;
      if (lum) {
          float L = dot(rgb, LUMA_WEIGHTS) + eps;
          float M = m[0];
          float mtf = (M - 1.0) * L / ((2.0 * M - 1.0) * L - M);
          // use Lupton scaling factor (S = L_stretched / L_orig)          
          rgb = rgb * mtf / L;
      } else {
          rgb = (m - 1.0) * rgb / ((2.0 * m - 1.0) * rgb - m);
      }
      return vec4(clamp(rgb_limit(rgb), 0.0, 1.0) , 1.0);
    }
  ]],
  
  Lua = function(x, m)
    return (m - 1.0) * x / ((2.0 * m - 1.0) * x - m);
  end,

}

function _M.midtone(c, luminance, median)
  local B = GREY_SKY
  -- exact formula for inverse stretch
  local m = ( median * (B - 1) ) / ( median * (2 * B - 1) - B)
  m = type(m) ~= "table" and vector{m,m,m,m} or m
  local shader = midtone.GLSL
  shader: send("m", m / c)
  shader: send("lum", luminance)
  return shader
end


-------------------------

local log = {
  
  GLSL = newShader [[
    uniform float c;

    float inv_denom = 1.0 / log(c + 1.0);
    
    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec3 x = Texel(tex, texture_coords) .rgb;
      return vec4(log(c*x + 1.0) * inv_denom, 1.0);      
    }
  ]],
  
  Lua = function(x, c)
    return math.log(c*x + 1.0) / math.log(c + 1.0)
  end,
  
}

function _M.log(stretch, luminance, median)  
  local c0 = 0.127 * median ^ -1.26
  local shader = log.GLSL
  local c = solve_stretch_parameter(log.Lua, median, GREY_SKY, c0)  
  c = c * (stretch + 1e-6) ^2   -- expand range
  shader: send("c",  c)
  return shader
end


-------------------------

local hyper = {
  GLSL = newShader [[
    uniform float m;
    
    const float d = 0.02;
    float c = d * (1 + d - m);
        
    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec3 x = Texel(tex, texture_coords) .rgb;
      return vec4(clamp((1 + c) * (x / (x + c)), 0.0, 1.0), 1.0);      
    }
  ]],
  
  Lua = function(x, m)
    local d = 0.02      -- saturation occurs at c = 0, hence m = 1 + d
    local c = d * (1 + d - m)
    return (1 + c) * (x / (x + c))
  end,
  
}

function _M.hyper(stretch, luminance, median)
  local m = solve_stretch_parameter(hyper.Lua, median, GREY_SKY, 1)  
  local shader = hyper.GLSL
  local max = 1.02
--  shader: send("m",  m + (stretch - 1) * (max - m))
  return shader
end


-------------------------

local linear = lg.newShader [[
    uniform vec3 c;

    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec3 x = Texel(texture, tc) .rgb;
      return vec4(x * c, 1.0);      
    }
  ]]

function _M.linear(c)
  local shader = linear
  shader: send("c", {c, c, c})    -- stretch just controls brightness
  return shader
end


-------------------------
--
-- STRETCH
--

function _M.stretch(workflow, selected, stretch, luminance, greySky)
  
  selected = selected: lower()
  local setup = _M[selected]
  local shader = setup (stretch, luminance, greySky) 

  workflow: shadeWith(shader)
  
end

-------------------------
--
-- adjustment of black/white points
--

local bw_points = lg.newShader [[
    uniform vec3 black, white;
        
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec3 pixel = Texel(texture, tc) .rgb;
    return vec4(clamp((pixel - black) / max(white - black, 1.0e-5), 0.0, 1.0), 1.0) ;
    }
  ]]


function _M.bw_points(workflow, black, white)
  lg.setBlendMode("replace", "premultiplied")
  black = type(black) == "table" and black or {black, black, black}
  white = type(white) == "table" and white or {white, white, white}
  workflow: shadeWith(bw_points, {
              black = black,
              white = white})
  lg.reset()
end


return _M

-----


