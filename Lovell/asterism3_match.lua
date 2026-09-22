--
-- asterism_match.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.07",
  AUTHOR = "AK Booer",
  DESCRIPTION = "asterism matcher for alignment with invariant validation",
}

local _log = require "logger" (_M)
local newTimer = require "utils" .newTimer

-------------------------------
-- Build catalog of triangle descriptors using squared side lengths & invariants
-------------------------------
function _M.buildCatalog(stars, maxStars)
  local elapsed = newTimer()
  local n = math.min(#stars, maxStars or 25)
  local triangles = {}

  for i = 1, n - 2 do
    local p1 = stars[i]
    for j = i + 1, n - 1 do
      local p2 = stars[j]
      local d12_sq = (p1.x - p2.x)^2 + (p1.y - p2.y)^2

      for k = j + 1, n do
        local p3 = stars[k]
        local d23_sq = (p2.x - p3.x)^2 + (p2.y - p3.y)^2
        local d31_sq = (p3.x - p1.x)^2 + (p3.y - p1.y)^2

        -- Local tuples: { lenSq, pOpp }
        local t1_lenSq, t1_pOpp = d12_sq, p3
        local t2_lenSq, t2_pOpp = d23_sq, p1
        local t3_lenSq, t3_pOpp = d31_sq, p2

        -- Fast 3-element sorting network: t1 >= t2 >= t3 (a >= b >= c)
        if t1_lenSq < t2_lenSq then 
          t1_lenSq, t2_lenSq = t2_lenSq, t1_lenSq 
          t1_pOpp,  t2_pOpp  = t2_pOpp,  t1_pOpp 
        end
        if t2_lenSq < t3_lenSq then 
          t2_lenSq, t3_lenSq = t3_lenSq, t2_lenSq 
          t2_pOpp,  t3_pOpp  = t3_pOpp,  t2_pOpp 
        end
        if t1_lenSq < t2_lenSq then 
          t1_lenSq, t2_lenSq = t2_lenSq, t1_lenSq 
          t1_pOpp,  t2_pOpp  = t2_pOpp,  t1_pOpp 
        end

        local a2 = t1_lenSq
        local b2 = t2_lenSq
        local c2 = t3_lenSq

        -- Reject collinear or degenerate star triplets
        if a2 > 1e-6 and b2 > 1e-6 then
          -- INVARIANT 1: 2D Chirality / Handedness (Signed area via cross product)
          -- Compute orientation from vertex 3 (t1_pOpp) to vertex 1 (t2_pOpp) and 2 (t3_pOpp)
          local v1x, v1y = t2_pOpp.x - t1_pOpp.x, t2_pOpp.y - t1_pOpp.y
          local v2x, v2y = t3_pOpp.x - t1_pOpp.x, t3_pOpp.y - t1_pOpp.y
          local cross = (v1x * v2y) - (v1y * v2x)
          local chirality = cross > 0 and 1 or -1

          -- INVARIANT 2: Relative Flux Ratios (if flux/intensity is provided)
          local f1 = t1_pOpp.flux or 1.0
          local f2 = t2_pOpp.flux or 1.0
          local f3 = t3_pOpp.flux or 1.0
          local totalFlux = f1 + f2 + f3

          triangles[#triangles + 1] = {
            xSq = b2 / a2,
            ySq = c2 / a2,
            chirality = chirality,
            -- Normalized vertex flux invariants:
            fRatios = { f1 / totalFlux, f2 / totalFlux, f3 / totalFlux },
            stars = { t1_pOpp, t2_pOpp, t3_pOpp }
          }
        end
      end
    end
  end

  _log(elapsed("%.3f ms, built star descriptor catalog, (%d entries)", #triangles))
  return triangles
end

-------------------------------
-- Match star candidates between two frames
-------------------------------
function _M.match(refStars, targetStars, toleranceSq, fluxTol)
  local tol = toleranceSq or 0.015
  local fTol = fluxTol or 0.15 -- 15% tolerance on relative star brightness

  local function normalizeStars(starList)
    local normalized = {}
    for i = 1, #starList do
      local s = starList[i]
      normalized[i] = {
        id = i,
        x = s.x or s[1],
        y = s.y or s[2],
        flux = s.flux or s.intensity or s[3] or 1.0
      }
    end
    return normalized
  end

  local normRef = normalizeStars(refStars)
  local normTgt = normalizeStars(targetStars)

  local refCatalog = _M.buildCatalog(normRef, 30)
  local tgtCatalog = _M.buildCatalog(normTgt, 30)

  local votes = {}

  for i = 1, #refCatalog do
    local t1 = refCatalog[i]
    for j = 1, #tgtCatalog do
      local t2 = tgtCatalog[j]

      -- 1. Side ratio box check
      if math.abs(t1.xSq - t2.xSq) < tol and math.abs(t1.ySq - t2.ySq) < tol then
        
        -- 2. Chirality check (must have identical 2D orientation)
        if t1.chirality == t2.chirality then
          
          -- 3. Flux ratio invariant check
          local fluxMatch = math.abs(t1.fRatios[1] - t2.fRatios[1]) < fTol and
                            math.abs(t1.fRatios[2] - t2.fRatios[2]) < fTol and
                            math.abs(t1.fRatios[3] - t2.fRatios[3]) < fTol

          if fluxMatch then
            for v = 1, 3 do
              local rId = t1.stars[v].id
              local tId = t2.stars[v].id
              
              local key = rId * 100000 + tId
              votes[key] = (votes[key] or 0) + 1
            end
          end
        end
      end
    end
  end

  -- Collect consensus candidate pairs
  local candidatePairs = {}
  for key, count in pairs(votes) do
    if count >= 3 then
      local rId = math.floor(key / 100000)
      local tId = key % 100000
      candidatePairs[#candidatePairs + 1] = {
        rId = rId,
        tId = tId,
        votes = count
      }
    end
  end

  table.sort(candidatePairs, function(a, b) return a.votes > b.votes end)

  -- Enforce 1-to-1 unique star matching
  local usedRef = {}
  local usedTgt = {}
  local pointPairs = {}

  for i = 1, #candidatePairs do
    local pair = candidatePairs[i]
    local rId = pair.rId
    local tId = pair.tId

    if not usedRef[rId] and not usedTgt[tId] then
      usedRef[rId] = true
      usedTgt[tId] = true

      local pRef = normRef[rId]
      local pTgt = normTgt[tId]
      pointPairs[#pointPairs + 1] = { pRef.x, pRef.y, pTgt.x, pTgt.y }
    end
  end

  return pointPairs
end

return _M

-----
