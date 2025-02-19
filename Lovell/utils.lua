--
-- utils.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.28",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry utilities",
  }

-- 2024.10.29  Version 0

-- 2025.01.28  separate workflow into its own module


local _log = require "logger" (_M)

local lt = require "love.timer"
local lg = require "love.graphics"

local floor = math.floor

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

-------------------------
--
-- SCREEN 
--

-- get dimensions of screen or canvas
function _M.getDimensions(screen)
  if screen then 
    return screen:getDimensions()
  else
    return lg.getDimensions()
  end
end

-- calculate vertical and horizontal ratios of image and screen dimensions
function _M.calcScreenRatios(image, screen)
  if not image then return 1, 1 end
  local w,h = _M.getDimensions(screen)
  local iw,ih = image:getDimensions()
  return w / iw, h / ih
end


-------------------------
--
-- FORMATTING
--

-- convert decimal degrees to DDD MM SS
local function deg_to_dms(deg)
  local sign = 1
  if deg < 0 then
    sign = -1
    deg = -deg
  end
  local d, m, s
  d = floor(deg)
  m = 60 * (deg - d)
  s = floor(60 * (m % 1) + 0.5)
  m = floor(m)
  return sign * d, m, s
end

-- convert decimal RA to HH MM SS
function _M.formatRA(RA)
  local ra = tonumber(RA)
  return ra and string.format ("%02dh %02d %02d", deg_to_dms(ra / 15)) or RA
end

-- convert decimal DEC to ±DDº MM SS
function _M.formatDEC(DEC)
  local dec = tonumber(DEC)
  return dec and string.format("%+02dº %02d %02d", deg_to_dms(dec)) or DEC
end


return _M

-----
