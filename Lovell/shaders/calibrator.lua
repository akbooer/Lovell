--
-- calibrator.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "apply darks and flats",
  }

local _log = require "logger" (_M)


-- 2025.04.14  Version 0

local newTimer = require "utils" .newTimer


local love = _G.love
local lg = require "love.graphics"


-------------------------
--
-- DARKS and FLATS
--

local calibrate = lg.newShader [[

    // Pixel Shader
    
    uniform bool do_dark, do_flat;
    uniform Image Idark, Iflat;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      float pixel = Texel(texture, tc ) .r;
      float black = Texel(Idark, tc ) .r;
      float white = Texel(Iflat, tc ) .r;
      pixel = do_dark ? pixel - black : pixel;
      pixel = do_flat ? pixel / min(white, 0.01) : pixel;
      return vec4(clamp(pixel, 0.0, 1.0), 0.0, 0.0, 1.0);
    }


]]

function _M.calibrate(workflow)
  local elapsed = newTimer()
  
  local dark, flat = workflow.dark, workflow.flat

  if true or dark or flat then
    local input, output = workflow()
    lg.setShader(calibrate)
    calibrate: send("do_dark", not not dark)
    calibrate: send("do_flat", not not flat)
    calibrate: send("Idark", dark or input)
    calibrate: send("Iflat", flat or input)
    output: renderTo(lg.draw, input)
    lg.reset()
  end
 
  _log(elapsed "%.3f ms,", dark and "DARK" or '', flat and "FLAT" or '')

end



return _M

-----
