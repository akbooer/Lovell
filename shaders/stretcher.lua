--
-- stretcher.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.02",
    AUTHOR = "Martin Meredith / AK Booer",
    DESCRIPTION = "stretches of various sorts on final stack",
  }

local _log = require "logger" (_M)

--  2024.10.18  Version 0, copied from Jocular stretches
--  2024.11.12  add modgamma() and the rest!

local love = _G.love
local lg = require "love.graphics"

local stats = require "shaders.stats" .stats

_M.gammaOptions = {"Linear", "Log", "Gamma", "ModGamma", "Asinh", "Hyper"}

--
-- apply scale inputs to stretches with black/white points and number of stacked images
--
local function applyShader(shader, input, output, controls)
  
  local black = 0.01 * (0.5 - controls.background.value)
  local white = 1 - controls.brightness.value
    
  shader: send("black", black)
  shader: send("white", math.max(0.02, white))

  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
 end

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
  

function _M.asinh(input, output, controls)
  
  local c = controls.stretch.value * 2000
  asinh: send("c", c)
  
  return applyShader(asinh, input, output, controls) 
  
end


-------------------------

local modgamma = lg.newShader [[
    uniform float black, white;
    uniform float a0, g, s, d;
    
    const vec3 zero = vec3(0.0 ,0.0, 0.0);
    
    #define gamma(x) x >= a0 ? (1 + d) * pow(x, g) - d : x * s
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = max(zero, (pixel.rgb - black)) / white;
    
     return vec4(gamma(x.r), gamma(x.g), gamma(x.b), 1.0);
      
    }
  ]]

function _M.modgamma(input, output, controls)
  -- This is used for processing colour channels
  -- with noise reduction, linear from x=0-a, with slope s

  local g = math.max(.01, 1 - controls.stretch.value)   -- or 0.5
  local a0 = 0.01

  local s = g / (a0 * (g - 1) + a0 ^ (1 - g))
  local d = (1 / (a0 ^ g * (g - 1) + 1)) - 1

  modgamma: send("a0", a0)
  modgamma: send("g",  g)
  modgamma: send("s",  s)
  modgamma: send("d",  d)

  return applyShader(modgamma, input, output, controls) 

end


-------------------------

local gamma = lg.newShader [[
    uniform float black, white;
    uniform vec3 c;
        
    const vec3 zero = vec3(0.0, 0.0, 0.0);

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = max(zero, (pixel.rgb - black)) / white;
      return vec4(pow(x, c), 1.0);      
    }
  ]]

function _M.gamma(input, output, controls)
  
  local c = math.max (0.01, 1 - controls.stretch.value)
  gamma: send("c", {c, c, c})
  
  return applyShader(gamma, input, output, controls) 
   
end



-------------------------

local log = lg.newShader [[
    uniform float black, white;
    uniform float c;
        
    const vec3 zero = vec3(0.0, 0.0, 0.0);

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = max(zero, (pixel.rgb - black)) / white;
      return vec4(log(c*x + 1) / log(c + 1), 1.0);      
    }
  ]]

function _M.log(input, output, controls)
  
  local c = 200 * controls.stretch.value + 1e-3
  log: send("c",  c)
   
  return applyShader(log, input, output, controls) 
   
end


-------------------------

local hyper = lg.newShader [[
    uniform float black, white;
    uniform float c;
        
    const vec3 zero = vec3(1.0e-6);
        
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      vec3 x = max(zero, (pixel.rgb - black)) / white;
        return vec4((1 + c) * (x / (x + c)), 1.0);      
    }
  ]]

function _M.hyper(input, output, controls)

  local d = 0.02
  local c = d * (1 + d - controls.stretch.value)
  hyper: send("c",  c)

  return applyShader(hyper, input, output, controls) 

end


-------------------------

function _M.linear(input, output, controls)
  gamma: send("c", {1, 1, 1})
  
  return applyShader(gamma, input, output, controls) 

end


return _M

-----


