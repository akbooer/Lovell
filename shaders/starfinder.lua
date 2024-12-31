--
-- starfinder.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.26",
    AUTHOR = "AK Booer",
    DESCRIPTION = "star detection",
  }

-- 2024.10.28  Version 0
-- 2024.11.18  replace findPeaks() withfindPeaksUsingShader()
-- 2024.11.25  return only largest peak found in each column (thanks @Martin Meredith for test data)
-- 2024.11.26  add pixel margin to aoid finding peaks at the image edge


local _log = require "logger" (_M)

local newTimer  = require "utils" .newTimer
--local buffer    = require "utils" .buffer

local love = _G.love
local lg = love.graphics

local buffer1 = lg.newCanvas(1,1)   -- working buffers for local maxima windowing
local buffer2 = lg.newCanvas(1,1)

local oneD = lg.newCanvas(1,1)      -- just a dummy to start with
local twoD = lg.newCanvas(1,1)


-- calculates maximum pixel in a 1-D sliding window
-- applied once in each direction for 2-D solution
local maxShader = lg.newShader [[
  uniform vec2 direction;
  uniform float radius;
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

-- returns coordinates and intensity of matching pixels of two images, 
-- also returns count of number of peaks in column (but only LARGEST is returned as coordinates)

local finder = lg.newShader [[
  uniform float h;
  uniform Image maxima;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    float n = 0.0;
    vec4 xyzn = vec4(0.0);
    for (float i = 1.0; i < h - 1; i += 1.0)
    {
      float y = i / h;
      float a = Texel(maxima, vec2(tc.x, y)) .r;
//      bool ok = a > 0.01 && a < 1.0 
      bool ok = a > xyzn.a;                     // select the biggest peak
      xyzn = ok ? vec4(sc.x + 1.0, i + 1.0, a, n + 1.0) : xyzn;
      n = xyzn.a;
    }
    return xyzn;
  }
]]

local function maxchan(canvas, direction, radius, channel)
  channel = channel or 0        -- default to red channel
  maxShader:send("channel", channel)
  maxShader:send("direction", direction)
  maxShader:send("radius", radius)
  lg.setShader(maxShader) 
  lg.draw(canvas)
  lg.setShader() 
end

 
local function recoverCoordinates(coords, w, h)
  local a = coords:newImageData()
  local floor = math.floor
  local xyzn = {}
  a: mapPixel(function(_,_, ...)
    local x, y, z, n = ...
    local margin = 20       -- margin in pixels
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

-- returns matching pixels in two images, 
-- or sets pixel value to zero if not matching
local matchPixels = lg.newShader [[
  extern Image stars;
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float c = Texel(texture, tc).r;
    float d = Texel(stars, tc).r;
    float r = (c == d) ? c : 0.0;
    return vec4(r,r,r, 1.0);
  }]]

local function matchStars(a, b)
  matchPixels: send("stars", a)
  lg.setShader(matchPixels)
  lg.draw(b)
  lg.setShader() 
end


local function findPeaksUsingShader(peaks, w ,h)
  lg.setShader(finder)
  finder: send("h", peaks: getHeight())
  finder: send("maxima", peaks)
  lg.setBlendMode("replace", "premultiplied")
  oneD: renderTo(lg.draw, twoD)
  lg.setBlendMode("alpha", "alphamultiply")
  lg.setShader()
  local xyzn = recoverCoordinates(oneD, w, h)
  return xyzn
end

-- findPeaks() 
-- original way to extract star coordinates.
-- could have been speeded up using FFI pointer
-- but now replaced with above shader

--[[local function findPeaks(img)
  local a = img:newImageData()
  local xyl = {}
  a: mapPixel(function(...)
    local x,y, r = ...
    if r > 0.3 and r < 0.95 then
      xyl[#xyl+1] = {x, y, r}
    end
    return ...
  end)
  a: release()
  return xyl
end
--]]

-- detects stars , returning array 'xyl' of {x, y, luminosity} tuples
local function starfinder(workflow)
  local span = workflow.controls.workflow.keystar.value
  local channel = 0       -- use the red channel (probably monochrome input anyway)
  local input = workflow.output       -- use the latest workflow output
  local w,h = input: getDimensions()
  local bw, bh = buffer1: getWidth()
  
  if bw ~= w or bh ~= h then
    oneD    = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})      -- coordinates and intensity of peaks
    twoD    = lg.newCanvas(w, 1, {dpiscale = 1, format = "r8"})           -- minimal storage, only used for dimensions
    buffer1 = lg.newCanvas(w, h, {dpiscale = 1, format = "r16f"})         -- only single channel needed
    buffer2 = lg.newCanvas(w, h, {dpiscale = 1, format = "r16f"})
  end
  
  -- find local maxima in star image
  local elapsed = newTimer()
  buffer1: renderTo(maxchan, input,   {1 / (w - 1), 0}, span, channel)    -- w-1 because of posts and gaps counting
  buffer2: renderTo(maxchan, buffer1, {0, 1 / (h - 1)}, span)  
  buffer1: renderTo(matchStars, input, buffer2)
 
  -- recover coordinates of maxima
  local xyl = findPeaksUsingShader(buffer1, w, h)
  table.sort(xyl, function(a,b) return a[3] > b[3] end)
  _log(elapsed ("%.3f ms, detected %d stars", #xyl))
  _log("min, max = %.3f, %.3f" % {xyl[#xyl][3], xyl[1][3]})
  
  return xyl
end

return starfinder

-----

