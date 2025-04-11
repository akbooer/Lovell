--
-- badpixel handling
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.10",
    AUTHOR = "AK Booer",
    DESCRIPTION = "hot pixel removal",
  }

--[[

  Works for both mono and Bayer images, using adjacent pixels of the same colour.
  Pixel replaced by adjacent pixel average if value exceeds some ratio of that average.
  
--]]

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

-- 2024.10.17  Version 0, @akbooer
-- 2024.12.23  use controls.workflow.badratio.value, add mono shader

-- 2025.01.29  integrate into workflow
-- 2025.02.10  use given Bayer pattern to determine whether to use mono or RGB bad pixel 


local love = _G.love
local lg = love.graphics


-------------------------
--
-- MONO
--

--   Kernel:  {{1,2,1},{2,4,2}, [1,2,1}} / 16

local mono = lg.newShader [[
  uniform float ratio;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  
      vec2 y;
      float c;                  // central pixel value
      float p;                  // pixel value
      float g;                  // 'Gaussian' filtered pixel
      float a;                  // average value of adjacent pixels
      
      float r = ratio / 2;
      
      y = tc;
      p = Texel(texture, tc) .r;        g = 4.0 * p; a = 0.0; c = p;
      p = Texel(texture, y + dx) .r;    g += p + p ; a += p;
      p = Texel(texture, y - dx) .r;    g += p + p ; a += p;
      
      y = tc + dy;
      p = Texel(texture, y     ) .r;    g += p + p ; a += p;
      p = Texel(texture, y + dx) .r;    g += p ;     a += p;
      p = Texel(texture, y - dx) .r;    g += p ;     a += p;
      
      y = tc - dy;
      p = Texel(texture, y     ) .r;    g += p + p ; a += p;
      p = Texel(texture, y + dx) .r;    g += p ;     a += p;
      p = Texel(texture, y - dx) .r;    g += p ;     a += p;
      
      g = g / 16.0;         // filtered pixels
      a = a / 8.0;          // average value
      
      return vec4(c > r * g ? a : c, 0.0, 0.0, 1.0);
  }
]]


-------------------------
--
-- RGB
--

local rgb = lg.newShader [[
  uniform float ratio;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
      
      vec2 Dx = dx + dx;
      vec2 Dy = dy + dy;
      
      float c = Texel(texture, tc) .r;
      float d = 0.0;
      d += Texel(texture, tc + Dx) .r;
      d += Texel(texture, tc - Dx) .r;
      d += Texel(texture, tc + Dy) .r;
      d += Texel(texture, tc - Dy) .r;
      d = d / 4.0;
      
      return vec4(c > ratio * d ? d : c, 0.0, 0.0, 1.0);
  }
]]


local function badPixelRemoval(workflow, bayerpat)
  local input, output = workflow()
  local controls = workflow.controls
  local elapsed = newTimer()

  local hasBayer = (bayerpat or ''): match "[RGB][RGB][RGB][RGB]"
  local shader, step
  if hasBayer then
    shader = rgb
   else 
    shader = mono
  end
  
  local w, h = input: getDimensions()
  shader: send("dx", {1 / w, 0})
  shader: send("dy", {0, 1 / h})
  
  local wk = controls.workflow
  local ratio = wk.badpixel.checked and wk.badratio.value or 1e6   -- turn it on/off
  shader: send("ratio", ratio);
  
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
      
  _log(elapsed ("%.3f ms, hot pixel removal [%s]", hasBayer and bayerpat or "MONO"))
  
end



return badPixelRemoval

-----
