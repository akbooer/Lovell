--
--  aligner.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.24",
  DESCRIPTION = "image alignment using Fast Global Registration [Qian-Yi Zhou 2016]",
}

-- 2024.10.30  Version 0

-- 2025.01.27  return matched point pairs for later display
-- 2025.03.05  use Fast Global Registration algorithm
-- 2025.03.09  use image centre as rotation origin
-- 2025.03.11  linearize angle around previous transformation estimate (as per the paper)
-- 2025.04.02  remove tuple check code and add simple test routine

-- 2026.10.24  remove unused star alignment parameters

--[[

  FAST GLOBAL REGISTRATION

  see: 
        Qian-Yi Zhou, Jaesik Park, and Vladlen Koltun, 
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
  local D, delta = 1000, 0.01
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
--    theta, h, v = solve(Ab(X, Y, XP, YP, lpq, 0,0,0))           -- update and solve weighted least-squares equations
    theta, h, v = solve(Ab(X, Y, XP, YP, lpq, theta, h, v))    -- update and solve weighted least-squares equations
    xform = xform_matrix(theta, h, v)  * xform                  -- calculate total transform
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
function _M.transform(stars, keystars, ox, oy)
  local elapsed = newTimer()

  local point_pairs = require "asterism4_match" .match (keystars, stars)
  
  if #point_pairs == 0 then return end

  local theta, x,y = fast_global_registration(point_pairs, ox, oy)

  local degrees = theta * deg
  _log(elapsed("%.3f ms, transform: %.3fº  (%.1f, %.1f)", degrees, x,y))
  return {theta, x,y}, point_pairs
end

-- return null transformation
function _M.null()
  return {0, 0, 0}
end


-- TEST

function _M.TEST()
  local theta, h, v = 0.5, 4, 7   -- angle in radians
  local X = { {0,0}, {100,100}, {20,50} }
  local Y = {}
  for i, p in ipairs(X) do
    local x, y = p[1], p[2]
    local c, s = math.cos(theta), math.sin(theta)
    local x2, y2 = c * x - s * y + h, s * x + c * y + v
    Y[i] = {x2, y2}
  end
  print("actual:", theta, h, v)
  print("found:", pretty(_M.transform(Y, X, 50)))
end

--_M.TEST()

return _M

-----
