--
-- background.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.05",
    DESCRIPTION = "background gradient estimation and removal",
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


local _log = require "logger" (_M)

local solver    = require "lib.solver"
local newTimer  = require "utils".newTimer
local stats     = require "shaders.stats"

local love  = _G.love
local lg    = love.graphics

  
local flattener = love.graphics.newShader(
[[
    //Vertex Shader
    
    // calculate the vertex background values which are interpolated for the pixel shader
    
    uniform vec3    Offset, Xslope, Yslope;
    uniform float   strength;
    varying vec4    background;

    vec4 position( mat4 transform_projection, vec4 texture_pos ) {
      background = vec4(Offset
                      + Xslope*strength * (VertexTexCoord.x - 0.5)         // put origin at image centre
                      + Yslope*strength * (VertexTexCoord.y - 0.5),
                      Offset);
      return transform_projection * texture_pos;
    }
]],[[

    // Pixel Shader
    
    varying vec4 background;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec4 pixel = Texel(texture, texture_coords );
      return pixel - background;
    }
]])

-- TODO: FFI version for speedup
local function getImageSamples(data, N)
  local x,y, r,g,b,a, I = {},{}, {},{},{},{}, {}
  local _, mean, var, var2
  local calc = stats.calc()         -- new stats calculator
  do -- sample the image on a grid
    local W,H = data:getDimensions()
    local N = math.floor(math.sqrt(N))
    local delta = 1 / N
    local i = 0
    
    for X = delta, 1 - delta, delta do
      for Y = delta, 1 - delta, delta do
        i = i + 1
        x[i], y[i] = X - 0.5, Y - 0.5                     -- put origin at image centre
        local R, G, B, A = data:getPixel(W * X, H * Y)
        r[i], g[i], b[i], a[i] = R, G, B, A
        I[i] = R + G + B
        _, _, mean, var = calc(I[i])
      end
    end
  end
  local std = math.sqrt(var)
  
  -- remove outliers from background samples

  local X,Y, R,G,B, A = {},{}, {},{},{}, {}
  local j = 0
  for i = 1, #r do
    if math.abs(I[i] - mean) < std / 2 then
      j = j + 1
      X[j], Y[j] = x[i], y[i]
      R[j], G[j], B[j], A[j] = r[i], g[i], b[i], a[j]
      _, _, _, var2 = calc(R[j] + G[j] + B[j])
    end
  end
  _log ("using %d of %d gradient samples (sdev = %.4f, %.4f)" % {#X, #x, std, math.sqrt(var2 or 0)})
  return X,Y, R,G,B, A
end

local minPoints = 10
local Nsamples = 512

local mini = lg.newCanvas(100, 100, {format = "rgba16f", dpiscale = 1})  -- tiny canvas to sample the much bigger image

--[[
     fitXYZ ( x_values, y_values, z_values )
     fit a plane
     x_values = { x1,x2,x3,...,xn }
     y_values = { y1,y2,y3,...,yn }
     model (  z = a + b * x + c * y )
     returns a, b, c
--]]

local function fitXYZ( x, y, z )	
	local A, b = {}, {}
	for i = 1, #x do
		A[i] = { 1, x[i], y[i] }
		b[i] = { z[i] }
	end
  return solver.solve(A, b)
end

-- calculate input image gradients
function _M.gradients(input)
  local elapsed = newTimer()
  
  local w,h = input: getDimensions()
  
  lg.setBlendMode("replace", "premultiplied")
--  input: setFilter "linear"
  mini: renderTo(lg.draw, input, 0,0,0, 100/w, 100/h)   -- scale image to fit mini canvas
  lg.setBlendMode "alpha"
--  input: setFilter "nearest"
   
--  local data = mipBuffer:newImageData(nil, 7, 0,0, w/64,h/64)
  local data = mini:newImageData()
  local x,y, r,g,b, a = getImageSamples(data, Nsamples) 
  
  local rx, ry, rz = 0, 0, 0
  local gx, gy, gz = 0, 0, 0
  local bx, by, bz = 0, 0, 0
  local ax, ay, az = 0, 0, 0
  
  local gradients
  if #x > minPoints then           -- solve for planar background in RGB
    rz, rx, ry = fitXYZ(x, y, r)   -- note transposition re. solution order
    gz, gx, gy = fitXYZ(x, y, g)
    bz, bx, by = fitXYZ(x, y, b)
    az, az, ay = fitXYZ(x, y, a)
    
    gradients = {
        Offset = {rz, gz, bz, az},
        Xslope = {rx, gx, bx, ax},
        Yslope = {ry, gy, by, ay},
      }
  end
  _log (elapsed "%.3f ms, gradient solved")
--  _log(pretty {gradients = gradients})
  
  return gradients
end

-- just return background offset correction
function _M.offset(input)
  local g = _M.gradients(input)
  local zeros = {0, 0, 0, 0}
  g.Xslope = zeros
  g.Yslope = zeros
  return g
end

-- use shader to apply background subtraction
function _M.remove(workflow, gradients, strength)
  if not gradients then return end
  strength = strength or 1
  local input, output = workflow()
  local g = gradients
  flattener: send ("Offset",  g.Offset);
  flattener: send ("Xslope",  g.Xslope);
  flattener: send ("Yslope",  g.Yslope);
  flattener: send ("strength", strength)
  
  lg.setShader(flattener) 
  lg.setBlendMode("replace", "premultiplied")
  output:renderTo(lg.draw, input)
  lg.reset()
end

  
return _M

-----


