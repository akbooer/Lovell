--
-- badpixel handling
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.23",
    AUTHOR = "AK Booer",
    DESCRIPTION = "hot pixel removal",
  }

--[[

  Works for both mono and Bayer images, using adjacent pixels of the same colour.
  Pixel replaced by adjacent pixel average if value exceeds some ratio of that average.
  
--]]

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

-- 2024.10.17  @akbooer
-- 2024.12.23  use controls.workflow.badratio.value, add mono shader


local love = _G.love
local lg = love.graphics


local mono = lg.newShader [[
  uniform float ratio;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  
      vec2 y = tc;
      float c = Texel(texture, tc) .r;
      
      float d = 0.0;                  // don't include the pixel itself in the average
      d += Texel(texture, y + dx) .r;
      d += Texel(texture, y - dx) .r;
      
      y = tc + dy;
      d += Texel(texture, y     ) .r;
      d += Texel(texture, y + dx) .r;
      d += Texel(texture, y - dx) .r;
      
      y = tc - dy;
      d += Texel(texture, y     ) .r;
      d += Texel(texture, y + dx) .r;
      d += Texel(texture, y - dx) .r;
      
      d = d / 8.0;
      return vec4(c > ratio * d ? d : c, 0.0, 0.0, 1.0);
  }
]]


local rgb = lg.newShader [[
  uniform float ratio;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
      
      float c = Texel(texture, tc) .r;
      float d = 0.0;
      d += Texel(texture, tc + dx) .r;
      d += Texel(texture, tc - dx) .r;
      d += Texel(texture, tc + dy) .r;
      d += Texel(texture, tc - dy) .r;
      d = d / 4.0;
      return vec4(c > ratio * d ? d : c, 0.0, 0.0, 1.0);
  }
]]

local function badPixelRemoval(input, output, controls)
  local elapsed = newTimer()
    
  local shader = rgb
  local step = 2    -- TODO: change to 1 for mono
  local w, h = input: getDimensions()
  shader: send("dx", {step / (w - 1), 0})
  shader: send("dy", {0, step / (h - 1)})
  
  local wk = controls.workflow
  local ratio = wk.badpixel.checked and wk.badratio.value or 1e6   -- turn it on/off
  rgb: send("ratio", ratio);
  
  lg.setShader(shader) 
  output:renderTo(lg.draw, input)
  lg.setShader()
      
  _log(elapsed "%.3f ms, hotPixelRemoval")
  
end

return badPixelRemoval

-----
