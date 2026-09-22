--
-- starfinder.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.21",
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
-- 2026.09.01  5x5 patch to measure flux and FWHM more carefully
--
-- 2026.09.21  complete re-write with integrated detector / centroid and flux / candidate selection funnel


local _log = require "logger" (_M)

local ffi = require "ffi"

local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


local starExtract = lg.newShader [[
#pragma language glsl3

uniform int channel = 0;
uniform int stride = 16;

uniform Image smoothedImage;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 texSize = vec2(textureSize(tex, 0));
    
    // Each pixel on the twoD canvas corresponds to a unique stride x stride tile block.
    // screen_coords gives the exact pixel coordinate on the target canvas (twoD).
    ivec2 tileCoord = ivec2(floor(screen_coords));
    ivec2 baseCoord = tileCoord * stride;
    
    float maxVal = 0.0;
    float previous = maxVal;
    ivec2 peakOffset = ivec2(0);

    // Scan ONLY within this specific tile's neighborhood using the smoothed image
    for (int y = 0; y < stride; y++) {
        for (int x = 0; x < stride; x++) {
            ivec2 samplePos = baseCoord + ivec2(x, y);
            float val = texelFetch(smoothedImage, samplePos, 0) [channel];
            
            if (val >= maxVal) {
                previous = maxVal;
                maxVal = val;
                peakOffset = ivec2(x, y);
            }
        }
    }

    // Threshold check for flat-top saturation
    if (maxVal == previous) {
        return vec4(0.0);
    }

    ivec2 centrePixel = baseCoord + peakOffset;

    // Extract Centroid and Flux from a 3x3 area on the main texture (tex) around the peak
    float weightSum = 1e-6;
    vec2 centroidSum = vec2(0.0);
    int idx = 0;

    vec3 X = vec3(0.0);
    vec3 Y = vec3(0.0);
    
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            ivec2 samplePos = centrePixel + ivec2(dx, dy);
            float rawVal = texelFetch(tex, samplePos, 0) [channel];
            
            weightSum += rawVal;
            X[dx + 1] += rawVal;
            Y[dy + 1] += rawVal;
        }
    }

    // centre calculation uses model of 2D sloping plane plus a paraboloid peak
    float dx = 0.5 * (X[0] - X[2]) / (X[0] - 2.0 * X[1] + X[2]);
    float dy = 0.5 * (Y[0] - Y[2]) / (Y[0] - 2.0 * Y[1] + Y[2]);
    
    if (dx < -0.5 || dy > 0.5 || dy < -0.5 || dy > 0.5) { // indicates poorly shaped stars
        return vec4(0.0);
    }
    
    vec2 starCoord = vec2(centrePixel);
//    starCoord = starCoord + vec2(dx, dy);                // fine adjustment based on peak location
    float flux = weightSum / 9.0;                         // normalized to unity
    float fwhm = sqrt(weightSum/maxVal);                  // gross approximation

    return vec4(starCoord, flux, fwhm);
}

]]

local function sortorder(a,b) return a[3] > b[3] end    -- order {x, y, flux, fwhm} by flux

--
-- group stars into 3x3 grid (nonants, cf. quadrants)
-- selecting locally the best
--

local function nonants(xyfw, W, H)
  
  local W3, H3 = 3 / W , 3 / H
  local I9 = { { {}, {}, {} }, { {}, {}, {} }, { {}, {}, {} } }
  
  -- populate the nonants
  for i = 1, #xyfw do
    local star = xyfw[i]
    local u, v = 1 + math.floor(star[1] * W3), 1 + math.floor(star[2] * H3)
    local nonant = I9[u][v]
    nonant[#nonant+1] = star
  end
  
  -- sort them and save top 4 (36 in total)
  local best4 = table.new(36, 0)
  for u = 1, 3 do
    for v = 1, 3 do
      local nonant = I9[u][v]
      table.sort(nonant, sortorder)   -- largest peaks first 
      for i = 1, 4 do
        best4[#best4+1] = nonant[i]   -- note that there may be less than 4, and that's OK
      end
    end
  end
  
  -- now sort the 36 and return best 30 (possibly dropping up to 6 stars)
  table.sort(best4, sortorder)   -- largest peaks first 
  local some = table.new(30, 0)
  for i = 1, 30 do
    some[i] = best4[i]
  end
  return some, best4
end

--
-- avoid near duplication of stars {x, y, flux, fwhm} from adjacent patches
--
local function distinct(xyfw, minDistance)
    if #xyfw <= 1 then return xyfw end
    minDistance = minDistance or 4.0
    local distSq = minDistance * minDistance

    -- Sort by X coordinate to enable spatial locality
    table.sort(xyfw, function(a, b) return a[1] < b[1] end)

    local unique = {}
    
    for i = 1, #xyfw do
        local star = xyfw[i]
        local keep = true

        -- Scan backwards through already accepted stars
        for j = #unique, 1, -1 do
            local kept = unique[j]
            local dx = star[1] - kept[1]

            -- Since stars are sorted by X, if dx exceeds minDistance, 
            -- no earlier star can possibly be within range.
            if dx > minDistance then
                break 
            end

            local dy = star[2] - kept[2]
            if (dx * dx + dy * dy) < distSq then
                -- Duplicate found! Keep the brighter one (or handle tie-breaks)
                if star[3] > kept[3] then
                    -- Replace the dimmer existing star with this brighter one
                    unique[j] = star
                end
                star = nil
                break
            end
        end

        unique[#unique + 1] = star
    end

    return unique
end


ffi.cdef[[
    typedef struct {
        float x;
        float y;
        float flux;
        float fwhm;
    } StarPoint;
]]

local function recoverCoordinates2d(coords, fullWidth, fullHeight, border)
  
  --
  -- recover star coordinates and parameters...
  -- ... ignoring saturated stars and those close to the image edge
  --
  
  border = border or 20
  local xmin, xmax = border, fullWidth  - 2 * border
  local ymin, ymax = border, fullHeight - 2 * border
  
  local data = coords:newImageData()
  local W, H = data:getDimensions()
  local N = {}        -- funnel sizes
  N[1] = W * H

  local stars = ffi.cast("StarPoint*", data:getFFIPointer())
  local xyfw = {}
  local j = 0

  for i = 0, N[1] - 1 do
    local p = stars[i]
    local x, y, flux, fwhm = p.x , p.y , p.flux, p.fwhm
    if flux < 0.99 and x > xmin and x < xmax and y > ymin and y < ymax then
      j = j + 1
      xyfw[j] = { x, y, flux, fwhm }
    end
  end
  data:release()
  N[2] = #xyfw
  
  --
  -- cull any near-duplicates (probably from adjacent patches)
  --

  local unique = distinct(xyfw, fullHeight * 0.01)      -- 1% of image height tolerance
  N[3] = #unique
  
  local some, best4 = nonants(unique, fullWidth, fullHeight)
  N[4] = #best4
  N[5] = #some
  
  local funnel = ("candidate funnel: %d => %d => %d => %d => %d") % N
  _log (funnel)
  
  return some
end


local TILESIZE = 16;

local twoD = lg.newCanvas(1,1)      -- just a dummy to start with


-- detects stars, returning array 'xyl' of {x, y, flux} tuples
-- note that this doesn't disrupt the workflow, 
-- as it restores original workflow output before returning
-- NB: the alpha channel may not be unity (could be replicated monochrome image) hence BlendMode
local function starfinder(workflow, span, maxstar)
  local channel = 0       -- use the red channel (maybe just monochrome anyway)
  local scale = 1 / TILESIZE
  local elapsed = newTimer()

  --
  -- configure 2D canvas, 16x16 smaller than raw image and full 32-bit FP
  --
  
  local w,h = workflow: getDimensions()
  local w2, h2 = math.floor(w * scale), math.floor(h* scale)  
  if w2 ~= twoD: getWidth() or h2 ~= twoD: getHeight() then
    twoD: release()
    twoD = lg.newCanvas(w2, h2, {dpiscale = 1, format = "rgba32f"})      -- coordinates and intensity of peaks
  end
  
  --
  -- filter input in two stages, after saving original in "temp"
  --
  
  _log "filtering..."
  lg.setBlendMode("replace", "premultiplied")
  workflow: copy("output", "temp")          -- save raw input
  require "shaders.filter" .gaussian (workflow, 1)    
  lg.setBlendMode("replace", "premultiplied")
  require "shaders.filter" .gaussian (workflow, 2)
  workflow: swap("output", "input")         -- output is now Gaussian(1), input is additional Gaussian(2)
   
  --
  -- extract best star in each 16x16 panel
  --
  
  _log "extracting coordinates..."
  lg.setShader(starExtract)
  starExtract: send("smoothedImage", workflow.input)
  lg.setBlendMode("replace", "premultiplied")  
  twoD: renderTo(lg.draw, workflow.output)
  workflow:swap ("temp", "output")              -- revert workflow buffer
  lg.reset()
  
  --
  -- Star funnel to select best candidates
  --
  
  _log "making selection..."
  local xyfw = recoverCoordinates2d(twoD, w, h)
  local n = #xyfw
  
--[[
  local s = '\n'
  local t = {s, "top stars (by flux):", "(   x   ,   y  )     flux"}
  for i = 1, math.min(n, 30) do
    t[#t+1] = "(%6.1f, %6.1f)    %5.2f    %5.2f" % xyfw[i]
  end
  t[#t+1] = ''
  _log(table.concat(t, s))
--]]

  _log(elapsed ("%.3f ms, selected %d stars", n))

  return n > 3 and xyfw or {}
end

return starfinder

-----

