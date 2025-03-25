--
-- colour.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "colour processing (synth lum, colour balance, ...)",
  }
  
-- 2024.11.10  Version 0
-- 2024.11.26  add colourise() to apply colour filter
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.07  add selected to channelOptions
-- 2025.01.29  integrate into workflow
-- 2025.02.24  add invert()
-- 2025.03.23  recoding of synthL(), lrgb(), added satboost, removed HSL processing


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics


_M.channelOptions = {"LRGB", "Luminance", "Inverted", "Red", "Green", "Blue", default = 1}

-------------------------
--
-- SYNTHL, synthetic luminance from RGB and OPTIONAL separate L subs
--

-- no additional Luminance image
--local synth = lg.newShader([[
    
--    uniform vec3 rgb;           // mixing ratio of RGB for synthL
    
--    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
--      vec3 pixel = Texel(texture, texture_coords ) .rgb;
--      float grey = dot(pixel, rgb);     // vector dot product, weighted sum of RGB
--      return vec4(vec3(grey), 1.0);
--    }
--]])

-- with additional Luminance image
local synthLL = lg.newShader([[
    
    uniform Image luminance;    // Luminance filter stack
    uniform float a, b;         // mixing ratio of synthL to L 
    uniform vec3 rgb;           // mixing ratio of RGB for synthL
    
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 _){
      vec3 pixel = Texel(texture, texture_coords ) .rgb;
      float lum = clamp(Texel(luminance, texture_coords) .r, 0.0, 1.0);
      float synthL = dot(pixel, rgb);     // vector dot product, weighted sum of RGB
      float grey = a * synthL + b * lum;
      return vec4(vec3(grey), 1.0);
    }
]])


function  _M.synthL(workflow, rgb, luminance, ratio)
  local input, output = workflow()
  
  -- RGB ratios for synthL
  rgb = rgb or {1.0, 1.0, 1.0}
  local r, g, b = unpack(rgb)
  local sum = r + g + b + 1e-6
  r, g, b = r / sum, g / sum, b / sum   -- scale to sum to unity
  
  local shader
--  local shader = synth
--  if luminance then
    local R = ratio or 0.5    -- ratio for synthL to L mixture
    local A, B = R / (1 + R), 1 / (1 + R)
    shader = synthLL
    shader: send("a", A)
    shader: send("b", B)
    shader: send("luminance", luminance or workflow.input)
--  end
  
  shader: send("rgb", {r, g, b})  
  lg.setShader(shader)
  output: renderTo(lg.draw, input)
  lg.setShader()
  
  return output
end

-------------------------

local lrgb = lg.newShader ([[
    uniform Image luminance;
    const float eps = 1.0e-6;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float lum = Texel(luminance, texture_coords) .r;
      float l = dot(rgb, vec3(1.0) + eps);
      vec3 lrgb = clamp(rgb * lum / l, 0.0, 1.0);
      return vec4(lrgb, 1.0);
    }
]])

function _M.lrgb(workflow, luminance)
  local input, output = workflow()
  luminance = workflow: buffer (luminance)    -- access by name, possibly
  local shader = lrgb
--  local shader = rgb2hsl2rgb
  shader: send("luminance", luminance)
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
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

function _M.balance(workflow, rgb)
  local input, output = workflow()
  local r, g, b = unpack(rgb)
  
  balance: send("rgb", {r, g, b})
  lg.setShader(balance) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output  
end

-------------------------

--  channel selector

local selector = lg.newShader[[
    uniform vec3 channelMask;
    const vec3 zero = vec3(0);

    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec4 pixel = Texel(texture, texture_coords);
      return vec4(max(zero, pixel.rgb) * channelMask, 1.0);
    }
  ]]

local monochrome =  lg.newShader[[
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec4 pixel = Texel(texture, texture_coords);
      float mono = (pixel.r + pixel.g + pixel.b) / 3.0;
      return vec4(vec3(mono), 1.0);
    }
  ]]

local rgb = {LRGB = {1,1,1}, Red = {1,0,0}, Green={0,1,0}, Blue = {0,0,1}}

function _M.selector(workflow, opts)
  local input, output = workflow()                -- get hold of the workflow buffers
  local selected = opts[opts.selected]
  local shader
  
  if selected == "Luminance" then
    shader = monochrome
  else
    shader = selector
    local selection = rgb[selected] or {1, 1, 1}
    shader: send("channelMask", selection)
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

--[[    
    // Algorithm from Chapter 16 of OpenGL Shading Language
    const vec3 W = vec3(0.2125, 0.7154, 0.0721);
    vec3 intensity = vec3(dot(rgb, W));
    return mix(intensity, rgb, adjustment);

--]]
local sat = lg.newShader [[
    uniform float sat;
    uniform vec3 weights;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      rgb = clamp(rgb, 0.0, 1.0);
      vec3 intensity = vec3(dot(rgb, weights));
      return vec4(mix(intensity, rgb, sat), 1.0);
    }
]]

function _M.satboost(workflow, boost)
  local input, output = workflow()      -- get hold of the workflow buffers
  local shader = sat
  shader: send("sat", boost)
  shader: send("weights", {0.2, 0.7, 0.1})
  lg.setShader(shader) 
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------

local invert = lg.newShader [[
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float l = clamp(1.0 - dot(rgb, vec3(1.0/3.0)), 0, 1);
      return vec4(vec3(l), 1.0);
    }
]]

function _M.invert(workflow, opts)
  if opts[opts.selected] ~= "Inverted" then return end
  local input, output = workflow()      -- get hold of the workflow buffers
  local shader = invert
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

function _M.balance_R_GB(workflow, tint)
  local input, output = workflow()      -- get hold of the workflow buffers
  local log = math.log
  local r, bg  = tint, 0.5
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
