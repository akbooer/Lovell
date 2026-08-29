--
-- starfinder.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.05.30",
  AUTHOR = "AK Booer",
  DESCRIPTION = "star detection",
}

-- 2024.10.28  Version 0
-- 2024.11.18  replace findPeaks() with findPeaksUsingShader()
-- 2024.11.25  return only largest peak found in each column (thanks @Martin Meredith for test data)
-- 2024.11.26  add pixel margin to avoid finding peaks at the image edge

-- 2025.01.28  add DoG (Difference of Gaussians)
-- 2025.02.06  use workflow buffers rather than internal monochrome ones
-- 2025.03.09  abandon DoG, use mean-relative threshold
-- 2025.04.18  Issue #13, use FWHM-related metric to discriminate against hot pixels
-- 2025.05.02  remove Texelstats and simplify finder shader

-- 2026.04.07  replace star intensity with a proxy for flux (using adjacent pixels, may help matching)
-- 2026.04.12  centroid calculation to refine star location, finder_CENTROID()
-- 2026.05.30  add maxstar as a parameter to starfinder()

--TODO: update to use shader.reducer()


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

--[[

 1. Flux calculation
 
    3x3 pixel area around peak
    
      .  u  .
      l  x  r
      .  d  .
      
    A proxy estimate for flux would be the sum of all these nine points (although could be further extended.)
    Further approximate the sum of the diagonal components as r + l + u + d
    
        Flux = x + 2(r + l + u + d)
 
 2. FWHM test
 
    A coarse estimation of the FWHM can be derived by dividing the total area under the peak by the peak height.
    In 1-D, (l x r) or (u x d)
    
        FWHM = (l + x + r) / x or (u + x + d) / x
        
    Average of these 
    
        FWHM = (r + l + u + d + 2x) / 2x 
        FWHM = (r + l + u + d) / 2x + 1
        
    So if (r + l + u + d) > 2x then FWHM > 2
    
 3. Centroid calculation
 
    A simple moments calculation of vertical (u, x, d) and horizontal (r, x, l) balance gives centroid offset from centre.
 
--]]

local matchPixels = lg.newShader [[
  uniform Image stars, maxed;
  const float eps = 1.0e-6;
  uniform vec2 dx, dy;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 _) {
    float a = Texel(texture, tc).r;
    float b = Texel(maxed, tc).r;
    bool peak = abs(a - b) < eps;   // true, if this pixel is a local maxima
    
    float x = Texel(stars, tc).r;   // original star intensity
    
    float r, l, u, d;               // right, left, up down
    r = Texel(stars, tc + dx).r;
    l = Texel(stars, tc - dx).r;
    u = Texel(stars, tc + dy).r;
    d = Texel(stars, tc - dy).r;
    float t = r + l + u + d;
    
    bool fwhm_ok = x + x < t;     // Issue #13, use FWHM-related metric (FWHM > 2) to discriminate against hot pixels
    
    // centroid offsets, using left or upper points as reference origin
    // range is 0 - 2, but scaled by 2 here, since stored in range 0 - 1
    
    float Dx, Dy;     
    Dx = (x + 2.0 * r) / (l + x + r + eps) / 2.0;
    Dy = (x + 2.0 * d) / (u + x + d + eps) / 2.0;
    
    float flux = peak && fwhm_ok ? (2.0 * t + x) / 9.0 : 0.0;   // nine-point average, proxy for flux
    
    return vec4(flux, Dx, Dy, 1.0);
  }
]]


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
  local elapsed = newTimer()
  local a = coords:newImageData()       -- this is what takes most of the time
  
  local stars = {}
  for i = 0, w - 1 do
    stars[i+1] = {a: getPixel(i, 0)}      -- {x, y, z, n}
  end
  
  table.sort(stars, function(a,b) return a[3] > b[3] end)   -- largest peaks first
  
  local thold = 0
  local xyzn = {}
  for i = 1, maxstar do
    local x, y, z, n = unpack(stars[i])
    if z <= thold then break end
    local margin = 5       -- margin in pixels
    local xok = x > margin and  x < w - margin
    local yok = y > margin and  y < h - margin
    if n ~= 0 and xok and yok then
      xyzn[#xyzn+1] = {x, y, z, n}
    end
  end
  a: release()
--  print(pretty(xyzn))
  return xyzn
end

-- returns coordinates and intensity of matching pixels of two images, 
-- also returns count of number of peaks in column (but only LARGEST is returned as coordinates)


local finder_INTEGER = lg.newShader [[
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


local finder_CENTROID = lg.newShader [[
  uniform float h;
  uniform Image maxima;
  
  vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
    float n = 0.0;
    vec4 xyzn = vec4(0.0);
    for (float i = 0.0; i < h; i += 1.0)
    {
      float y = i / h;
      vec4 adxdy = Texel(maxima, vec2(tc.x, y));
      float a  = adxdy.r;
      float dx = adxdy.g * 2.0;
      float dy = adxdy.b * 2.0;
      bool ok = a > xyzn.a;                      // select the biggest peak
      
      xyzn = ok ? vec4(sc.x + dx, i + dy, a, n + 1.0) : xyzn;
      
      n = xyzn.a;
    }
    return xyzn;
  }
]]

local finder = false and finder_CENTROID or finder_INTEGER     -- * * * IMPLEMENTATION CHOICE

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
--  _log(pretty(xyzn))    -- dump coordinate info
  return xyzn
end

-- detects stars, returning array 'xyl' of {x, y, flux} tuples
-- note that this doesn't disrupt the workflow, 
-- as it restores original workflow output before returning
local function starfinder(workflow, span, maxstar)
  local channel = 0       -- use the red channel (maybe just monochrome anyway)

  local elapsed = newTimer()

  local w,h = workflow: getDimensions()

  if w ~= oneD: getWidth() then
--    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba32f"})      -- coordinates and intensity of peaks
    oneD = lg.newCanvas(w, 1, {dpiscale = 1, format = "rgba16f"})      -- coordinates and intensity of peaks
  end
  
  lg.setBlendMode("replace", "premultiplied")
  workflow: copy("output", "temp")
  require "shaders.filter" .gaussian (workflow, 5)
--  workflow: gaussian(5)
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
  
  -- revert workflow buffer
  workflow:swap ("output", "temp")

  return nxyl > 3 and xyl or {}
end

return starfinder

-----

