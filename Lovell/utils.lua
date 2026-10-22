--
-- utils.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.16",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry utilities",
  }

-- 2024.10.29  Version 0

-- 2025.01.28  separate workflow into its own module
-- 2025.02.27  add extra format functions

-- 2026.03.29  tidy up getDimensions()
-- 2026.06.09  add alphanumeric_sort()
-- 2026.10.12  add sorted() iterator
-- 2026.10.16  use math.degrees()


local _log = require "logger" (_M)

local lg = require "love.graphics"
local lt = require "love.timer"

local floor = math.floor


-------------------------
--
-- TIMING and PROFILING 
--

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

do -- PROFILER utility
  
  local index = {}
  local meta = {__index = index}
  
  function index: add(name, deltaT)
    if deltaT < self._threshold then return end
    local p = self[name] 
    if not p then -- ignore first call (because you're probably timing the JIT compiler)
      self[name] = {calls = 0, time = 0}
      return 
    end
    p.calls = p.calls + 1
    p.time = p.time + deltaT
  end
  
  function index: report()
    local r =  {'', '', "      name    #calls   time(s)  per call(ms)"}
    local fmt = "%12s  %4d   %8.3f    %0.3f"
    for name, p in _M.sorted(self) do
      if name ~= "_threshold" and p.calls > 0 then 
        r[#r+1] = (fmt % {name, p.calls, p.time, 1000 * p.time/p.calls})
      end
    end
    r[#r+1] = ''
    return table.concat(r, '\n')
  end
  
  function _M.profiler(thold)    -- ignore any single call under threshold
    return setmetatable({_threshold = thold or 0}, meta)
  end
    
end

-------------------------
--
-- SCREEN 
--

-- get dimensions of screen or canvas
function _M.getDimensions(screen)
    return (screen or lg):getDimensions()
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
-- SORTING
--

-- to get things like "Messier 51" into correct order
function _M.alphanumeric_sort(a,b)
  local a1, a2 = a: match "(%D+)%s*(%d*)"
  local b1, b2 = b: match "(%D+)%s*(%d*)"
  if a1 < b1 then return true end
  a2 = tonumber(a2) or 0 
  b2 = tonumber(b2) or 0
  if a1 == b1 then return a2 < b2 end
  return false
end


-- sorted version of the pairs iterator
-- use like this:  for a,b in sorted (x, fct) do ... end
-- optional second parameter is sort function cf. table.sort
function _M.sorted (x, fct)
  local y, i = {}, 0
  for z in pairs(x) do y[#y+1] = z end
  table.sort (y, fct) 
  return function ()
    i = i + 1
    local z = y[i]
    return z, x[z]  -- if z is nil, then x[z] is nil, and loop terminates
  end
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
  -- don't round up as 59.6 seconds will be shown as 60!
  s = floor(60 * (m % 1))
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

-- convert seconds to sensible number with units
function _M.formatSeconds(t)
  t = tonumber(t)
  if not t then return '' end
  local scale, unit = 1, 's'
  if t < 1e-3 then
    scale, unit = 1e6, 'µs'
  elseif t < 1 then
    scale, unit = 1e3, 'ms'
--  elseif
--    t >= 60 then
--    return os.date("%M:%S", t)
  end
  return string.format("%.0f %s", t * scale, unit)
end

-- return degrees / minutes / seconds of input angle (in arc seconds)
function _M.formatAngle(x)
  local hhmm = os.date([[!%Hº %M']], x + 30)    -- round to nearest minute
  hhmm = hhmm: gsub("0(%d)", "%1")              -- remove leading zeros
  return hhmm
end

-- return degrees given radians
do 
  local fmt = {}      -- cache for format strings
  
  function _M.formatDegrees(x, dp)
    dp = math.floor(dp or 0)                              -- decimal places
    fmt[dp] = fmt[dp] or string.format ("%%0.%dfº", dp)   -- build format if needed
    return string.format (fmt[dp], math.degrees(x))
  end
end

-- seconds to mm:ss
function _M.formatHM(x)
  if not x or x == '' then
    return ''
  end
  local h, m
  h = floor(x)
  m = (x - h) * 60
  return string.format("%2d:%02d", h, m)
end

-- convert minutes or arc to sensible format º or ' or "
function _M.formatArcMinutes(d)
  d = tonumber(d)
  if not d or d == 0 then return '' end
  if d < 1 then
    return '%4.1f"' % (d * 60)
  elseif d < 100 then
    return "%4.1f'" % d
  else
    return "%.1fº" % (d / 60)
  end
end


return _M

-----
