--
-- badpixel handling
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.04",
    AUTHOR = "AK Booer",
    DESCRIPTION = "hot pixel removal",
  }

--[[

  Works for both mono and Bayer images, using adjacent pixels of the same colour.
  Pixel replaced by adjacent pixel average if value exceeds some ratio of that average.
  
--]]

local _log = require "logger" (_M)


-- 2024.10.17  Version 0, @akbooer
-- 2024.12.23  use controls.workflow.badratio.value, add mono shader

-- 2025.01.29  integrate into workflow
-- 2025.02.10  use given Bayer pattern to determine whether to use mono or RGB bad pixel 

-- 2026.03.30  tidy up
-- 2026.07.04  use texelSize in shader


local love = _G.love
local lg = love.graphics


-------------------------
--
-- MONO
--

--   Kernel:  {{1,2,1},{2,4,2}, [1,2,1}} / 16

local mono = lg.newShader [[
  #pragma language glsl3
  
  uniform float ratio;
  
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
    vec2 texelSize = 1.0 / vec2(textureSize(tex, 0));     // 0 is mipmap level
      
      vec2 dx = vec2(texelSize.x, 0.0);
      vec2 dy = vec2(0.0, texelSize.y);
  
      vec2 y;
      float c;                  // central pixel value
      float p;                  // pixel value
      float g;                  // 'Gaussian' filtered pixel
      float a;                  // average value of adjacent pixels
      
      float r = ratio / 2;
      
      y = tc;
      p = Texel(tex, tc) .r;        g = 4.0 * p; a = 0.0; c = p;
      p = Texel(tex, y + dx) .r;    g += p + p ; a += p;
      p = Texel(tex, y - dx) .r;    g += p + p ; a += p;
      
      y = tc + dy;
      p = Texel(tex, y     ) .r;    g += p + p ; a += p;
      p = Texel(tex, y + dx) .r;    g += p ;     a += p;
      p = Texel(tex, y - dx) .r;    g += p ;     a += p;
      
      y = tc - dy;
      p = Texel(tex, y     ) .r;    g += p + p ; a += p;
      p = Texel(tex, y + dx) .r;    g += p ;     a += p;
      p = Texel(tex, y - dx) .r;    g += p ;     a += p;
      
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
  #pragma language glsl3
  
  uniform float ratio;
  
  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
      vec2 texelSize = 2.0 / vec2(textureSize(tex, 0));    // step over two pixels (Bayer pattern repeat)
      
      vec2 Dx = vec2(texelSize.x, 0.0);
      vec2 Dy = vec2(0.0, texelSize.y);
      
      float c = Texel(tex, tc) .r;
      float d = 0.0;
      d += Texel(tex, tc + Dx) .r;
      d += Texel(tex, tc - Dx) .r;
      d += Texel(tex, tc + Dy) .r;
      d += Texel(tex, tc - Dy) .r;
      d = d / 4.0;
      
      return vec4(c > ratio * d ? d : c, 0.0, 0.0, 1.0);
  }
]]


local function badPixelRemoval(workflow, bayerpat, ratio)

  local hasBayer = (bayerpat or ''): match "[RGB][RGB][RGB][RGB]"
  
  workflow: shadeWith(hasBayer and rgb or mono, {ratio =  ratio});
      
  _log("hot pixel removal [%s]"  % (hasBayer and bayerpat or "MONO"))
  
end


return badPixelRemoval

-----
