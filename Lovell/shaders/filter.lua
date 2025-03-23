--
-- filter – 
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry processing filters (BOX, TNR, APF, ...)",
  }

local _log = require "logger" (_M)

local moonbridge  = require "shaders.moonbridge"   -- Moonshine proxy

-- 2024.11.07  Version 0, @akbooer
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.29  incoporate moonshine bridge shaders
-- 2025.03.21  use named buffers (possibly) in tnr() and apf()


local love = _G.love
local lg = love.graphics


-------------------------------
--
-- BOXBLUR, from Moonshine
--

local boxblur = moonbridge "boxblur"

function _M.boxblur(workflow, radius)
  boxblur.setters.radius(radius or 3)
  boxblur.filter(workflow)
end

-------------------------------
--
-- GAUSSIAN, from Moonshine
--

local gaussian = {}        -- list of already built gaussians

function _M.gaussian(workflow, sigma)
  local gauss = gaussian[sigma]
  if not gauss then
    _log ("creating moonshine GaussianBlur shader, sigma = " .. sigma)
    gauss = moonbridge "gaussianblur"
    gauss.setters.sigma(sigma)
    gaussian[sigma] = gauss
  end
  
  gauss.filter(workflow)
end

-------------------------------
--
-- GAUSSIAN (fast), from Moonshine
--

local fastgaussian = {}        -- list of already built fast gaussians

function _M.fastgaussian(workflow, taps)
  local gauss = fastgaussian[taps]
  if not gauss then
    _log ("creating moonshine FastGaussianBlur shader, #taps = " .. taps)
    gauss = moonbridge "fastgaussianblur"
    gauss.setters.taps(taps)
    fastgaussian[taps] = gauss
  end
  
  gauss.filter(workflow)
end

-------------------------------
--
-- TNR - Tony's noise reduction
--

--[[

  this is my PixInsight implementation:
  
  Radius = 17;
  Strength = 30;

  ($T - medfilt($T, Radius))                   // signal - model
     * (1 / (1 + Strength * exp (-27 * $T)))   // window
     + medfilt($T, Radius)                     // + model

]]

local tnr = love.graphics.newShader[[
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background, tc) .rgb;
    vec3 window = one / (1.0 + strength * exp (-7.0 * image));
    vec3 tnr = (image - backg) * window + image;
    return vec4(clamp(tnr, 0.0, 1.0), 1.0);
  }]]

function _M.tnr(workflow, background)
  local strength = 30 * workflow.controls.denoise.value
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  background = workflow: buffer(background)
  local shader = tnr
  lg.setShader(shader)
  shader: send("background", background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF0 - two scales: 3x3, plus whatever additional smoothed background is supplied
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf0 = love.graphics.newShader[[
  extern vec2 dx, dy;
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec4 d = Texel(texture, tc);
    vec3 image = d.rgb;
    
    d += Texel(texture, tc + dx + dy);
    d += Texel(texture, tc - dx + dy);
    d += Texel(texture, tc + dx - dy);
    d += Texel(texture, tc - dx - dy);
    d += Texel(texture, tc + dx);
    d += Texel(texture, tc - dx);
    d += Texel(texture, tc + dy);
    d += Texel(texture, tc - dy);
    vec3 back0 = d .rgb / 9.0;
    
    vec3 backg = Texel(background,  tc) .rgb;
    vec3 foo = image;
    image = pow(image, pow(vec3(2.0), 6.0 * strength * (back0 - image)));
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    return vec4(clamp(image, 0.0, 1.0), 1.0);
  }]]

function _M.apf0(background, workflow)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  local strength = controls.sharpen.value
  local shader = apf0
  if strength == 0 then return end
  local w, h = input: getDimensions()
  lg.setShader(shader)
  shader: send("dx", {1 / (w - 1), 0})
  shader: send("dy", {0, 1 / (h - 1)})
  shader: send("background",  background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF - 2 scales
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf2 = love.graphics.newShader[[
  extern float strength;
  extern Image background, background2;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background,  tc) .rgb;
    vec3 back2 = Texel(background2, tc) .rgb;
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    image = pow(image, pow(vec3(2.0), 3.0 * strength * (back2 - image)));
    return vec4(clamp(image, 0.0, 1.0), 1.0);
  }]]

function _M.apf2(workflow, background, background2)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  background  = workflow: buffer(background)
  background2 = workflow: buffer(background2)
  local strength = controls.sharpen.value
  local shader = apf2
  lg.setShader(shader)
  shader: send("background",  background)
  shader: send("background2", background2)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end

-------------------------------
--
-- APF
--
--[[
$T ^ (2^(gconv($T,3) - $T))
for 3, 6, 12, 24

]]

local apf = love.graphics.newShader[[
  extern float strength;
  extern Image background;
  const vec3 one = vec3(1.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    vec3 backg = Texel(background, tc) .rgb;
    vec3 apf = pow(image, pow(vec3(2.0), 3.0 * strength * (backg - image)));
    return vec4(clamp(apf, 0.0, 1.0), 1.0);
  }]]

function _M.apf(...)
  local workflow, background, background2 = ...
  if background2 then
    return _M.apf2(...)
  end
  background = workflow: buffer(background)
  local input, output, controls = workflow()      -- get hold of the workflow buffers and controls
  local strength = controls.sharpen.value
  local shader = apf
  lg.setShader(shader)
  shader: send("background", background)
  shader: send("strength", strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
  return output
end


return _M

-----
