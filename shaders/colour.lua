--
-- colour.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.29",
    AUTHOR = "AK Booer",
    DESCRIPTION = "colour processing (synth lum, colour balance, ...)",
  }
  
-- 2024.11.10  Version 0
-- 2024.11.26  add colourise() to apply colour filter
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.07  add selected to channelOptions
-- 2025.01.29  integrate into workflow


local _log = require "logger" (_M)

local HSL = require "shaders.shadertoyHSL"

local love = _G.love
local lg = love.graphics


_M.channelOptions = {"LRGB", "Luminance", "Red", "Green", "Blue", default = 1}

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


function  _M.synthL(workflow, rgb)
  local input, output = workflow()      -- get hold of the workflow buffers and controls
  rgb = rgb or {1.0, 1.0, 1.0}
  local sum = rgb[1] + rgb[2] + rgb[3]
  for i = 1,3 do rgb[i] = rgb[i] / sum end
  
  synth: send("rgb", rgb)
  lg.setShader(synth)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

local balance = lg.newShader [[
  uniform vec3 rgb;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 x = Texel(texture, tc);
    return vec4(x.rgb * rgb, x.a);
  }
]]

function _M.balance(workflow)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls  
  local c = controls
  local r, g, b = c.red.value, c.green.value, c.blue.value
  local rgb = r + g + b + 1e-3
  
  balance: send("rgb", {r / rgb, g / rgb, b / rgb})
  lg.setShader(balance) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output  
end

-------------------------

local colourise = lg.newShader [[
  uniform int channel;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float x = Texel(texture, tc).r;
    vec3 col = vec3(0.0);
    col[channel] = x;
    return vec4(col, 1.0);
  }
]]

function _M.colourise(workflow, channel)
  local input, output = workflow()      -- get hold of the workflow buffers and controls
  local shader = colourise
  shader: send("channel", channel)
  lg.setShader(shader) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

--  channel selector

local selector = lg.newShader[[
    uniform vec3 channelMask;
    const vec3 zero = vec3(0);

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return vec4(max(zero, pixel.rgb) * channelMask, 1.0);
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

function _M.selector(workflow)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  local opts = controls.channelOptions
  local selected = opts[opts.selected]
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
  return output  
end

--local t, f = true, false
--local rgba = {LRGB = {t,t,t,t}, Red = {t,f,f,t}, Green={f,t,f,t}, Blue = {f,f,t,t}}

--function _M.selector(workflow)
--  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
--  local selected = controls.channelOptions[controls.channel]
--  love.graphics.setColorMask(unpack(rgba[selected] or rgba.LRGB))
--  workflow()
--  return output  
--end

-------------------------

local rgb2hsl = lg.newShader (HSL .. [[
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      return vec4(RGBtoHSL(pixel.rgb), 1.0);
    }
]])

function _M.rgb2hsl(workflow)
  local input, output = workflow()      -- get hold of the workflow buffers and controls
  local shader = rgb2hsl
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

local hsl2rgb = lg.newShader (HSL .. [[
    uniform float sat;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords);
      pixel.y = pixel.y * sat;
      return vec4(HSLtoRGB(pixel.rgb), 1.0);
    }
]])

function _M.hsl2rgb(workflow)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  local shader = hsl2rgb
  shader: send("sat", controls.saturation.value)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

local lrgb = lg.newShader ([[
    uniform Image luminance;
    const float eps = 1.0e-6;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float lum = Texel(luminance, texture_coords) .r ;
      float l = dot(rgb, vec3(1.0) + eps);
      vec3 lrgb = rgb * clamp(lum / l, 0.0, 1.0);
      return vec4(lrgb, 1.0);
    }
]])

function _M.lrgb(workflow, luminance)
  local input, output = workflow()      -- get hold of the workflow buffers and controls
  local shader = lrgb
  shader: send("luminance", luminance)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
end
-------------------------

local balance_R_GB = lg.newShader [[
  uniform vec3 rgb;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 x = Texel(texture, tc);
    return vec4(x.rgb * rgb, x.a);
  }
]]

function _M.balance_R_GB(workflow)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  local log = math.log
  local c = controls
--  local r, bg  = c.red.value, c["blue / green"].value
  local r, bg  = c.tint.value, 0.5
  r, bg = (r - 0.5) / 4 + 0.5, bg / 2 + 0.25       -- restrict range
  r = r ^ (log(1/3)  / log(1/2))            -- map 0..1 range with middle being 1/3, not 1/2
  local g = (2 * bg - r) / 2
  local b = 1 - g - r
--  _log ("rgb: %.2f %.2f %.2f" % {r, g, b})
  balance_R_GB: send("rgb", {r, g, b})
  lg.setShader(balance_R_GB) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output  
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

function _M.scnr(workflow)
  local input, output = workflow()      -- get hold of the workflow buffers
  lg.setShader(scnrShader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

return _M

-----
