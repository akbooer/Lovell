--
-- background.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.09.09",
    DESCRIPTION = "background gradient and black/white point estimation",
  }

-- 2024.10.18  Version 0
-- 2024.10.21  add 'fast' mode, which scales down the image before sampling
-- 2024.11.18  use setBlendMode("replace", "premultiplied")  rather than custom shader to copy
-- 2024.11.24  remove outliers from samples prior to gradient calculation
-- 2024.12.09  separate solution and application functions
-- 2024.12.16  use workflow() buffers

-- 2025.01.29  integrate into workflow
-- 2025.03.03  move fitXYZ() here and use general solver.solve() for A x = b
-- 2025.03.16  use external parameter for strength of gradient in remove()
-- 2025.05.04  add alpha channel stats for RGBL, use stats.calc()
-- 2025.05.05  rename calculate() to gradients() and add offset()
-- 2025.05.19  fix nil return in offset()
-- 2025.05.28  fix vec4 Offset, Xslope, Yslope in vertex shader

-- 2026.03.31  make mini canvas rgba32f (was 16)
-- 2026.05.04  add vignetting to background correction, correct alpha channel gradient calculation
-- 2026.05.07  background black point selection based on Jocular/Canisp's 20% - 80% filtering
-- 2026.07.04  use workflow:shadeWith()

-- 2026.07.18  Version 2, using shaders.sampler (instanced mesh sampling and FFI data retrieval)
-- 2026.08.06  workflow.dummyMesh for full-screen rendering
-- 2026.08.28  restructure, adding quartiles(), to remove redundant calculations
-- 2026.09.09  use closed-form fitPlane() solver rather than generic matrix least-squares


local _log = require "logger" (_M)

--local ffi = require "ffi"

local sample    = require "shaders.sampler"
local fitPlane  = require "lib.solver" .fitPlane
local matrix    = require "lib.matrix"
local vector    = require "lib.vector"
local newTimer  = require "utils".newTimer


local SAMPLE_SIZE = 100           -- number of samples in each row/column (so N * N total)

-----

-- factory method for index
local Index do  
  local index = {}    -- reuse index if right length...
  function Index(n)
    if #index ~= n then
      index = table.new(n, 0)   -- ...else allocate new one
    end
    return index
  end  
end

local function index_channel(channel)
  local c = channel
  local index = Index(#c)
  for i = 1, #c do index[i] = i end                            -- build table of indices
  table.sort(index, function(a,b) return c[a] < c[b] end)       -- sort by selected channel value
  return index
end

-- fitXYZ ( x_values, y_values, z_values )
--     fit a plane: z = a + b * x + c * y 
--     returns {a, b, c}
local function fitXYZ_indexed( coords, z, index )	
  local N = #index
  -- remove outliers from background samples (ignore top and bottom 20%)
  local twenty, eighty = math.floor(0.2 * N), math.floor(0.8 * N)    -- 20% - 80% range
  local xyz = {}
  for j = twenty, eighty do
    local i = index[j]
    local x, y = unpack(coords[i])
    local v = z[i]
    xyz[#xyz+1] = {x, y, v}
	end
  local a, b, c = fitPlane(xyz)
  return {c, a, b}
end

 
-- quartiles, including min and max
local function quartiles(z, index)
  local N = #z
  local I = {1, N/4, N/2, 3*N/4, N}
  local q = {}
  for i, j in ipairs(I) do
    q[i] = z[index[math.floor(j)]]
  end
  return q
end


local function generate_mesh()
  local margin = 0.2    -- 20% all the way around
  local stride = (1 - 2 * margin) / SAMPLE_SIZE
  
  local coords = {} 
  for u = margin, 1 - margin, stride do
    for v = margin, 1 - margin, stride do
      coords[#coords+1] = {u, v}
    end
  end
  return coords
end

local coords = generate_mesh()    -- mesh size independent of image dimensions

-- calculate input image gradients for RGB channels
local function background_calc(self, input, quiet)             -- self is workflow
  local elapsed = newTimer()
  local channelCount = self: getChannelCount()
  if not quiet then 
    _log ("sampling %d image channels..." % channelCount)
  end
  local rgba = {sample(input, coords)}    -- returns R G B A channels separately
   
  local BP, WP, MEDIAN = vector{0,0,0,0}, vector{1,1,1,1}, vector{0,0,0,0}
  local QUARTILES, MAD = {}, vector{0,0,0,0}
  local LINEAR = {}
  
  local Linear, Qs
  local X = {'R','G','B','L'}
  for i = 1, 4 do
--  for i = 1, channelCount do
    local channel = rgba[i]                 -- select one of {r,g,b,a}
    local index = index_channel(channel)
    
    -- linear gradients and quartiles
    local Plane
    Linear, Plane = fitXYZ_indexed(coords, channel, index)
    Qs = quartiles(channel, index)         -- {min, Q1, median, Q3, max} 
     
    -- calculate significant thresholds
    local median = Qs[3]
    local MADleft = median - Qs[2]        -- median value of MADleft
    local max = Qs[5]
    
    -- save image processing info
    BP[i] = math.max(0.0, median - 4 * MADleft)
    WP[i] = max
    MEDIAN[i] = median
    LINEAR[i] = Linear 
    MAD[i] = MADleft
    QUARTILES[X[i]] = Qs
    
  end
  
  -- inverse variance RGB weights (possibly for stack or colour mixing)
  -- actually, sdev = 1.4826 * MADleft [constant holds for normal noise distribution]
  --- ... but inVar values still correct because they're normalised to sum to unity
  local Var  = MAD ^ 2                -- 
  local inVar = Var: ones() / Var
  for i = 1, 4 do 
    inVar[i] = Var[i] > 0 and inVar[i] or 0 
  end
  
  local background = {
    BP = BP, WP = WP, 
    MEDIAN = MEDIAN, MAD = MAD,
    QUARTILES = QUARTILES,
    Linear = matrix (LINEAR) ^ 'T',     -- transpose matrix
    inVAR = inVar / inVar: sum()}       -- scale to unity sum
  
  for _, v in ipairs(background.Linear) do
    vector(v)
  end
    
  if not quiet then
    _log("RGBL black points: %.4f, %.4f, %.4f, %.4f" % BP)
    _log("RGBL white points: %.4f, %.4f, %.4f, %.4f" % WP)
    _log(pretty(background))
    _log (elapsed ("%.3f ms, gradient solved using %d image samples", #coords))
  end

  return background
end

  
return background_calc

-----


