--
-- stretcher.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.29",
    AUTHOR = "Martin Meredith / AK Booer",
    DESCRIPTION = "stretches of various sorts on final stack",
  }

local _log = require "logger" (_M)

-- 2024.10.18  Version 0, copied from Jocular stretches
-- 2024.11.12  add modgamma() and the rest!

-- 2025.01.29  integrate into workflow chain


local love = _G.love
local lg = require "love.graphics"


_M.gammaOptions = {"Linear", "Log", "Gamma", "ModGamma", "Asinh", "Hyper", selected = 5}


-------------------------

local asinh = love.graphics.newShader[[
    uniform float black, white, c;
    
  // arsinh(x) = ln(x + sqrt(x^2 + 1))     
  #define ARSINH(type)  type arsinh (type x) {return log(x + sqrt(x*x + 1.0));}

    ARSINH(vec3)
    ARSINH(float)
    
    const float eps = 1.0e-7;
    const vec3 zero = vec3(0.0, 0.0, 0.0);
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      vec3 x = (pixel.rgb - black) / white ;
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
    uniform float black, white;
    uniform float a0, g, s, d;
    
    #define gamma(x) x >= a0 ? (1 + d) * pow(x, g) - d : x * s
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = clamp((pixel.rgb - black) / white, 0.0, 1.0);
    
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

local gamma = lg.newShader [[
    uniform float black, white;
    uniform vec3 c;

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = clamp((pixel.rgb - black) / white, 0.0, 1.0);
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
    uniform float black, white;
    uniform float c;

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = clamp((pixel.rgb - black) / white, 0.0, 1.0);
      return vec4(log(c*x + 1) / log(c + 1), 1.0);      
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
    uniform float black, white;
    uniform float c;
        
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = clamp((pixel.rgb - black) / white, 0.0, 1.0);
      return vec4(clamp((1 + c) * (x / (x + c)), 0.0, 1.0), 1.0);      
    }
  ]]

function _M.hyper(stretch)
  local d = 0.02
  local c = d * (1 + d - stretch)
  c = c > 0 and c or 0
  local shader = hyper
  shader: send("c",  c)
  return shader
end


-------------------------

function _M.linear()
  local shader = gamma      -- use gamma shader
  shader: send("c", {1, 1, 1})
  return shader
end


-------------------------
--
-- apply scale inputs to stretches with black/white points
--

function _M.stretch(workflow, selected, stretch)
  local input, output, controls = workflow()
  
  local opt = _M.gammaOptions
  selected = (selected or opt[opt.selected]): lower()
  local setup = _M[selected]

  local black = 0.01 * (0.5 - controls.background.value)
  local white = 1 - controls.brightness.value
  stretch = stretch or controls.stretch.value
    
  local shader = setup (stretch) 
  shader: send("black", black)
  shader: send("white", math.max(0.005, 2 * white))

  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  
  return output
end


return _M

-----


