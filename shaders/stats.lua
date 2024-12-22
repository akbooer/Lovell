--
-- stats.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.17",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry statistical calculations in images using SHADERS",
  }

-- 2024.10.21  Version 0
-- 2024.11.16  use shader to calculate min, max, mean, standard deviation
-- 2024.11.17  avoid negative square root in standard deviation (due to rounding errors)


local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local lg = require "love.graphics"
local li = require "love.image"

--
local oneD = lg.newCanvas(2,2)    -- just a dummy to start with
local twoD = lg.newCanvas(2,2)

  
-------------------------------
--
-- STATISTICS
--

-- columns calculates min(x), max(x), sum(x), sum(x^2) for each column of given layer [0-2] = r,g,b
local columns = lg.newShader [[
  uniform float h;
  uniform int channel;
  uniform Image image;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float min = 1.0e6, max = -1.0e6, sum = 0.0, sum2 = 0.0;
    for (float i = 0.0; i < h; i += 1.0)
    {
    float foo = channel;
      float x = Texel(image, vec2(tc.x, i / h)) [channel];    // select channel of interest
      min = x < min ? x : min;
      max = x > max ? x : max;
      sum  += x;
      sum2 += x * x;
    }
    return vec4(min, max, sum, sum2);
  }
]]

local function getChannelStats(channel)
    columns: send("channel", channel)
    local w = oneD: getWidth()
    lg.setBlendMode("replace", "premultiplied")
    oneD: renderTo(lg.draw, twoD)
--    oneD: renderTo(lg.line, 0.5, 0.5, w - 0.5, 0.5)
    lg.setBlendMode("alpha", "alphamultiply")

    -- combine the min(x), max(x), sum(x), sum(x^2) column subtotals
    local d1 = oneD: newImageData()
    local min, max, sum, sum2 = 1e6, -1e6, 0, 0
    d1: mapPixel(function(_,_, ...)   -- first two are (x,y) coordinates
      local r,g,b,a = ...
      min = r < min and r or min
      max = g > max and g or max
      sum  = sum  + b
      sum2 = sum2 + a
      return ...
    end)
  
    return {min, max, sum, sum2}
  end
 
-- avoid square root of negative number due to rounding errors
local function sqrt(x)
  return x > 0 and math.sqrt(x) or 0
end

-- returns min, max, mean, standard deviation of RGB in input image
function _M.stats(image, log)
  local elapsed = newTimer()
  
  local w, h = image: getDimensions()
  local bw = oneD: getWidth()
  if bw ~= w then
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})   -- maximum precision for accumulators
    twoD = lg.newCanvas(w, 1, {dpiscale = 1, format = "r8"})        -- minimal storage, only used for dimensions
  end
  
  local red, green, blue
  do
    lg.setShader(columns)
    columns: send("h", h)
    columns: send("image", image)
    red   = getChannelStats(0)
    green = getChannelStats(1)
    blue  = getChannelStats(2)
    lg.setShader()
  end
  
  local min = {red[1], blue[1], green[1]}
  local max = {red[2], blue[2], green[2]}
  
  local n = w * h
  local mean = {red[3]/n, blue[3]/n, green[3]/n}
  
  local sdev = { 
                  sqrt(  red[4] / n - mean[1]  * mean[1]),
                  sqrt(green[4] / n - mean[2]  * mean[2]),
                  sqrt( blue[4] / n - mean[3]  * mean[3]),
                }
  if log then
    _log(elapsed "%.3f ms, results...")
    _log("RGB min: %6.3f, %6.3f, %6.3f" % min) 
    _log("RGB max: %6.3f, %6.3f, %6.3f" % max) 
    _log("RGB avg: %6.3f, %6.3f, %6.3f" % mean) 
    _log("RGB std: %6.3f, %6.3f, %6.3f" % sdev) 
  end
  
  return {min = min, max=max, mean=mean, sdev = sdev}
end

  
-------------------------------
--
-- NORMALISATION
--

local normalise = lg.newShader [[
  uniform float min, scale;
  
  vec4 effect(vec4 color, Image image, vec2 tc, vec2 _) {
    vec3 rgb = Texel(image, tc) .rgb;
    return vec4((rgb - vec3(min)) * scale, 1.0);
  }
]]

---- nomalize RGB, collectively, to be between 0 and 1
function _M.normalise(workflow)
  local input, output = workflow()      -- get hold of the workflow buffers
  local stats = _M.stats(input);
  local eps = 1.0e-10
  local max, min = stats.max, stats.min
  local rgb_max = math.max(math.max(max[1], max[2]),max[3])
  local rgb_min = math.min(math.min(min[1], min[2]),min[3])
  local scale = 1 / (rgb_max - rgb_min + eps)                 -- avoid division by zero
  normalise: send("min", rgb_min)
  normalise: send("scale", scale)
  lg.setShader(normalise)
  output: renderTo(lg.draw, input)
  lg.setShader()
end
  
-------------------------------
--
-- TESTING
--

function _M.test(N)
  
  -- create test image
  
  N = N or 9
 _log "Stats test"
  local x = li.newImageData(N, N, "rgba16f")

  local t = {}
  local random = math.random
  x: mapPixel(function(x,y, r,g,b)
    r = random()
    g = random()
    b = random()
    r = r - r % 0.001
    g = g - g % 0.001
    b = b - b % 0.001
    x, y = x+1, y+1
    t[y] = t[y] or {}
    t[y][x] = r
    return r,g,b,1
  end)

--  for _, row in ipairs(t) do
--    print("%.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f" % row)
--  end

  local temp = lg.newImage(x, {dpiscale = 1})
  temp: setFilter("nearest", "nearest")
  local itest = lg.newCanvas (N,N, {dpiscale=1, format = "rgba16f"})
  itest: setFilter("nearest", "nearest")
  itest: renderTo(lg.draw, temp)
  
  _M.stats(itest)
  
end

--_M.test()

return _M

-----
