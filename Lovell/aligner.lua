--
--  aligner.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.04.01",
  DESCRIPTION = "image alignment using Fast Global Registration",
}

-- 2024.10.30  Version 0

-- 2025.01.27  return matched point pairs for later display
-- 2025.03.05  use Fast Global Registration algorithm
-- 2025.03.09  use image centre as rotation origin
-- 2025.03.11  linearize angle around previous transformation estimate (as per the paper)


--[[

  FAST GLOBAL REGISTRATION

  see: 
        Zhou, Qian-Yi, Jaesik Park, and Vladlen Koltun. 
        "Fast global registration." 
        Computer Vision–ECCV 2016: 14th European Conference, Amsterdam, The Netherlands, October 11-14, 2016, 
        Proceedings, Part II 14. Springer International Publishing, 2016.

  also: https://github.com/isl-org/FastGlobalRegistration

  They say:
  
        "Extensive experiments demonstrate that the presented approach matches
        or exceeds the accuracy of state-of-the-art global registration pipelines, while 
        being at least an order of magnitude faster. Remarkably, the presented approach is
        also faster than local refinement algorithms such as ICP. It provides the accuracy
        achieved by well-initialized local refinement algorithms, without requiring
        an initialization and at lower computational cost."
        
--]]


local _log = require "logger" (_M)

local solve     = require "lib.solver" .solve
local matrix    = require "lib.matrix"
local newTimer  = require "utils" .newTimer

local deg = 180 / math.pi

-------------------------------
--
-- nearest neighbour to each of the keystars
-- possible that no match is found (if intensities too different)
-- returned index[i] contains index of matching star[j] or 0 if no match
--

local function oneWayMatch(stars, keystars, maxDist, maxLumDiff)  
  local maxDist2 = maxDist * maxDist
  local maxLumDiff2 = maxLumDiff * maxLumDiff
  local index = {}    -- index of star which matches i-th keystar
  for i = 1, #keystars do
    local a = keystars[i]
    local mindist2 = maxDist2
    local x1, y1, l1 = a[1], a[2], a[3] or 0   -- (x,y) and intensity
    local found = 0
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
    index[i] = found
  end
  return index
end

-- two-way match of star pairs
local function matchPairs(stars, keystars, controls)
  local elapsed= newTimer()
  local maxDist = controls.workflow.offset.value
  local maxLumDiff = 0.1 -- 0.05  
  local sIndex = oneWayMatch(stars, keystars, maxDist, maxLumDiff)     -- match one to the other...
  local kIndex = oneWayMatch(keystars, stars, maxDist, maxLumDiff)     -- ...and then the other way around

  local starIndex, keyIndex = {}, {}
  for i = 1, #sIndex do
    local found = sIndex[i]
    if kIndex[found] == i then
      starIndex[#starIndex + 1] = found
      keyIndex[#keyIndex + 1]  = i
    end
  end

  _log(elapsed ("%.3f ms, matched %d stars", #starIndex))

  return starIndex, keyIndex
end

--[=[
local function check(p, q, i, j)
  return true
end

-- three-way tuple constraint
local function tuple_constraint(stars, keystars, starIndex, keyIndex)
  local N = #starIndex
  local random = _G.love.math.random
  local include = {}
  for _ = 1,42 do
    local idx = {}
    local p, q = {}, {}
    for i = 1,3 do
      local n = random(N)
      idx[i] = n
      p[i] = stars[starIndex[n]]
      q[i] = keystars[keyIndex[n]]
    end
    local ok = check(p,q, 1,2)
    ok = ok and check(p,q, 1,3)
    ok = ok and check(p,q, 2,3)
    if ok then
      for i = 1,3 do
        include[idx[i]] = true
      end
    end
  end
  -- build new indices
  local newSI, newKI = {}, {}
  for i = 1, N do
    local j = include[i]
    if j then
      newSI[#newSI+1] = starIndex[j]
      newKI[#newKI+1] = keyIndex[j]
    end
  end
  return newSI, newKI
end
--]=]

local function NearestNeighbors(stars, keystars, controls)
  
--  local Si, Ki = matchPairs(stars, keystars, controls)
--  local starIndex, keyIndex = tuple_constraint(stars, keystars, Si, Ki)
  -- OR
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
-- FAST GLOBAL REGISTRATION
--

local function xform_matrix(theta, x, y)
  local c, s = math.cos(theta), math.sin(theta)
  return matrix { {c, -s, x}, {s, c, y}, {0, 0, 1} }
end

-- build equation to solve Ax = b
local function Ab(X, Y, XP, YP, L, theta, h, v)
  local c, s = math.cos(theta), math.sin(theta)
  local A,b = {}, {}
  L = L or {}           -- vector of lpq weights
  local j = 0
  for i = 1, #X do
    local lpq = L[i] or 1
    local x,y, xp,yp = X[i], Y[i], XP[i], YP[i]    
    x, y = c * x - s * y + h, s * x + c * y + v     -- linearize around old transformation angle
    j = j + 1
    A[j] = {-y * lpq, lpq, 0}
    b[j] = {lpq * (xp - x)}
    j = j + 1
    A[j] = { x * lpq, 0, lpq}
    b[j] = {lpq * (yp - y)}
  end
  return A, b
end

-- (ox, oy) is offset to centre of rotation (centre of image)
local function fast_global_registration(point_pairs, ox, oy)
  
  ox, oy = ox or 0, oy or 0
  local D, delta = 1000, 0.001
  local D2, delta2 = D * D, delta * delta
  local mu = D2
  local theta, h, v = 0, 0, 0    -- initial transform T
  local lpq = {}

  local X, Y, XP, YP = {}, {}, {}, {}
  for i = 1, #point_pairs do 
    local x, y, xp, yp = unpack(point_pairs[i])
    X[i], Y[i], XP[i], YP[i] = x - ox, y - oy, xp - ox, yp - oy   -- offset to image centre
  end
  
  while mu > delta2 do
    local var = 0
    local lpqMean = 0
    for i = 1, #X do                              -- compute line function lpq 
      local x,y, xp,yp = X[i], Y[i], XP[i], YP[i]
      local dx = xp - (h - y * theta + x)
      local dy = yp - (v + x * theta + y)
      local e2 = dx*dx + dy*dy
      lpq[i] = (mu / (mu + e2)) ^2
      lpqMean = lpqMean + lpq[i]
      var = var + e2 * lpq[i]
    end
    local xform = xform_matrix(theta, h, v)
--    theta, h, v = solve(Ab(X, Y, XP, YP, lpq, 0,0,0))     -- update and solve weighted least-squares equations
    theta, h, v = solve(Ab(X, Y, XP, YP, lpq, theta, h, v))     -- update and solve weighted least-squares equations
    xform = xform_matrix(theta, h, v)  * xform                 -- calculate total transform
    theta, h, v = math.asin(xform[2][1]), xform[1][3], xform[2][3]
--    _log("%.3f (%.3f,%.3f)" % {theta * deg, h, v})
    local err = var/#lpq * (lpqMean / #lpq)       -- normalize by weights
    if err < delta2 then 
      return theta, h, v                          -- finish if sufficiently converged
    end
    mu = mu / 1.8                                   -- update graduated non-convexity parameter
  end
  -- no return signals failure
end

-------------------------------
--
-- Calculate transform
--
-- ox, oy are x,y offset to center of rotation
--
function _M.transform(stars, keystars, controls, ox, oy)
  local elapsed = newTimer()

  local point_pairs = NearestNeighbors(stars, keystars, controls)
  if #point_pairs == 0 then return end

  local theta, x,y = fast_global_registration(point_pairs, ox, oy)

  local degrees = theta * deg
  _log(elapsed("%.3f ms, transform: %.3fº  (%.1f, %.1f)", degrees, x,y))
  return theta, x,y, point_pairs
end


return _M

-----
