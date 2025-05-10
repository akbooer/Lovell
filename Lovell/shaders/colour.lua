--
-- colour.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.05",
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
-- 2024.04.08  add RGB weighting to lrgb()
-- 2025.05.04  make balance() RGBA ready
-- 2025.05.05  add thumbnail()


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics


_M.channelOptions = {"LRGB", "Luminance", "Inverted", "Red", "Green", "Blue", default = 1}

-------------------------
--
-- SYNTHL, synthetic luminance from RGB and OPTIONAL separate L subs
--
-- RGBL version... alpha channel is luminance

local synthRGBL = lg.newShader([[
    
    uniform float a, b;         // mixing ratio of synthL to L 
    uniform vec3 rgb;           // mixing ratio of RGB for synthL
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      vec4 pixel = Texel(texture, tc );
      float L = clamp(pixel.a, 0.0, 1.0);
      float synthL = dot(pixel.rgb, rgb);     // vector dot product, weighted sum of RGB
      float grey = a * synthL + b * L;
      return vec4(vec3(grey), 1.0);     // now creating 'normal' mono RGB image with unity alpha channel
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
  local R = ratio or 0.5    -- ratio for synthL to L mixture
  local A, B = R / (1 + R), 1 / (1 + R)
  shader = synthRGBL
  shader: send("a", A)
  shader: send("b", B)
  
  shader: send("rgb", {r, g, b})  
  lg.setShader(shader)
  output: renderTo(lg.draw, input)
  lg.setShader()
  
  return output
end

-------------------------

local lrgb = lg.newShader ([[
    uniform vec3 weights;
    uniform Image luminance;

    const float eps = 1.0e-6;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 _ ){
      vec3 rgb = Texel(texture, texture_coords) .rgb;
      float lum = Texel(luminance, texture_coords) .r;
      float l = dot(rgb, vec3(weights)) + eps;
      vec3 RGB = 0.99 * rgb / l ;     // normalised RGB
      vec3 lrgb = clamp(RGB * lum, 0.0, 1.0);
      return vec4(lrgb, 1.0);
    }
]])

function _M.lrgb(workflow, luminance)
  local input, output = workflow()
  luminance = workflow: buffer (luminance)    -- access by name, possibly
  local shader = lrgb
  shader: send("weights", {0.2, 0.7, 0.1})
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
  local sum = r + g + b + 0.02
  r, g, b = r / sum, g / sum, b / sum   -- scale to sum to (nearly) unity
  
  lg.setBlendMode("replace", "premultiplied")
  lg.setShader(balance) 
  balance: send("rgb", {r, g, b})
  output: renderTo(lg.draw, input)
  lg.reset()
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
      return vec4(clamp(mix(intensity, rgb, sat), 0.0, 1.0), 1.0);
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

local magic = lg.newShader [[

  uniform float c;
  
  vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
    vec3 p = Texel(texture, texture_coords) .rgb;
    float mini = min(p.r, min(p.g, p.b));
    p = p - mini + 0.05;
    float m = max(p.r, max(p.g, p.b));
    float s = 0.95 / (m + 1e-5);
    float foo = c;
    p = p * s + 0.01;
    return vec4(clamp(p, 0.0, 1.0), 1.0);
  }
]]

function _M.magic(workflow, c)
 local input, output = workflow()      -- get hold of the workflow buffers
  c = c or 0.8
  lg.setShader(magic) 
  magic: send("c", c)
  output:renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------------
--
-- THUMBNAIL
--

local thumbshade = lg.newShader [[
  vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
    vec3 pixel = Texel(texture, tc) .rgb;
    return vec4(pixel, 1.0);    // override luminance in alpha channel
  }
]]

function _M.thumbnail(workflow)
  local image = workflow.output
  local Wthumb = 700        -- thumbnail width, height scales to preserve aspect ratio
  local lg = _G.love.graphics
  
  local w,h = image:getDimensions()
  local scale = Wthumb / w
  local Hthumb = math.floor(scale * h)
  local thumb = lg.newCanvas(Wthumb, Hthumb, {dpiscale = 1, format = "rgba16f"})
  lg.setColor (1,1,1, 1)
  lg.setShader(thumbshade)
  thumb: renderTo(lg.draw, image, 0,0, 0, scale, scale)
  lg.setShader()
  _log("created thumbnail [%dx%d]" % {Wthumb, Hthumb})
  return thumb
end


return _M

-----
