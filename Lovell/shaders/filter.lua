--
-- filter – 
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry processing filters (BOX, TNR, APF, ...)",
  }

local _log = require "logger" (_M)

local moonbridge  = require "shaders.moonbridge"   -- Moonshine proxy

-- 2024.11.07  Version 0, @akbooer
-- 2024.12.09  use workflow() function to acquire buffers and control parameters

-- 2025.01.29  incorporate moonshine bridge shaders
-- 2025.03.21  use named buffers (possibly) in tnr() and apf()
-- 2025.05.14  consolidate apf() for different numbers of backgrounds into one single code


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
  }
  
]]

function _M.tnr(workflow, background)
  local controls = workflow.controls
  local strength = controls.denoise.value
  local input, output = workflow()
  background = workflow: buffer(background)
  local shader = tnr
  lg.setShader(shader)
  shader: send("background", background)
  shader: send("strength", 30 * strength)
  output: renderTo(lg.draw, input)
  lg.setShader()
end

-------------------------------
--
-- APF
--
--[[
  
  this is my PixInsight implementation:

  $T ^ (2^(gconv($T,3) - $T))
  for 3, 6, 12, 24

]]

local apf = love.graphics.newShader[[
  
  uniform int nb;
  uniform float strength;
  uniform Image background1, background2, background3;
  
  const vec3 two = vec3(2.0);

  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    vec3 image = Texel(texture, tc) .rgb;
    
    image = pow(image, pow(two, 3.0 * strength * (Texel(background1,  tc) .rgb - image)));
    
    image = nb < 2 ? image : pow(image, pow(two, 3.0 * strength * (Texel(background2,  tc) .rgb - image)));
    
    image = nb < 3 ? image : pow(image, pow(two, 3.0 * strength * (Texel(background3,  tc) .rgb - image)));
    
    return vec4(clamp(image, 0.0, 1.0), 1.0);
  }
  
]]

function _M.apf(workflow, ...)  
  local controls = workflow.controls
  local strength = controls.sharpen.value
  if strength < 0.02 then return end
  
  local background = {...}
  local nb = #background
  for i = 1, math.min(nb, 3) do
    local bg = workflow: buffer(background[i])
    apf: send("background" .. i, bg)
  end
  
  lg.setShader(apf)
  apf: send("nb", nb)
  apf: send("strength", strength)
  
  local input, output = workflow()
  output: renderTo(lg.draw, input)
  lg.setShader()
end


return _M

-----
