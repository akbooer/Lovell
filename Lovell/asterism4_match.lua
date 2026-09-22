--
-- asterism4_match.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.09",
  AUTHOR = "AK Booer",
  DESCRIPTION = "asterism matcher for alignment with invariant validation (tetrads)",
}

local _log = require "logger" (_M)
local newTimer = require "utils" .newTimer

-------------------------------
-- Build catalog of tetrad descriptors using squared side lengths & invariants
-------------------------------
function _M.buildCatalog(stars, maxStars)
  local elapsed = newTimer()
  local n = math.min(#stars, maxStars or 25)
  local tetrads = {}

  for i = 1, n - 3 do
    local p1 = stars[i]
    for j = i + 1, n - 2 do
      local p2 = stars[j]
      local d12_sq = (p1.x - p2.x)^2 + (p1.y - p2.y)^2

      for k = j + 1, n - 1 do
        local p3 = stars[k]
        local d23_sq = (p2.x - p3.x)^2 + (p2.y - p3.y)^2
        local d31_sq = (p3.x - p1.x)^2 + (p3.y - p1.y)^2

        for l = k + 1, n do
          local p4 = stars[l]
          local d14_sq = (p1.x - p4.x)^2 + (p1.y - p4.y)^2
          local d24_sq = (p2.x - p4.x)^2 + (p2.y - p4.y)^2
          local d34_sq = (p3.x - p4.x)^2 + (p3.y - p4.y)^2

          -- Local tuples for all 6 pairwise edges in a 4-star complete graph: { lenSq, pOpp }
          -- pOpp holds the vertex OPPOSITE to the edge in the primary 4-star set
          local t1_lenSq, t1_pOpp = d12_sq, p3
          local t2_lenSq, t2_pOpp = d23_sq, p1
          local t3_lenSq, t3_pOpp = d31_sq, p2
          local t4_lenSq, t4_pOpp = d14_sq, p4
          local t5_lenSq, t5_pOpp = d24_sq, p4
          local t6_lenSq, t6_pOpp = d34_sq, p4

          -- 6-element sorting network: t1 >= t2 >= t3 >= t4 >= t5 >= t6
          if t1_lenSq < t2_lenSq then t1_lenSq, t2_lenSq = t2_lenSq, t1_lenSq; t1_pOpp, t2_pOpp = t2_pOpp, t1_pOpp end
          if t3_lenSq < t4_lenSq then t3_lenSq, t4_lenSq = t4_lenSq, t3_lenSq; t3_pOpp, t4_pOpp = t4_pOpp, t3_pOpp end
          if t5_lenSq < t6_lenSq then t5_lenSq, t6_lenSq = t6_lenSq, t5_lenSq; t5_pOpp, t6_pOpp = t6_pOpp, t5_pOpp end
          if t1_lenSq < t3_lenSq then t1_lenSq, t3_lenSq = t3_lenSq, t1_lenSq; t1_pOpp, t3_pOpp = t3_pOpp, t1_pOpp end
          if t2_lenSq < t5_lenSq then t2_lenSq, t5_lenSq = t5_lenSq, t2_lenSq; t2_pOpp, t5_pOpp = t5_pOpp, t2_pOpp end
          if t4_lenSq < t6_lenSq then t4_lenSq, t6_lenSq = t6_lenSq, t4_lenSq; t4_pOpp, t6_pOpp = t6_pOpp, t4_pOpp end
          if t2_lenSq < t3_lenSq then t2_lenSq, t3_lenSq = t3_lenSq, t2_lenSq; t2_pOpp, t3_pOpp = t3_pOpp, t2_pOpp end
          if t4_lenSq < t5_lenSq then t4_lenSq, t5_lenSq = t5_lenSq, t4_lenSq; t4_pOpp, t5_pOpp = t5_pOpp, t4_pOpp end
          if t3_lenSq < t4_lenSq then t3_lenSq, t4_lenSq = t4_lenSq, t3_lenSq; t3_pOpp, t4_pOpp = t4_pOpp, t3_pOpp end

          local a2 = t1_lenSq
          local b2 = t2_lenSq
          local c2 = t3_lenSq
          local d2 = t4_lenSq
          local e2 = t5_lenSq

          -- Reject collinear or degenerate star tetrads
          if a2 > 1e-6 and b2 > 1e-6 then
            -- INVARIANT 1: 2D Chirality / Handedness (Signed area via cross product)
            -- Vector from vertex 4 to vertex 1 and vertex 2
            local v1x, v1y = t2_pOpp.x - t1_pOpp.x, t2_pOpp.y - t1_pOpp.y
            local v2x, v2y = t3_pOpp.x - t1_pOpp.x, t3_pOpp.y - t1_pOpp.y
            local cross = (v1x * v2y) - (v1y * v2x)
            local chirality = cross > 0 and 1 or -1

            -- INVARIANT 2: Relative Flux Ratios across all 4 vertices
            local f1 = t1_pOpp.flux or 1.0
            local f2 = t2_pOpp.flux or 1.0
            local f3 = t3_pOpp.flux or 1.0
            local f4 = t4_pOpp.flux or 1.0
            local totalFlux = f1 + f2 + f3 + f4

            tetrads[#tetrads + 1] = {
              xSq = b2 / a2,
              ySq = c2 / a2,
              zSq = d2 / a2,
              wSq = e2 / a2,
              chirality = chirality,
              -- Normalized vertex flux invariants:
              fRatios = { f1 / totalFlux, f2 / totalFlux, f3 / totalFlux, f4 / totalFlux },
              stars = { t1_pOpp, t2_pOpp, t3_pOpp, t4_pOpp }
            }
          end
        end
      end
    end
  end

  _log(elapsed("%.3f ms, built star descriptor catalog, (%d entries)", #tetrads))
  return tetrads
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

  -- Reduced candidate star limit default (20 stars = 4,845 tetrads vs 30 stars = 27,405 tetrads)
  local refCatalog = _M.buildCatalog(normRef, 20)
  local tgtCatalog = _M.buildCatalog(normTgt, 20)

  local votes = {}

  for i = 1, #refCatalog do
    local t1 = refCatalog[i]
    for j = 1, #tgtCatalog do
      local t2 = tgtCatalog[j]

      -- 1. Quad side ratio box check (4 invariant ratios)
      if math.abs(t1.xSq - t2.xSq) < tol and
         math.abs(t1.ySq - t2.ySq) < tol and
         math.abs(t1.zSq - t2.zSq) < tol and
         math.abs(t1.wSq - t2.wSq) < tol then
        
        -- 2. Chirality check (must have identical 2D orientation)
        if t1.chirality == t2.chirality then
          
          -- 3. Flux ratio invariant check across 4 stars
          local fluxMatch = math.abs(t1.fRatios[1] - t2.fRatios[1]) < fTol and
                            math.abs(t1.fRatios[2] - t2.fRatios[2]) < fTol and
                            math.abs(t1.fRatios[3] - t2.fRatios[3]) < fTol and
                            math.abs(t1.fRatios[4] - t2.fRatios[4]) < fTol

          if fluxMatch then
            for v = 1, 4 do
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

  -- Collect consensus candidate pairs (requiring higher vote threshold due to tetrad selectivity)
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
