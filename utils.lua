--
-- utils.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.10.29",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry utilities",
  }

local _log = require "logger" (_M)

local lt = require "love.timer"
local lg = require "love.graphics"

-- newTimer, returns a function which gives time (in ms) since its creation
-- returned function can be called multiple times, for cumulative timings
--
-- local elapsed = timer()
-- do something end
-- local t = elapsed()
--
-- optional formatting parameter for string return
-- optional parameters for formatting AFTER the time
function _M.newTimer()
  local gt = lt.getTime
  local t = gt()
  return function(fmt, ...) 
    local dt = 1000 * (gt() - t) 
    return fmt and fmt % {dt, ...} or dt
  end
end

-- buffer
--
local function getInfo(image)
  local width, height = image:getDimensions()
  local dpiscale= image: getDPIScale()
  local imageFormat = image:getFormat()
  return width, height, imageFormat, dpiscale
end
  
-- ensure buffer, if it exists, is the right size for image
-- otherwise create and return one that matches
-- settings, if present, overrides selected image settings
function _M.buffer(image, buffer, settings)
  local w1, h1, f1, d1 = getInfo(image)
  settings = setmetatable(settings or {}, {__index = {format = f1, dpiscale = d1}})
  if buffer then
    local w2, h2 = getInfo(buffer)
    if w2 ~= w1 or h2 ~= h1 then
      buffer = nil
    end
  end
  return buffer or lg.newCanvas(w1, h1, settings)
end

return _M

-----
