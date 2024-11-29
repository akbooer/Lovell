--
-- smoother – 3x3 shader
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.07",
    AUTHOR = "AK Booer",
    DESCRIPTION = "3x3 box smoother",
  }

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

-- 2024.11.07  @akbooer
--

local love = _G.love
local lg = love.graphics


local smooth3x3 = lg.newShader [[
  uniform vec2 dx;
  uniform vec2 dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
  
      vec2 y = tc;
      vec4 d = vec4(0.0);
      
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      y = tc + dy;
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      y = tc - dy;
      d += Texel(texture, y     );
      d += Texel(texture, y + dx);
      d += Texel(texture, y - dx);
      
      return d / 9.0;
  }
]]


local function smooth(input, output)
  
  local w, h = input: getDimensions()
  smooth3x3: send("dx", {1 / w, 0})
  smooth3x3: send("dy", {0, 1 / h})
  
  lg.setShader(smooth3x3) 
  output:renderTo(lg.draw, input)
  lg.setShader()
  
end

return smooth

-----
