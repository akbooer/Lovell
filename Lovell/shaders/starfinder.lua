--
-- starfinder.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.03.09",
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


-- returns matching pixels in two images, 
-- or sets pixel value to zero if not matching
local matchPixels = lg.newShader [[
  uniform Image stars, maxed;
  const float eps = 1.0e-4;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float c = Texel(texture, tc).r;
    float d = Texel(maxed, tc).r;
    float e = Texel(stars, tc).r;   // original star intensities
    float r = abs(c - d) < eps ? e : 0.0;
    return vec4(r,r,r, 1.0);
  }]]

local function matchStars(input, maxed, stars)
  matchPixels: send("maxed", maxed)
  matchPixels: send("stars", stars)
  lg.setShader(matchPixels)
  lg.draw(input)
  lg.setShader() 
end

local function recoverCoordinates(coords, w, h)
  local a = coords:newImageData()
  local floor = math.floor
  local xyzn = {}
  a: mapPixel(function(_,_, ...)
      local x, y, z, n = ...
      local margin = 5       -- margin in pixels
      local xok = x > margin and  x < w - margin
      local yok = y > margin and  y < h - margin
      if n ~= 0 and xok and yok then
        xyzn[#xyzn+1] = {floor(x), floor(y), z, n}
      end
      return ...
    end)
  a: release()
  return xyzn
end

-- returns coordinates and intensity of matching pixels of two images, 
-- also returns count of number of peaks in column (but only LARGEST is returned as coordinates)

local finder = lg.newShader [[
  uniform float h;
  uniform Image maxima, statsTexel;
  float threshold = 2.0 * Texel(statsTexel, vec2(0.0)) .z;     // twice the mean value
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    float n = 0.0;
    vec4 xyzn = vec4(0.0);
    for (float i = 0.0; i < h; i += 1.0)
    {
      float y = i / h;
      float a = Texel(maxima, vec2(tc.x, y)) .r;
      bool ok = a > xyzn.a && a > threshold;                      // select the biggest peak
      xyzn = ok ? vec4(sc.x + 1.0, i + 1.0, a, n + 1.0) : xyzn;
      n = xyzn.a;
    }
    return xyzn;
  }
]]

-- statsTexel is 1x1 canvas with min, max, avg, var of a R, G, or B channel (or A)
local function findPeaksUsingShader(peaks, statsTexel)
  local w, h = peaks: getDimensions()
  lg.setShader(finder)
  finder: send("h", peaks: getHeight())
  finder: send("maxima", peaks)
  finder: send("statsTexel", statsTexel)

  oneD: renderTo(lg.clear)
  lg.setBlendMode("replace", "premultiplied")
  oneD: renderTo(lg.draw, peaks)
  lg.setBlendMode("alpha", "alphamultiply")

  lg.setShader()
  local xyzn = recoverCoordinates(oneD, w, h)
  return xyzn
end

-- findPeaks() 
-- original way to extract star coordinates.
-- could have been speeded up using FFI pointer
-- but now replaced with above shader

local function findPeaks(img, threshold)
  threshold = threshold or 0.001
  local a = img:newImageData()
  local xyl = {}
  a: mapPixel(function(...)
      local x,y, r = ...
      if r > threshold then
        xyl[#xyl+1] = {x, y, r}
      end
      return ...
    end)
  a: release()
  return xyl
end

-- detects stars , returning array 'xyl' of {x, y, luminosity} tuples
-- note that this doesn't disrupt the workflow, 
-- as it restores original workflow output before returning
local function starfinder(workflow, span)
  local channel = 0       -- use the red channel (maybe just monochrome anyway)

  local elapsed = newTimer()

  local w,h = workflow: getDimensions()

  if w ~= oneD: getWidth() then
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})      -- coordinates and intensity of peaks
  end
  
  local statsTexel = workflow: statsTexel(channel)    -- get channel statistics (as a texture)
  
  workflow: copy("output", "temp")
  workflow: gaussian(3)
  workflow: copy("output", "temp1")

  -- find local maxima in star image
  workflow: renderTo(maxchan, {1 / w, 0}, span, channel)
  workflow: renderTo(maxchan, {0, 1 / h}, span)  
  workflow: renderTo(matchStars, workflow.temp1, workflow.temp)

  -- recover coordinates of maxima
--  local xyl = findPeaks(workflow.output, threshold)
  local xyl = findPeaksUsingShader(workflow.output, statsTexel)

  table.sort(xyl, function(a,b) return a[3] > b[3] end)     -- largest peaks first
  local nxyl = #xyl
  _log(elapsed ("%.3f ms, detected %d stars", nxyl))
  if nxyl < 3 then return {} end
  
  -- revert workflow buffer
  workflow.output, workflow.temp = workflow.temp, workflow.output

  local maxstar = math.floor(workflow.controls.workflow.maxstar.value)
  for i = maxstar + 1, #xyl do
    xyl[i] = nil
  end

  return xyl
end

return starfinder

-----

