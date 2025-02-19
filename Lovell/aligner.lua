--
--  aligner.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.27",
    DESCRIPTION = "image alignment",
  }

-- 2024.10.30  Version 0

-- 2025.01.27  return matched point pairs for later display


local _log, newTimer
if love then
  _log = require "logger" (_M)
  newTimer = require "utils" .newTimer
else
  _log = print
  newTimer = function() return function(f, ...) return f:format(0, ...) end end
end



-------------------------------
--
-- signatures 
--
-- returns an informative, rotationally invariant signature (sparse histogram of star distances)
-- for each star coordinate in the list
--

local function signatures(stars)
  local floor, sqrt = math.floor, math.sqrt
  local ranges = {}
  local elapsed = newTimer()
  local N = math.min(100, #stars)
  for i = 1, N do
    local hist = {}
    ranges[i] = hist
    local a = stars[i]
    local x1, y1 = a[1], a[2]
    for j = 1, N do
      local b = stars[j]
      local x2, y2 = b[1], b[2]
      local d  = sqrt ((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
      d = floor(d + 0.5) + 1
      hist[d] = (hist[d] or 0) + 1
    end
  end
  _log (elapsed ("%0.3f ms, for %d star signatures", N))
  return ranges
end

-------------------------------
--
-- EMDistance - Earth Mover's Distance
--
-- ... a measure of the similarity of two histograms
-- see: https://en.wikipedia.org/wiki/Earth_mover%27s_distance
--

local function EMDistance(hist1, hist2, N)
  local abs = math.abs
  local EMD = 0
  local TD = 0      -- total distance
  for i = 1, N do
    local p = hist1[i] or 0   -- handle sparse histograms
    local q = hist2[i] or 0
    EMD = EMD + p - q
    TD = TD + abs(EMD)
   end
   return TD
end

-------------------------------
--
-- nearest neighbour to each of the keystars
-- possible that no match is found (if intensities too different)
-- returned matches array contains pairs of INDICES of matching stars and keystars
--
--[
local function matchPairs(stars, keystars, controls)
  local maxDist = controls.workflow.offset.value
  local maxLumDiff = 0.05
  
  local maxDist2 = maxDist * maxDist
  local maxLumDiff2 = maxLumDiff * maxLumDiff
  
	local starIndex, keyIndex = {}, {}    -- index of paired stars
  local elapsed= newTimer()
  
  for i = 1, #keystars do
    local a = keystars[i]
    local mindist2 = maxDist2
    local x1, y1, l1 = a[1], a[2], a[3] or 0   -- (x,y) and intensity
    local found
    for j = 1, #stars do
      local b = stars[j]
      local x2, y2, l2 = b[1], b[2], b[3] or 0
      local dist2  = (x1 - x2)^2 + (y1 - y2)^2
      local delta2 = (l1 - l2)^2 
      if dist2 < mindist2 and delta2 < maxLumDiff2 then
        mindist2 = dist2
        found = j 
      end
    end
    if found then
      starIndex[#starIndex + 1] = found
      keyIndex[#keyIndex + 1]  = i
    end
  end
  
  _log(elapsed ("%.3f ms, matched %d stars (max offset = %d)", #starIndex, maxDist))

	return starIndex, keyIndex
end
--]]


local function mindist(a, sigStar)
  local mindist = math.huge
  local found
  for j = 1, #sigStar do
    local b = sigStar[j]
     local dist = EMDistance(a, b, 500)
    if dist < mindist then
      mindist = dist
      found = j 
    end
  end
  return found
end

local function YmatchPairs(stars, keystars, controls)
  local maxDist = controls.workflow.offset.value
  local maxDist2 = maxDist * maxDist
  
	local starIndex, keyIndex = {}, {}    -- index of paired stars
  local elapsed= newTimer()
  
  local sigKeys = signatures(keystars)
  local sigStar = signatures(stars)
   
  for i = 1, #sigKeys do
    local a = sigKeys[i]
    local j = mindist(a, sigStar)

    -- check reciprocal
    local k = mindist(sigStar[j], sigKeys)
    if i == k then
      starIndex[#starIndex + 1] = j
      keyIndex[#keyIndex + 1]  = i
    end
  end
  
--  _log(elapsed ("%.3f ms, matched %d stars (max offset = %d)", #starIndex, maxDist))

	return starIndex, keyIndex
end

local function NearestNeighbors(stars, keystars, controls)
  local starIndex, keyIndex = matchPairs(stars, keystars, controls)
  local point_pairs = {}
  for i = 1, #starIndex do
    local star = stars[starIndex[i]]
    local key  = keystars[keyIndex[i]]
    point_pairs[i] = {key[1], key[2], star[1], star[2]}  -- (x,y), (x',y')
  end
  return point_pairs, {starIndex, keyIndex}
end

-------------------------------
--
-- ICP
-- see: https://github.com/richardos/icp
--

local function point_based_matching(point_pairs)
  --[[
    see: "Robot Pose Estimation in Unknown Environments by Matching 2D Range Scans", by F. Lu and E. Milios.

    point_pairs: the matched point pairs { {x1, y1, x1', y1'}, ..., {xi, yi, xi', yi'}, ...}
    returns rotation angle and the 2D translation (x, y) to be applied for matching the given pairs of points
   ]]

  local n = #point_pairs
  if n == 0 then return end

  local x_mean,  y_mean  = 0, 0
  local xp_mean, yp_mean = 0, 0

  for i = 1, #point_pairs do
    local x,y, xp,yp = unpack(point_pairs[i])
    x_mean,   y_mean =  x_mean + x,   y_mean + y
    xp_mean, yp_mean = xp_mean + xp, yp_mean + yp
  end

  x_mean,   y_mean =  x_mean / n,  y_mean / n
  xp_mean, yp_mean = xp_mean / n, yp_mean / n

  local s_x_xp, s_y_yp, s_x_yp, s_y_xp = 0, 0, 0, 0  
  for i = 1, #point_pairs do
    local x,y, xp,yp = unpack(point_pairs[i])
    s_x_xp = s_x_xp + (x - x_mean) * (xp - xp_mean)
    s_y_yp = s_y_yp + (y - y_mean) * (yp - yp_mean)
    s_x_yp = s_x_yp + (x - x_mean) * (yp - yp_mean)
    s_y_xp = s_y_xp + (y - y_mean) * (xp - xp_mean)
  end

  local opposite, adjacent = s_x_yp - s_y_xp, s_x_xp + s_y_yp
  local hypotenuse = math.sqrt(adjacent * adjacent + opposite * opposite)
  local sin, cos = opposite / hypotenuse, adjacent / hypotenuse
  local translation_x = xp_mean - (x_mean * cos - y_mean * sin)
  local translation_y = yp_mean - (x_mean * sin + y_mean * cos)
  local rot_angle = math.atan2(s_x_yp - s_y_xp, s_x_xp + s_y_yp)

--  print("fit x,y, angle", translation_x, translation_y,  rot_angle)
  return rot_angle, translation_x, translation_y
end


-------------------------------
--
--

function _M.transform(stars, keystars, controls)
  local elapsed = newTimer()

  local point_pairs = NearestNeighbors(stars, keystars, controls)
  if #point_pairs == 0 then return end
  
  local theta, x,y = point_based_matching(point_pairs)
  local degrees = theta * 180 / math.pi
  _log(elapsed("%.3f ms, transform: %.3fº  (%.1f, %.1f)", degrees, x,y))
  return theta, x,y, point_pairs
end


-------------------------------
--
-- TEST from https://github.com/richardos/icp/tree/master
    
function _M.TEST(N)

  local pretty = require "lib.pretty"
  local matrix = require "lib.matrix"

  local T = 'T'   -- transpose operator

  -- set seed for reproducible results
  math.randomseed(12345)

  -- create a set of points to be the reference for ICP
  local reference_points = {}
  for i = 1, N do
    local x = math.random() * 1000
    local y = math.random() * 1000
    reference_points[i] = {x, y}
  end
  reference_points = matrix(reference_points)

  -- transform the set of reference points to create a new set of
  -- points for testing the ICP implementation

  -- 1. remove some points
  local points_to_be_aligned = {}
  for i = 1, N * 0.8 do
    points_to_be_aligned[i] = reference_points[i] -- + matrix {{math.random(), math.random()}}
  end
  points_to_be_aligned = matrix(points_to_be_aligned)

  -- 2. apply rotation to the new point set
  local theta = -1.5/60
  local c, s = math.cos(theta), math.sin(theta)
  local rot = matrix({{c, -s},
      {s,  c}})
  points_to_be_aligned = points_to_be_aligned * rot
--    for i = 1, #points_to_be_aligned do
--      local x,y = points_to_be_aligned[i]
--      x = x * c + x * s
--      y = y * c - y * s
--      points_to_be_aligned[i] = {x, y}
--    end

  -- 3. apply translation to the new point set
  local a,b = 18, -5
  local offset = {{a, b}}
  for i = 1, #points_to_be_aligned do
    offset[i] = offset[1]
  end
  offset = matrix(offset)
  print("offset", a, b, "angle", theta)
  points_to_be_aligned = points_to_be_aligned + offset 

  print(points_to_be_aligned)
  print "----"
  print(reference_points)
  print "----"

  local hists = signatures(reference_points)
--  print(pretty(hists))
  print "----"

  print "EM distance"
  local n = #hists
  for i = 1, n do
    for j = 1, n do
      if i == j then print(i, EMDistance(hists[j], hists[i], 1500)) end
    end
  end
  print "----"
  
  local controls = {workflow = {offset = {value = 100}}}
  
  local phi, x, y = _M.transform(reference_points, points_to_be_aligned, controls)
  print "SOLUTION:"
  print("offset", a, b, "angle", phi)

end

--_M.TEST(500)

-----

return _M

-----
