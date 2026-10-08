--
-- stretcher.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.07",
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
-- 2026.10.07  scale stretch parameters to map median level to 0.12 at default stretch level


local vector = require "lib.vector"

local love = _G.love
local lg = require "love.graphics"

local luminance, chrominance    -- forward reference

-- radio button toggle between the two checkboxes
local function radio(button)
  local Hit, notHit = luminance, chrominance
  if button.id ~= luminance then
    Hit, notHit = notHit, Hit
  end
  notHit.checked = not Hit.checked  
end

luminance   = {checked = false, action = radio, text = "protect RGB"}   -- Lupton processing
chrominance = {checked = true,  action = radio, text = "separate R G B"}

_M.gammaOptions = {"MidTone", "Asinh", "Hyper", "Gamma", "ModGamma", "Log", "Linear",
                      '-'..('–'): rep(20),          -- unselectable divider
                      luminance,                      -- special checkbox entries
--                      luminance, chrominance,       -- special checkbox entries
                      luminance   = luminance,
                      chrominance = chrominance,
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

local asinh = newShader [[

    uniform float c;
    uniform bool lum;
    
    float inv_denom = 1.0 / asinh(c + eps);

    vec4 effect( vec4 color, Image tex, vec2 texture_coords, vec2 _ ){
      vec4 raw = Texel(tex, texture_coords);
      float L = dot(raw.rgb, LUMA_WEIGHTS) + eps;  // synthetic luminance
      vec4 rgbl = vec4(raw.rgb, L);
      rgbl = asinh(rgbl * c) * inv_denom;   // stretch both RGB and synthetic :
      if (lum) {
          // use Lupton scaling factor (S = L_stretched / L_orig)   
          rgbl = raw * rgbl.a / L;
      }
      rgbl.a = 1.0;
      return clamp((rgbl), 0.0, 1.0);
    }
  ]]
  

function _M.asinh(stretch, luminance, median)
  
  -- For typical astro parameters (m∈[0.0001,0.01] and T∈[0.1,0.15])
  -- this formula places the output median within 5%
  local T = 0.12   -- target median
  local m = median
  local c = 0.25 * m ^ -1.2 
  c = c  * stretch ^ 4      -- expand top end range
  
  local shader = asinh
  shader: send("c", c)
  shader: send("lum", luminance)
  return shader
end


-------------------------

local gamma = lg.newShader [[
  
    uniform vec3 c;

    vec4 effect( vec4 color, Image tex, vec2 tc, vec2 _ ){
      vec3 x = Texel(tex, tc) .rgb;
      return vec4(pow(x, c), 1.0);      
    }
  ]]

function _M.gamma(stretch, luminance, median)  
  -- exact inverse formula for median level and gamma stretch
  local T = 0.12   -- target median
  local m = median
  local c = math.log(T) / math.log(median) * math.max (0.01, 2 - stretch)
  local shader = gamma
  shader: send("c", {c, c, c})
  return shader
end


-------------------------

local modgamma = lg.newShader [[
    uniform float a0, g, s, d;
    
    #define gamma(x) x >= a0 ? (1 + d) * pow(x, g) - d : x * s
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords) .rgb;    
     return vec4(gamma(x.r), gamma(x.g), gamma(x.b), 1.0);
    }
  ]]

-- This is used for processing colour channels
-- with noise reduction, linear from x=0-a, with slope s
function _M.modgamma(stretch, luminance, median)  
  -- exact inverse formula for median level and gamma stretch
  local T = 0.12   -- target median
  local m = median
  local g = math.log(T) / math.log(median) * (2 - stretch + 1e-6)

--  local g = math.max(.01, 1 - stretch)   -- or 0.5
  local a0 = median / 4

  local s = g / (a0 * (g - 1) + a0 ^ (1 - g))
  local d = (1 / (a0 ^ g * (g - 1) + 1)) - 1

  local shader = modgamma
  shader: send("a0", a0)
  shader: send("g",  g)
  shader: send("s",  s)
  shader: send("d",  d)
  return shader
end


-------------------------

local midtone = newShader [[
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
  ]]

--[[
  Mn = normalised median = median - bp
  B  = target background brightness (say 0.25)
  m  = Mn (B - 1) / ( (2B - 1) Mn - B )
--]]

function _M.midtone(c, luminance, MEDIAN)
  local Mn = MEDIAN or 0.01
  local shader = midtone
  local B = 0.12   -- target median
  local m = ( Mn * (B - 1) ) / ( Mn * (2 * B - 1) - B)
  m = type(m) ~= "table" and vector{m,m,m,m} or m
  shader: send("m", m / c)
  shader: send("lum", luminance)
  return shader
end


-------------------------

local log = lg.newShader [[
    uniform float c;

    float inv_denom = 1.0 / log(c + 1.0);
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords) .rgb;
      return vec4(log(c*x + 1.0) * inv_denom, 1.0);      
    }
  ]]

function _M.log(stretch, luminance, median)  
--  local c = 200 * stretch + 1e-3
  local c = 0.2 * (stretch + 1e-6) ^2 * median ^ -1.28
  local shader = log
  shader: send("c",  c)
  return shader
end


-------------------------

local hyper = lg.newShader [[
    uniform float c;
        
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords) .rgb;
      return vec4(clamp((1 + c) * (x / (x + c)), 0.0, 1.0), 1.0);      
    }
  ]]

function _M.hyper(stretch, luminance, median)
  local d = 0.02
  local c = d * (1 + d - stretch*0.7)
  local T = 0.12
  c = (2 - stretch) * median * (1.0 - T) / (T - median)
  c = math.max(c, 0)
  local shader = hyper
  shader: send("c",  c)
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

function _M.stretch(workflow, selected, stretch, luminance, MEDIAN)
  
  selected = selected: lower()
  local setup = _M[selected]
  local shader = setup (stretch, luminance, MEDIAN) 

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


