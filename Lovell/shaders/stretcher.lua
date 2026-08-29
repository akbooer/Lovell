--
-- stretcher.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.04",
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


local vector = require "lib.vector"

local love = _G.love
local lg = require "love.graphics"


_M.gammaOptions = {"MidTone", "Asinh", "Hyper", "Gamma", "ModGamma", "Log", "Linear", 
                      id = "Stretch: ", selected = 1, default = 1}


-------------------------

local asinh = love.graphics.newShader[[
    uniform float c;
    
  // arsinh(x) = ln(x + sqrt(x^2 + 1))     
  #define ARSINH(type)  type arsinh (type x) {return log(x + sqrt(x*x + 1.0));}

    ARSINH(vec3)
    ARSINH(float)
    
    const float eps = 1.0e-7;
    const vec3 zero = vec3(0.0, 0.0, 0.0);
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords) .rgb;
      vec3 y = arsinh(x * c) / arsinh(c + eps);
      return vec4(clamp(y, 0.0, 1.0) , 1.0);
    }
  ]]
  

function _M.asinh(stretch)
  local c = stretch * 2000
  local shader = asinh
  shader: send("c", c)
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

function _M.modgamma(stretch)
  -- This is used for processing colour channels
  -- with noise reduction, linear from x=0-a, with slope s

  local g = math.max(.01, 1 - stretch)   -- or 0.5
  local a0 = 0.01

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

local midtone = lg.newShader [[
    uniform vec3 m;

    const float eps = 1.0e-10;
  
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords ) .rgb;
      vec3 mtf = (m - 1.0) * x / ((2.0 * m - 1.0) * x - m);
      return vec4(mtf, 1.0);      
    }
  ]]

--[[
  Mn = normalised median = median - bp
  B  = target background brightness (say 0.25)
  m  = Mn (B - 1) / ( (2B - 1) Mn - B )
--]]

function _M.midtone(c, MEDIAN)
  local Mn = MEDIAN or 0.01
  local shader = midtone
  local B = 0.12   -- target median
  local m = ( Mn * (B - 1) ) / ( Mn * (2 * B - 1) - B)
  m = type(m) ~= "table" and vector{m,m,m,m} or m
  shader: send("m", m / c)
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

function _M.gamma(stretch)
  local c = math.max (0.01, 1 - stretch)
  local shader = gamma
  shader: send("c", {c, c, c})
  return shader
end


-------------------------

local log = lg.newShader [[
    uniform float c;

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 x = Texel(texture, texture_coords) .rgb;
      return vec4(log(c*x + 1.0) / log(c + 1.0), 1.0);      
    }
  ]]

function _M.log(stretch)  
  local c = 200 * stretch + 1e-3
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

function _M.hyper(stretch)
  local d = 0.02
  local c = d * (1 + d - stretch*0.7)
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

function _M.stretch(workflow, selected, stretch, MEDIAN)
  local controls = workflow.controls
  
  local opt = _M.gammaOptions
  selected = selected: lower()
  local setup = _M[selected]
  local shader = setup (stretch, MEDIAN) 

  workflow: shadeWith(shader)
  
  return output
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


