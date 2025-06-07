--
-- calibrator.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.06.07",
    AUTHOR = "AK Booer",
    DESCRIPTION = "apply darks and flats",
  }

local _log = require "logger" (_M)


-- 2025.04.14  Version 0
-- 2025.05.27  load masters on demand
-- 2025.05.28  add scaling factor for flats


local masters   = require "databases.masters"
local newTimer  = require "utils" .newTimer


local love = _G.love
local lg = love.graphics


-------------------------
--
-- DARKS and FLATS
--

local calibrate = lg.newShader [[

    // Pixel Shader
    
    uniform float scale;
    uniform bool do_dark, do_flat;
    uniform Image Idark, Iflat;
    
    vec4 effect( vec4 color, Image texture, vec2 tc, vec2 _ ){
      float pixel = Texel(texture, tc ) .r;
      float black = do_dark ? Texel(Idark, tc ) .r : 0.0;
      float white = do_flat ? Texel(Iflat, tc ) .r : 1.0;
      pixel = scale * (pixel - black) / max(white, 0.01);
      return vec4(pixel, 0.0, 0.0, 1.0);
    }


]]

local midpoint                                      -- for scaling flats
local bias, dark, flat                              -- master canvases
local current_bias, current_dark, current_flat      -- master catalogue entries

function _M.calibrate(workflow, frame)
  local elapsed = newTimer()
  local controls = workflow.controls
  local w = controls.workflow
  local do_dark, do_flat = w.do_dark.checked, w.do_flat.checked
  
  if frame.first then
    _log "clearing masters"
    masters.clear()
    current_dark = nil
    current_flat = nil
    bias = nil
    dark = nil
    flat = nil
  end
  
  if do_dark or do_flat then
    local b, d, f = masters.search(frame)    -- get catalogue entries for matching bias / dark / flat
    if do_dark and d ~= current_dark then
      dark = masters.read(d)
      current_dark = d
    end
    if do_flat and f ~= current_flat then
      flat, midpoint = masters.read(f)
      current_flat = f
    else 
      midpoint = 1
    end
  end

  frame.dark_calibration = not not dark
  frame.flat_calibration = not not flat
    
  if dark or flat then
    local input, output = workflow()
    lg.setShader(calibrate)
    lg.setBlendMode("replace", "premultiplied")
    calibrate: send("do_dark", frame.dark_calibration)
    calibrate: send("do_flat", frame.flat_calibration)
    calibrate: send("Idark", dark or input)
    calibrate: send("Iflat", flat or input)
    calibrate: send("scale", 0.5 / midpoint)    -- scaling factor for flat
    output: renderTo(lg.draw, input)
    lg.reset()
    _log(elapsed "%.3f ms,", dark and "DARK" or '', flat and "FLAT" or '')
  end
 
end


return _M

-----
