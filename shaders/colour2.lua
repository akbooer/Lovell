--
-- colour.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.10",
    AUTHOR = "AK Booer",
    DESCRIPTION = "colour processing (synth lum, colour balance, ...)",
  }
  
-- 24.11.10  Version 0


local _log = require "logger" (_M)

local lg = require "love.graphics"
local GCS = require "lib.GLSL-Color-Spaces"
--local LUV = require "lib.HSLuv"


_M.channelOptions = {"LRGB", "Luminance", "Red", "Green", "Blue"}

-------------------------

local synth = lg.newShader([[

    // Pixel Shader
    
    uniform vec3 rgb;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords ) .rgb;
      float grey = dot(pixel, rgb);     // vector dot product
      return vec4(vec3(grey), 1.0);
    }
]])

function  _M.synthL(input, output, rgb)
  
  rgb = rgb or {1, 1, 1}
  local sum = rgb[1] + rgb[2] + rgb[3]
  for i = 1,3 do rgb[i] = rgb[i] / sum end
  
  synth: send("rgb", rgb)
  lg.setShader(synth)
  output: renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------

local balance = lg.newShader [[
  uniform vec3 rgb;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 x = Texel(texture, tc);
    return vec4(x.rgb * rgb, x.a);
  }
]]

function _M.balance(input, output, controls)
  
  local c = controls
  local r, g, b = c.red.value, c.green.value, c.blue.value
  local rgb = r + g + b + 1e-3
  
  balance: send("rgb", {r / rgb, g / rgb, b / rgb})
  lg.setShader(balance) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  
end

-------------------------

--  channel selector

local selector = lg.newShader[[
    uniform vec3 channelMask;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return vec4(pixel.rgb * channelMask, 1.0);
    }
  ]]

local monochrome =  lg.newShader[[
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      float mono = (pixel.r + pixel.g + pixel.b) / 3.0;
      return vec4(vec3(mono), 1.0);
    }
  ]]

local rgb = {LRGB = {1,1,1}, Red = {1,0,0}, Green={0,1,0}, Blue = {0,0,1}}

function _M.selector(input, output, controls)
  local selected = controls.channelOptions[controls.channel]
  local shader
  
  if selected == "Luminance" then
    shader = monochrome
  else
    shader = selector
    local selection = rgb[selected] or {1, 1, 1}
    selector: send("channelMask", selection)
  end
    
  lg.setShader(shader) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  
end

-------------------------

local rgb2hsl = lg.newShader (GCS .. [[
    uniform float scale;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return vec4((rgb_to_hsl(scale*pixel.rgb)), 1.0);
    }
]])

function _M.rgb2hsl(input, output, controls)
  local shader = rgb2hsl
--  shader: send("scale", 1 / controls.Nstack)
  shader: send("scale", 1)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------

local hsl2rgb = lg.newShader (GCS .. [[
    uniform float scale, sat;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      pixel.y = pixel.y * sat ;
      return vec4((hsl_to_rgb(pixel.rgb)) / scale, 1.0);
    }
]])

function _M.hsl2rgb(input, output, controls)
  local shader = hsl2rgb
  shader: send("scale", 1)
  shader: send("sat", controls.saturation.value)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------

-- replace HSL luminance with alternative
local lrgb = lg.newShader (GCS .. [[
    uniform Image luminance;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float lum = Texel(luminance, texture_coords) .r;
      // vec3 hsl = vec3(rgb_to_hsl(rgb).xy, lum);
      vec3 hsl = rgb_to_hsl(rgb);
      rgb = hsl_to_rgb(hsl);
      return vec4(rgb, 1.0);
    }
]])

function _M.lrgb(luminance, rgb, output, controls)
  local shader = lrgb
  shader: send("luminance", luminance)
  lg.setShader(shader) 
  output:renderTo(lg.draw, rgb)
  lg.setShader()
end

-------------------------

local triangle = lg.newShader ([[
    //Vertex Shader
    
    // calculate the vertex background values which are interpolated for the pixel shader
    
//    uniform vec2 a, b, c;

    vec4 position( mat4 transform_projection, vec4 texture_pos ) {
      return transform_projection * texture_pos;
    }
]],[[

    //Fragment Shader
    
    uniform float   scale, sat;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return pixel;
    }
]])

function _M.triangle(output, x,y, size)
  local shader = triangle
--  shader: send("scale", 1 / controls.Nstack)
--  shader: send("sat", controls.saturation.value)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
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
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      pixel.g = min(pixel.g, 0.5*(pixel.r + pixel.b));
      return pixel;
    }
  ]]

function _M.scnr(input, output)
  lg.setShader(scnrShader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------

return _M

-----
