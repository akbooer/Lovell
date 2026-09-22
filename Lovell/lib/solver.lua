--
--  solution methods
--

-- 2026.09.09  add closed-form fitPlane() solver in addition to generic matrix least-squares

local matrix = require "lib.matrix"
  
local T = 'T'   -- transpose operator

getmetatable(matrix {}).__concat = function(self, mat) return self:concath(mat) end -- add missing '..' meta function

    
local _M = {}


-- solve Ax = b
function _M.solve(A, b)
	A = matrix(A)
	b = matrix(b)

  local AT = A ^ T
  local ATA = AT * A
  local ATb = AT * b
  local ATAATb = ATA .. ATb
 
 	ATAATb: dogauss()             -- Gauss-Jordan Method, result is in last column

  local abc = ATAATb ^ T
  return unpack( abc[#abc] )    -- result is in last row

end 


-------------------------------
--
-- Closed-form solution method for z = a + bx + cy
--
-- Fits an inclined plane z(x, y) = a*x + b*y + c to a set of random 3D points.
-- Input: points = { {x=1.2, y=3.4, z=10.1}, {x=..., y=..., z=...}, ... }
--         OR array format: { {1.2, 3.4, 10.1}, ... }
-- Returns: a (x-slope), b (y-slope), c (z-offset at x=0, y=0)
--          Returns nil if points are colinear or degenerate (det close to 0)
--------------------------------------------------------------------------------
function _M.fitPlane(points)
  local n = #points
  if n < 3 then
    return nil, "Requires at least 3 points to define a plane"
  end

  -- Pass 1: Compute centroids (mean x, y, z)
  local sumX, sumY, sumZ = 0, 0, 0
  for i = 1, n do
    local p = points[i]
    sumX = sumX + (p.x or p[1])
    sumY = sumY + (p.y or p[2])
    sumZ = sumZ + (p.z or p[3])
  end

  local meanX = sumX / n
  local meanY = sumY / n
  local meanZ = sumZ / n

  -- Pass 2: Accumulate centered moments
  local Suu, Svv, Suv = 0, 0, 0
  local Suz, Svz = 0, 0

  for i = 1, n do
    local p = points[i]
    local u = (p.x or p[1]) - meanX
    local v = (p.y or p[2]) - meanY
    local dz = (p.z or p[3]) - meanZ

    Suu = Suu + u * u
    Svv = Svv + v * v
    Suv = Suv + u * v
    Suz = Suz + u * dz
    Svz = Svz + v * dz
  end

  -- Determinant of the centered 2x2 covariance matrix
  local det = Suu * Svv - Suv * Suv

  -- Check for degenerate geometry (e.g., all points lying along a single line)
  if math.abs(det) < 1e-12 then
    return nil, "Degenerate point layout (colinear points)"
  end

  -- Analytical closed-form solution via Cramer's Rule
  local a = (Svv * Suz - Suv * Svz) / det
  local b = (Suu * Svz - Suv * Suz) / det

  -- Un-center to find global z-intercept c at origin (x=0, y=0)
  local c = meanZ - a * meanX - b * meanY

  return a, b, c
end

--------------------------------------------------------------------------------
-- Convenience evaluator for the fitted plane
--------------------------------------------------------------------------------
function _M.evaluate(x, y, a, b, c)
  return a * x + b * y + c
end


return _M

-----
