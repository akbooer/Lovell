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

-- nearest neighbour to each of the keystars
-- possible that no match is found (if intensities too different)
-- returned matches array contains pairs of INDICES of matching stars and keystars
local function matchPairs(stars, keystars, controls)
  local maxDist = controls.workflow.offset.value
  local maxLumDiff = 0.1
  
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
      local dist2 = (x1 - x2)^2 + (y1 - y2)^2
      local delta = (l1 - l2)^2
      if dist2 < mindist2 and delta < maxLumDiff2 then
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


local function icp(reference_points, points, max_iterations, distance_threshold, 
  convergence_translation_threshold, convergence_rotation_threshold, point_pairs_threshold)
--[[
    An implementation of the Iterative Closest Point algorithm that matches a set of M 2D points to another set
    of N 2D (reference) points.

    :param reference_points: the reference point set as a numpy array (N x 2)
    :param points: the point that should be aligned to the reference_points set as a numpy array (M x 2)
    :param max_iterations: the maximum number of iteration to be executed
    :param distance_threshold: the distance threshold between two points in order to be considered as a pair
    :param convergence_translation_threshold: the threshold for the translation parameters (x and y) for the
                                              transformation to be considered converged
    :param convergence_rotation_threshold: the threshold for the rotation angle (in rad) for the transformation
                                               to be considered converged
    :param point_pairs_threshold: the minimum number of point pairs the should exist
    :param verbose: whether to print informative messages about the process (default: False)
    :return: correspondence
    
    ]]

--[=[

    for iter_num in range(max_iterations):

        closest_point_pairs = []  # list of point correspondences for closest point rule
        correspondence = []

        distances, indices = nbrs.kneighbors(points)
        for nn_index in range(len(distances)):
            if distances[nn_index][0] < distance_threshold:
                closest_point_pairs.append((points[nn_index], reference_points[indices[nn_index][0]]))
                correspondence.append((nn_index, indices[nn_index][0]))

        # if only few point pairs, stop process
        if len(closest_point_pairs) < point_pairs_threshold:
            break

        # compute translation and rotation using point correspondences
        closest_rot_angle, closest_translation_x, closest_translation_y = point_based_matching(closest_point_pairs)
        if closest_rot_angle is None or closest_translation_x is None or closest_translation_y is None:
            break

        # transform 'points' (using the calculated rotation and translation)
        c, s = math.cos(closest_rot_angle), math.sin(closest_rot_angle)
        rot = np.array([[c, -s],
                        [s, c]])
        aligned_points = np.dot(points, rot.T)
        aligned_points[:, 0] += closest_translation_x
        aligned_points[:, 1] += closest_translation_y

        # update 'points' for the next iteration
        points = aligned_points

        # check convergence
        if (abs(closest_rot_angle) < convergence_rotation_threshold) \
                and (abs(closest_translation_x) < convergence_translation_threshold) \
                and (abs(closest_translation_y) < convergence_translation_threshold):
            break

    return correspondence

]=]

  max_iterations = max_iterations or 100
  distance_threshold = distance_threshold or 0.3
  convergence_translation_threshold = convergence_translation_threshold or 1e-3
  convergence_rotation_threshold = convergence_rotation_threshold or 1e-4
  point_pairs_threshold = point_pairs_threshold or 10

  local abs = math.abs

  local params = {maxDist = distance_threshold}
  local closest_rot_angle, closest_translation_x, closest_translation_y 
  local final_rot_angle, final_translation_x, final_translation_y = 0, 0, 0

  
  for iter = 1, max_iterations do
    _log ("ICP #", iter)

    -- list of point correspondences for closest point rule
    local closest_point_pairs, indices = NearestNeighbors(points, reference_points, params)
    _log('', "#closest point pairs: ", #closest_point_pairs)
    -- if only few point pairs, stop process
    if #closest_point_pairs < point_pairs_threshold then
      break
    end

    -- compute translation and rotation using point correspondences
    closest_rot_angle, closest_translation_x, closest_translation_y = point_based_matching(closest_point_pairs)
    _log('', string.format ("iteration %d, theta = %.3f, (x,y) = (%.2f,%.2f)", 
        iter, closest_rot_angle, closest_translation_x, closest_translation_y))
    if not closest_rot_angle then
      break
    end
    
    -- transform 'points' (using the calculated rotation and translation)
    local c, s = math.cos(closest_rot_angle), math.sin(closest_rot_angle)
  --        local rot = np.array({ {c, -s},
  --                              {s,  c} })
--    local aligned_points = {}
    local starIndex = indices[1]
    for i = 1, #points do
      local point = points[i]
      local x, y = point[1], point[2]
      point[1] = x * c + y * s - closest_translation_x
      point[2] = y * c - x * s - closest_translation_y
--      aligned_points[i] = point
    end
    
    -- update 'points' for the next iteration
--    points = aligned_points

    -- update transformation history
    final_rot_angle = final_rot_angle + closest_rot_angle
    local x, y = final_translation_x, final_translation_y
    final_translation_x = x * c + x * s + closest_translation_x
    final_translation_y = y * c - y * s + closest_translation_y

    -- check convergence
    if (abs(closest_rot_angle) < convergence_rotation_threshold + 1) 
          and (abs(closest_translation_x) < convergence_translation_threshold) 
          and (abs(closest_translation_y) < convergence_translation_threshold) then
      break
    end
    
  end
  
  _log(string.format ("FINAL: (x,y) = (%.2f,%.2f), theta = %.3f", 
      final_translation_x, final_translation_y, final_rot_angle))

  return final_rot_angle, final_translation_x, final_translation_y 
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

--function _M.transform2(stars, keystars)
  
--  do return _M.transform(stars, keystars) end   -- * * * * *
  
--  return icp(keystars, stars, 100, 35, 0.1, 0.001)
--end



-------------------------------
--
-- TEST from https://github.com/richardos/icp/tree/master
    
function _M.TEST()

  local matrix = require "lib.matrix"

  local T = 'T'   -- transpose operator

  -- set seed for reproducible results
  math.randomseed(12345)

  -- create a set of points to be the reference for ICP
  local reference_points = {}
  for i = 1, 50 do
    local x = math.random() * 1000
    local y = math.random() * 1000
    reference_points[i] = {x, y}
  end
  reference_points = matrix(reference_points)

  -- transform the set of reference points to create a new set of
  -- points for testing the ICP implementation

  -- 1. remove some points
  local points_to_be_aligned = {}
  for i = 1, 47 do
    points_to_be_aligned[i] = reference_points[i]
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
  local a,b = 8, -5
  local offset = {{a, b}}
  for i = 1, #points_to_be_aligned do
    offset[i] = offset[1]
  end
  offset = matrix(offset)
  print("offset", a, b, "angle", theta)
  points_to_be_aligned = points_to_be_aligned + offset 

--  print(points_to_be_aligned)
--  print "----"
--  print(reference_points)
--  print "----"

  -- icp(reference_points, points, max_iterations, distance_threshold, 
  --         convergence_translation_threshold, convergence_rotation_threshold, point_pairs_threshold)
  local transformation_history, aligned_points = icp(reference_points, points_to_be_aligned, 20, 20, .04)

  -- show results
--    plt.plot(reference_points[:, 0], reference_points[:, 1], 'rx', label='reference points')
--    plt.plot(points_to_be_aligned[:, 0], points_to_be_aligned[:, 1], 'b1', label='points to be aligned')
--    plt.plot(aligned_points[:, 0], aligned_points[:, 1], 'g+', label='aligned points')
--    plt.legend()
--    plt.show()

end

--_M.TEST()

-----

return _M

-----
