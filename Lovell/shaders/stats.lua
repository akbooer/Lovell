--
-- stats.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.17",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry statistical calculations in images using SHADERS",
  }

-- 2024.10.21  Version 0
-- 2024.11.16  use shader to calculate min, max, mean, standard deviation
-- 2024.11.17  avoid negative square root in standard deviation (due to rounding errors)

-- 2025.03.17  added offset()
-- 2025.03.19  added shader to calculate min, max, mean, var... much, much faster than mapPixel() (100µs vs 50 ms)


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

local function getChannelStats(image, channel)
  local zeroD = _M.statsTexel(image, channel)
  local d0 = zeroD: newImageData()
  local min, max, mean, var = d0: getPixel(0, 0)
  return {min, max, mean, var > 0 and math.sqrt(var) or 0}  -- avoid square root of negative due to rounding errors
end


-- returns min, max, mean, standard deviation of RGB in input image
function _M.stats(image, log_results)
  local elapsed = newTimer()
  
  local red, green, blue
  red   = getChannelStats(image, 0)
  green = getChannelStats(image, 1)
  blue  = getChannelStats(image, 2)
  
  local min, max, mean, sdev
  min  = {red[1], green[1], blue[1]}
  max  = {red[2], green[2], blue[2]}
  mean = {red[3], green[3], blue[3]}
  sdev = {red[4], green[4], blue[4]}
          
  if log_results then
    _log(elapsed "%.3f ms, results...")
    _log("RGB min: %6.3f, %6.3f, %6.3f" % min) 
    _log("RGB max: %6.3f, %6.3f, %6.3f" % max) 
    _log("RGB avg: %6.3f, %6.3f, %6.3f" % mean) 
    _log("RGB std: %6.3f, %6.3f, %6.3f" % sdev) 
  end
  
  return {min = min, max = max, mean = mean, sdev = sdev}
end

  
-------------------------------
--
-- NORMALISATION
--

local normalise = lg.newShader [[
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

-- offset RGB, 
function _M.normalise(workflow)
  local input, output = workflow()      -- get hold of the workflow buffers
  
  local red, green, blue
  red   = _M.statsTexel(input, 0)
  green = _M.statsTexel(input, 1)
  blue  = _M.statsTexel(input, 2)

  local shader = normalise
  shader: send("red", red)
  shader: send("green", green)
  shader: send("blue", blue)
  lg.setShader(shader)
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

--_M.test()

return _M

-----
