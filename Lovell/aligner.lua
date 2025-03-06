--
--  aligner.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.03.05",
  DESCRIPTION = "image alignment using Fast Global Registration",
}

-- 2024.10.30  Version 0

-- 2025.01.27  return matched point pairs for later display
-- 2025.03.05  use Fast Global Registration algorithm

--[[

  FAST GLOBAL REGISTRATION

  see: 
        Zhou, Qian-Yi, Jaesik Park, and Vladlen Koltun. 
        "Fast global registration." 
        Computer Vision–ECCV 2016: 14th European Conference, Amsterdam, The Netherlands, October 11-14, 2016, 
        Proceedings, Part II 14. Springer International Publishing, 2016.

  also: https://github.com/isl-org/FastGlobalRegistration

--]]


local _log = require "logger" (_M)

local solve     = require "lib.solver" .solve
local newTimer  = require "utils" .newTimer

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
  local maxLumDiff = 1 -- 0.05  
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

  _log(elapsed ("%.3f ms, matched %d stars (max offset = %d)", #starIndex, maxDist))

  return starIndex, keyIndex
end

-- three-way tuple constraint
local function tuple_constraint(starIndex, keyIndex)
  for i = 1, 42 do
    
  end
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
-- FAST GLOBAL REGISTRATION
--

local function Ab(point_pairs, L)
  local A,b = {}, {}    -- equation to solve Ax = b
  L = L or {}           -- vector of lpq weights
  local j = 0
  for i = 1, #point_pairs do
    local lpq = L[i] or 1
    local x,y, xp,yp = unpack(point_pairs[i])
    j = j + 1
    A[j] = {-y * lpq, lpq, 0}
    b[j] = {lpq * (xp - x)}
    j = j + 1
    A[j] = { x * lpq, 0, lpq}
    b[j] = {lpq * (yp - y)}
  end
  return A, b
end

local function fast_global_registration(point_pairs)
  
  local D, delta = 1000, 0.1
  local D2, delta2 = D * D, delta * delta
  local mu = D2
  local theta, h, v = 0, 0, 0    -- initial transform T
  local lpq = {}

  while mu > delta2 do
    local var = 0
    for i = 1, #point_pairs do                    -- compute line function lpq 
      local x,y, xp,yp = unpack(point_pairs[i])
      local dx = xp - (h - y * theta + x)
      local dy = yp - (v + x * theta + y)
      local e2 = dx*dx + dy*dy
      lpq[i] = (mu / (mu + e2)) ^2
      var = var + e2 * lpq[i]
    end

    theta, h, v = solve(Ab(point_pairs, lpq))     -- update and solve weighted least-squares equations
    if var/#lpq < delta2 then break end           -- finish if sufficiently converged
    mu = mu / 2                                   -- update graduated non-convexity parameter
  end

  return theta, h, v
end

-------------------------------
--
-- Calculate transform
--

function _M.transform(stars, keystars, controls)
  local elapsed = newTimer()

  local point_pairs = NearestNeighbors(stars, keystars, controls)
  if #point_pairs == 0 then return end

  local theta, x,y = fast_global_registration(point_pairs)

  local degrees = theta * 180 / math.pi
  _log(elapsed("%.3f ms, transform: %.3fº  (%.1f, %.1f)", degrees, x,y))
  return theta, x,y, point_pairs
end


return _M

-----
