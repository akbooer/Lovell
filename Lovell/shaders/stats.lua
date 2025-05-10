--
-- stats.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.02",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry statistical calculations in images using SHADERS",
  }

-- 2024.10.21  Version 0
-- 2024.11.16  use shader to calculate min, max, mean, standard deviation
-- 2024.11.17  avoid negative square root in standard deviation (due to rounding errors)

-- 2025.03.17  add offset()
-- 2025.03.19  add shader to calculate min, max, mean, var... much, much faster than mapPixel() (100µs vs 50 ms)
-- 2025.03.25  revert to non-Texel based stats (Issue #1, broken on PCs, thanks @Songwired)
-- 2025.05.02  add calc(), add RGBA stats


local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local lg = require "love.graphics"
local li = require "love.image"

--
local oneD  = lg.newCanvas(2,2)    -- just a dummy to start with
local twoD  = lg.newCanvas(2,2)
  
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


-- columns calculates min(x), max(x), mean(x), var(x) for then final row
local collectRow = lg.newShader [[
  uniform float N, step;
  uniform Image image;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float min = 1.0e6, max = -1.0e6, sum = 0.0, sum2 = 0.0;
    float mean, var;
    for (float i = 0.0; i < 1.0; i += step)
    {
      vec4 x = Texel(image, vec2(i, tc.y));
      min = x.x < min ? x.x : min;
      max = x.y > max ? x.y : max;
      sum  += x.z;
      sum2 += x.a;
    }
    mean = sum / N;
    var = sum2 / N - mean * mean;
    var = var > 0 ? var : 0.0;
    return vec4(min, max, mean, var);
  }
]]

--]=]

 
function _M.statsTexel(image, channel)
  local w, h = image: getDimensions()  
  local bw = oneD: getWidth()
  if bw ~= w then
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})   -- maximum precision for accumulators
    twoD = lg.newCanvas(w, 1, {dpiscale = 1, format = "r8"})        -- minimal storage, only used for dimensions
  end
  
  lg.setShader(columns)
  columns: send("h", h)
  columns: send("image", image)
  columns: send("channel", channel)
  lg.setBlendMode("replace", "premultiplied")
  oneD: renderTo(lg.draw, twoD)

  -- combine the min(x), max(x), sum(x), sum(x^2) column subtotals
  lg.setShader(collectRow)
  collectRow: send("N", w * h)
  collectRow: send("step", 1 / w)
  collectRow: send("image", oneD)
  
  local zeroD = lg.newCanvas(1,1, {dpiscale = 1, format = "rgba32f"})   -- for results {min, max, mean, var}
  zeroD: renderTo(lg.draw, oneD)
  lg.setBlendMode("alpha", "alphamultiply")
  lg.setShader()
  
  return zeroD
end

local function getChannelStatsTexel(image, channel)
  local zeroD = _M.statsTexel(image, channel)
  local d0 = zeroD: newImageData()
  local min, max, mean, var = d0: getPixel(0, 0)
  return {min, max, mean, var > 0 and math.sqrt(var) or 0}  -- avoid square root of negative due to rounding errors
end


-- returns min, max, mean, standard deviation of RGB in input image
function _M.statsXXX(image, log_results)
  local elapsed = newTimer()
  
  local red, green, blue
  red   = getChannelStatsTexel(image, 0)
  green = getChannelStatsTexel(image, 1)
  blue  = getChannelStatsTexel(image, 2)
  
  local min, max, mean, sdev
  min  = {red[1], green[1], blue[1]}
  max  = {red[2], green[2], blue[2]}
  mean = {red[3], green[3], blue[3]}
  sdev = {red[4], green[4], blue[4]}
          
  if log_results then
    _log(elapsed "%.3f ms, results...")
    _log("RGB min: %6.3e, %6.3e, %6.3e" % min) 
    _log("RGB max: %6.3e, %6.3e, %6.3e" % max) 
    _log("RGB avg: %6.3e, %6.3e, %6.3e" % mean) 
    _log("RGB std: %6.3e, %6.3e, %6.3e" % sdev) 
  end
  
  return {min = min, max = max, mean = mean, sdev = sdev}
end

  
-------------------------------
--
-- NORMALISATION
--

local normaliseTexel = lg.newShader [[
  uniform Image, red, green, blue;
  const float eps = 1.0e-6;
  const vec2 xy = vec2(0);
  
  vec4 r = Texel(red, xy);
  vec4 g = Texel(green, xy);
  vec4 b = Texel(blue, xy);
  
  float r_min = r.x, r_max = r.y, r_avg = r.z, r_var = r.a;
  float g_min = g.x, g_max = g.y, g_avg = g.z, g_var = g.a;
  float b_min = b.x, b_max = b.y, b_avg = b.z, b_var = b.a;
  
  float rgb_min = float(min(r_min, min(g_min, b_min)));
  float rgb_max = float(max(r_max, max(g_max, b_max)));
  vec3 rgb_avg = vec3(r_avg, g_avg, b_avg);
  vec3 rgb_var = vec3(r_var, g_var, b_var);
  
  float min_var = min(r_var, min(g_var, b_var));
  float scale = 1.0 / (rgb_max - rgb_min + eps);
    
  vec4 effect(vec4 color, Image image, vec2 tc, vec2 _) {
    vec3 rgb = Texel(image, tc) .rgb;
    return vec4((rgb - rgb_min) * scale, 1.0);

  }
]]

-- normalise range 0..1 
function _M.normaliseTexel(workflow)
  local input, output = workflow()      -- get hold of the workflow buffers
  
  local red, green, blue
  red   = _M.statsTexel(input, 0)
  green = _M.statsTexel(input, 1)
  blue  = _M.statsTexel(input, 2)

  local shader = normaliseTexel
  shader: send("red", red)
  shader: send("green", green)
  shader: send("blue", blue)
  lg.setShader(shader)
  output: renderTo(lg.draw, input)
  lg.setShader()
end
  
-------------------------------
--
-- LEGACY VERSIONS
--
 

 
local function getChannelStats(image, channel)
  local w, h = image: getDimensions()
  local n = w * h
  
  local bw = oneD: getWidth()
  if bw ~= w then
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})   -- maximum precision for accumulators
    twoD = lg.newCanvas(w, 1, {dpiscale = 1, format = "r8"})        -- minimal storage, only used for dimensions
  end
  
  lg.setShader(columns)
  columns: send("h", h)
  columns: send("image", image)
  columns: send("channel", channel)
  lg.setBlendMode("replace", "premultiplied")
  oneD: renderTo(lg.draw, twoD)
--  lg.setBlendMode("alpha", "alphamultiply")

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
  
  lg.reset()
  local mean = sum / n
  local var = sum2 / n - mean * mean
  return {min, max, mean, var > 0 and math.sqrt(var) or 0}  -- avoid square root of negative due to rounding errors
end
 

-- returns min, max, mean, standard deviation of RGB in input image
function _M.stats(image, log_results)
  local elapsed = newTimer()
  
  local red, green, blue, alpha
  red   = getChannelStats(image, 0)
  green = getChannelStats(image, 1)
  blue  = getChannelStats(image, 2)
  alpha = getChannelStats(image, 3)
  
  local min, max, mean, sdev
  min  = {red[1], green[1], blue[1], alpha[1]}
  max  = {red[2], green[2], blue[2], alpha[2]}
  mean = {red[3], green[3], blue[3], alpha[3]}
  sdev = {red[4], green[4], blue[4], alpha[4]}
          
  if log_results then
    _log(elapsed "%.3f ms, results...")
    _log("RGBA min: %6.3e, %6.3e, %6.3e, %6.3e" % min) 
    _log("RGBA max: %6.3e, %6.3e, %6.3e, %6.3e" % max) 
    _log("RGBA avg: %6.3e, %6.3e, %6.3e, %6.3e" % mean) 
    _log("RGBA std: %6.3e, %6.3e, %6.3e, %6.3e" % sdev) 
  end
  
  return {min = min, max = max, mean = mean, sdev = sdev}
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

-- nomalize RGB, collectively, to be between 0 and 1
-- use input reference image, if present, for stats, otherwise input buffer
function _M.normalise(workflow, reference, Max)
  local input, output = workflow()      -- get hold of the workflow buffers
  local stats = _M.stats(reference or input)
  local eps = 1.0e-10
  local max, min = stats.max, stats.min
  local rgb_max = math.max(math.max(max[1], max[2]),max[3])
  local rgb_min = math.min(math.min(min[1], min[2]),min[3])
  local scale = (Max or 1) / (rgb_max - rgb_min + eps)                 -- avoid division by zero
  normalise: send("min", rgb_min)
  normalise: send("scale", scale)
  lg.setShader(normalise)
  output: renderTo(lg.draw, input)
  lg.setShader()
end
  
  
-------------------------------
--
-- LOGISTIC function
--

local logistic = lg.newShader [[

  vec4 effect(vec4 color, Image image, vec2 tc, vec2 _) {
    vec3 rgb = Texel(image, tc) .rgb;
    vec3 new = 1 / 1 + exp(-4 * (rgb - 0.5));
    return vec4(new, 1.0);
  }
]]

-- maps resultant to be between 0 and 1
function _M.logistic(workflow)
  local input, output = workflow()
  lg.setShader(logistic)
  output: renderTo(lg.draw, input)
  lg.setShader()
end
  

-------------------------------
--
-- CALC, incremental stats calculator
--

function _M.calc()
  local min, max
  local sum, sum2, n = 0, 0, 0
  return function(x)
    n = n + 1
    sum  = sum  + x
    sum2 = sum2 + x * x
    min = x < (min or x + 1) and x or min
    max = x > (max or x - 1) and x or max
  
    n = n > 0 and n or 1
    local mean = sum / n
    local var = sum2 / n - mean * mean
    
    return min, max, mean, var
  end
end


-------------------------------
--
-- TESTING
--

function _M.TEST(N)
  
  -- create test image
  
  N = N or 9
  _log ''
 _log "Stats test"
  local x = li.newImageData(N, N, "rgba16f")

  local t = {}
  local random = math.random
  local min, max, sum, sum2 = math.huge, 0, 0, 0
  x: mapPixel(function(x,y, r,g,b)
    r = random(10)
    g = random(20)
    b = random(30)
    r = r - r % 0.001
    g = g - g % 0.001
    b = b - b % 0.001
    x, y = x+1, y+1
    t[y] = t[y] or {}
    t[y][x] = r
    sum = sum + r
    sum2 = sum2 + r * r
    min = r < min and r or min
    max = r > max and r or max
    return r,g,b,1
  end)

--  for _, row in ipairs(t) do
--    _log("%.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f, %.3f" % row)
--  end
  local M = N * N
  local avg = sum / M
  local var = sum2 / M - avg * avg
  
  _log("min, max, avg, sdev: %.4f, %.4f, %.4f, %.4f" % {min, max, avg, math.sqrt(var)})
  local temp = lg.newImage(x, {dpiscale = 1})
  temp: setFilter("nearest", "nearest")
  local itest = lg.newCanvas (N,N, {dpiscale=1, format = "rgba16f"})
  itest: setFilter("nearest", "nearest")
  itest: renderTo(lg.draw, temp)
  
  local s = _M.stats(itest)
  _log(pretty(s))
end

--_M.TEST()

return _M

-----
