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
-- TODO: make this work in mono workflow to reduce memory bandwidth?


local _log = require "logger" (_M)

local ffi = require "ffi"

local reducer   = require "shaders.reducer"
local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


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

local reduce = reducer.new {Xborder = 5, Yborder = 5, stride = 1}

local function matchStars(background, maxed, stars)
  
  local w, h = stars: getDimensions()

  return reduce (background, {
      
      pass1 = {
        comment =  "Pass #1 - find the peaks",
        uniforms = {
          ["Image stars"] = stars,      -- original star image
          ["Image maxed"] = maxed,      -- local maxima
          ["vec2 dx"] = {1 / w, 0},
          ["vec2 dy"] = {0, 1 / h}},
        init = [[ 
          const float eps = 1.0e-6; 
          vec4 peak = vec4(0.0); ]],
        code = [[
          vec2 tc = texture_coords;
          float a = Texel(MainTexture, tc).r;     // smoothed background
          float b = Texel(maxed, tc).r;
          bool isPeak = abs(a - b) < eps;   // true, if this pixel is a local maxima
          
          float x = Texel(stars, tc).r;   // original star intensity
          
          float r, l, u, d;               // right, left, up down
          r = Texel(stars, tc + dx).r;
          l = Texel(stars, tc - dx).r;
          u = Texel(stars, tc + dy).r;
          d = Texel(stars, tc - dy).r;
          float t = r + l + u + d;
          
          // Issue #13, use FWHM-related metric (FWHM > 2) to discriminate against hot pixels
          bool fwhm_ok = x + x < t;
          
          // centroid offsets, using left or upper points as reference origin
          // range is 0 - 2, but scaled by 2 here, since stored in range 0 - 1
          
          float Dx, Dy;     
          Dx = (x + 2.0 * r) / (l + x + r + eps) / 2.0;
          Dy = (x + 2.0 * d) / (u + x + d + eps) / 2.0;
          
          float flux = isPeak && fwhm_ok ? (2.0 * t + x) / 9.0 : 0.0;   // nine-point average, proxy for flux 
          vec4 star = vec4(flux, Dx, Dy, 1.0);
          peak = peak.r < flux ? star : peak; ]],
        ret = "peak"},
      
    pass2 = {
        comment = "Pass #2 - select the largest of the largest peaks",
        init = [[ vec4 peak = vec4(0.0); ]],
        code = [[
          vec4 star = Texel(MainTexture, texture_coords);
          peak = star.r > peak.r ? star : peak; ]],
        ret = "peak"}
      })
  end


-- detects stars, returning array 'xyl' of {x, y, flux} tuples
-- note that this doesn't disrupt the workflow, 
-- as it restores original workflow output before returning
local function starfinder(workflow, span, maxstar)
  local channel = 0       -- use the red channel (maybe just monochrome anyway)

  local elapsed = newTimer()

  local w,h = workflow: getDimensions()
  
  lg.setBlendMode("replace", "premultiplied")
  workflow: copy("output", "temp")              -- stars
  workflow: gaussian(5)
  workflow: copy("output", "temp1")             -- smooth background

  -- find local maxima in star image
  workflow: renderTo(maxchan, {1 / w, 0}, span, channel)      -- 1D maxed
  workflow: renderTo(maxchan, {0, 1 / h}, span)               -- 2D maxed
  

--  workflow: renderTo(background, workflow.temp1, workflow.temp)
  lg.setBlendMode "alpha"
   
  local oneD = matchStars(workflow.temp1, workflow.output, workflow.temp)    -- background, maxed, stars

  -- recover peaks
  local x, y, l = reducer.readout(oneD)
  local xyl = {}
  for i = 1, #x do
    if l[i] > 0 then
      xyl[#xyl+1] = {w * x[i], h * y[i], l[i]}
    end
  end
  
  xyl.n = math.min(#x, maxstar)
  table.sort(xyl, function (a,b) return a[3] > b[3] end)
  
  --TODO: coordinates not right !
--  local xyl = findPeaks(oneD, maxstar)

  local nxyl = #xyl
  _log(elapsed ("%.3f ms, detected %d stars", nxyl))
--  _log(pretty(xyl))
  -- revert workflow buffer
  workflow:swap ("output", "temp")

  return nxyl > 3 and xyl or {}
end

return starfinder

-----

