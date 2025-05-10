--
-- starfinder.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.04.30",
  AUTHOR = "AK Booer",
  DESCRIPTION = "star detection",
}

-- 2024.10.28  Version 0
-- 2024.11.18  replace findPeaks() with findPeaksUsingShader()
-- 2024.11.25  return only largest peak found in each column (thanks @Martin Meredith for test data)
-- 2024.11.26  add pixel margin to aoid finding peaks at the image edge

-- 2025.01.28  add DoG (Difference of Gaussians)
-- 2025.02.06  use workflow buffers rather than internal monochrome ones
-- 2025.03.09  abandon DoG, use mean-relative threshold
-- 2025.04.18  Issue #13, use FWHM-related metric to discriminate against hot pixels
-- 2025.05.02  remove Texelstats and simplify finder shader


local _log = require "logger" (_M)

local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics

local oneD = lg.newCanvas(1,1)      -- just a dummy to start with


-- calculates maximum pixel in a 1-D sliding window
-- applied once in each direction for 2-D solution
local maxShader = lg.newShader [[
  uniform vec2 direction;
  uniform int radius;
  uniform int channel;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float c = 0.0;
    for (float i = -radius; i <= radius; i += 1.0)
    {
      c = max (c, Texel(texture, tc + i * direction) [channel]);
    }
    return vec4(c, c, c, 1.0);
  }
]]

local function maxchan(canvas, direction, radius, channel)
  channel = channel or 0        -- default to red channel
  maxShader:send("channel", channel)
  maxShader:send("direction", direction)
  maxShader:send("radius", math.floor(radius))
  lg.setShader(maxShader) 
  lg.draw(canvas)
  lg.setShader() 
end


local matchPixels = lg.newShader [[
  uniform Image stars, maxed;
  const float eps = 1.0e-6;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float c = Texel(texture, tc).r;
    float d = Texel(maxed, tc).r;
    float e = Texel(stars, tc).r;   // original star intensities
    
    float t = 0.0;
    t += Texel(stars, tc + dx).r;
    t += Texel(stars, tc - dx).r;
    t += Texel(stars, tc + dy).r;
    t += Texel(stars, tc - dy).r;
    
    bool near = abs(c - d) < eps;
    bool fwhm_ok = e + e < t;     // Issue #13, use FWHM-related metric to discriminate against hot pixels
    
    float r = near && fwhm_ok ? e : 0.0;
    return vec4(r,r,r, 1.0);
  }]]


local function matchStars(input, maxed, stars)
  matchPixels: send("maxed", maxed)
  matchPixels: send("stars", stars)
  
  local w, h = stars: getDimensions()
  matchPixels: send("dx", {1 / w, 0})
  matchPixels: send("dy", {0, 1 / h})
  
  lg.setShader(matchPixels)
  lg.draw(input)
  lg.setShader() 
end

local function recoverCoordinates(coords, w, h, maxstar)
  local a = coords:newImageData()       -- this is what takes most of the time
  local floor = math.floor
  local foo = {}
  local min, max, avg, var
  local calc = require "shaders.stats" .calc()
  for i = 0, w - 1 do
    local x, y, z, n = a: getPixel(i, 0)
    foo[i+1] = {x, y, z, n}
    if z > 0 then 
      min, max, avg, var = calc(z)
    end
  end
  local sdev = math.sqrt(var)
  table.sort(foo, function(a,b) return a[3] > b[3] end)   -- largest peaks first
  _log("stars (min, max, mean, sdev): %.3f, %.3f, %.3f, %.3f" % {min, max, avg, sdev})
  
  local thold = 0
  _log("threshold", thold)
  local xyzn = {}
  for i = 1, maxstar do
    local x, y, z, n = unpack(foo[i])
    if z <= thold then break end
--    _log(z)
    local margin = 5       -- margin in pixels
    local xok = x > margin and  x < w - margin
    local yok = y > margin and  y < h - margin
    if n ~= 0 and xok and yok then
--      _log(floor(x),y,z)
      xyzn[#xyzn+1] = {floor(x), floor(y), z, n}
    end
  end
  a: release()
--  print(pretty(xyzn))
  return xyzn
end

-- returns coordinates and intensity of matching pixels of two images, 
-- also returns count of number of peaks in column (but only LARGEST is returned as coordinates)

local finder = lg.newShader [[
  uniform float h;
  uniform Image maxima;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    float n = 0.0;
    vec4 xyzn = vec4(0.0);
    for (float i = 0.0; i < h; i += 1.0)
    {
      float y = i / h;
      float a = Texel(maxima, vec2(tc.x, y)) .r;
      bool ok = a > xyzn.a;                      // select the biggest peak
      xyzn = ok ? vec4(sc.x + 1.0, i + 1.0, a, n + 1.0) : xyzn;
      n = xyzn.a;
    }
    return xyzn;
  }
]]

local function findPeaksUsingShader(peaks, maxstar)
  local w, h = peaks: getDimensions()
  lg.setShader(finder)
  finder: send("h", peaks: getHeight())
  finder: send("maxima", peaks)

  oneD: renderTo(lg.clear)
  lg.setBlendMode("replace", "premultiplied")
  oneD: renderTo(lg.draw, peaks)
  lg.setBlendMode "alpha"

  lg.setShader()
  local xyzn = recoverCoordinates(oneD, w, h, maxstar)
  return xyzn
end

-- detects stars , returning array 'xyl' of {x, y, luminosity} tuples
-- note that this doesn't disrupt the workflow, 
-- as it restores original workflow output before returning
local function starfinder(workflow, span)
  local channel = 0       -- use the red channel (maybe just monochrome anyway)
  local maxstar = math.floor(workflow.controls.workflow.maxstar.value)  -- max # of stars to find

  local elapsed = newTimer()

  local w,h = workflow: getDimensions()

  if w ~= oneD: getWidth() then
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})      -- coordinates and intensity of peaks
  end
  
  lg.setBlendMode("replace", "premultiplied")
  workflow: copy("output", "temp")
  workflow: gaussian(3)
  workflow: copy("output", "temp1")

  -- find local maxima in star image
  workflow: renderTo(maxchan, {1 / w, 0}, span, channel)
  workflow: renderTo(maxchan, {0, 1 / h}, span)  
  workflow: renderTo(matchStars, workflow.temp1, workflow.temp)
  lg.setBlendMode "alpha"

  -- recover coordinates of maxima
  local xyl = findPeaksUsingShader(workflow.output, maxstar)

  local nxyl = #xyl
  _log(elapsed ("%.3f ms, detected %d stars", nxyl))
  if nxyl < 3 then return {} end
  
  -- revert workflow buffer
  workflow.output, workflow.temp = workflow.temp, workflow.output

  return xyl
end

return starfinder

-----

