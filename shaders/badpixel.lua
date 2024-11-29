--
-- badpixel handling
--

local _M = {
    NAME = ...,
    VERSION = "2024.10.17",
    AUTHOR = "AK Booer",
    DESCRIPTION = "hot pixel removal",
  }

--[[

  Works for both mono and Bayer images, using adjacent pixels of the same colour.
  Pixel replaced by adjacent pixel average if value exceeds some ratio of  that average.
  
--]]

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

-- 2024.10.17  @akbooer
--

local love = _G.love
local lg = love.graphics


local hotPixelRemoval = lg.newShader [[
  uniform float ratio;
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
      vec2 dx = vec2(2.0 / love_ScreenSize.x, 0.0);
      vec2 dy = vec2(0.0, 2.0 / love_ScreenSize.x);
      float c = Texel(texture, tc) .r;
      float d = 0;
      d += Texel(texture, tc + dx) .r;
      d += Texel(texture, tc - dx) .r;
      d += Texel(texture, tc + dy) .r;
      d += Texel(texture, tc - dy) .r;
      d = d / 4.0;
//      return c > ratio * d ? vec4(c, 0.0, 0.0, 1.0) : vec4(0.0, 0.0, 0.0, 1.0);   // 'hot' pixels only
      return c > ratio * d ? vec4(d, 0.0, 0.0, 1.0) : vec4(c, 0.0, 0.0, 1.0);
  }
]]

local ratio = 1.5     -- comparison threshold

local function badPixelRemoval(input, output, params)
  if type(params) == "table" then
    ratio = params.ratio or ratio
  end

  local elapsed = newTimer()
  hotPixelRemoval: send("ratio", ratio);
  
  lg.setShader(hotPixelRemoval) 
  output:renderTo(lg.draw, input)
  lg.setShader()
      
  _log(elapsed "%.3f ms, hotPixelRemoval")
  
end

return badPixelRemoval

-----
