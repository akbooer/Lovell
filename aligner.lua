--
--  aligner.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.10.30",
    DESCRIPTION = "image alignment",
  }

-- 2024.10.30

local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer


-- nearest neighbour to each of the keystars
-- possible that no match is found (if intensities too different)
-- so returned matches array may contain nils
local function matchPairs(stars, keystars, params)
  params = params or {}
  local maxDist = params.maxDist or math.huge
  local maxLumDiff = params.maxLumDiff or 1
  
  local maxDist2 = maxDist * maxDist
  local maxLumDiff2 = maxLumDiff * maxLumDiff
  
	local matches = {}
  local dist = {}
  local elapsed= newTimer()
  
  for i, a in ipairs(keystars) do
    local mindist2 = maxDist2
    local x1, y1, l1 = a[1], a[2], a[3]
    for _, b in ipairs(stars) do
      local x2, y2, l2 = b[1], b[2], b[3]
      local dist2 = (x1 - x2)^2 + (y1 - y2)^2
      local delta = (l1 - l2)^2
      if dist2 < mindist2 and delta < maxLumDiff2 then
        mindist2 = dist2
        matches[i] = b
      end
    dist[i] = math.sqrt(mindist2)
    end
  end
  
  _log(elapsed ("%.3f ms, matched %d stars", #matches))

	return matches
end


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

  return rot_angle, translation_x, translation_y
end


function _M.transform(stars, keystars)
  local params = {maxDist = 35, maxLumDif = 0.1}

  local matches = matchPairs(stars, keystars, params)
  
  local elapsed = newTimer()
  local point_pairs = {}
  for i = 1, #keystars do
    local matched = matches[i]
    if matched then
      local key = keystars[i]
      point_pairs[#point_pairs+1] = {matched[1], matched[2], key[1], key[2]}  -- (x,y), (x',y')
    end
  end
  
  if #point_pairs == 0 then return end
  
  local theta, x,y = point_based_matching(point_pairs)
  local degrees = theta * 180 / math.pi
  _log(elapsed("%.3f ms, transform: %.3fº  (%.1f, %.1f)", degrees, x,y))
  return theta, x,y
end

return _M

-----
