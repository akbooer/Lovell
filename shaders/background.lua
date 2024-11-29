--
-- background.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.24",
    DESCRIPTION = "background gradient estimation and removal",
  }

-- 2024.10.18  Version 0
-- 2024.10.21  add 'fast' mode, which scales down the image before sampling
-- 2024.11.18  use setBlendMode("replace", "premultiplied")  rather than custom shader to copy
-- 2024.11.24  remove outliers from samples prior to gradient calculation


local _log = require "logger" (_M)

local solver = require "lib.solver"
local newTimer = require "utils".newTimer

local love  = _G.love
local lg    = love.graphics

local function stats(x)
  local mean, mean2 = 0, 0
  local n = #x
  for i = 1, n do
    local y = x[i]
    mean = mean + y
    mean2 = mean2 + y * y
  end
  mean = mean / n                             -- mean
  local sigma2 = mean2 / n - mean  * mean     -- variance
  return mean, math.sqrt(sigma2)
end

  
local flattener = love.graphics.newShader(
[[
    //Vertex Shader
    
    // calculate the vertex background values which are interpolated for the pixel shader
    
    uniform vec3    Offset, Xslope, Yslope;
    uniform float   gradient;
    varying vec3    background;

    vec4 position( mat4 transform_projection, vec4 texture_pos ) {
      background = vec3(Offset
                      + Xslope*gradient * (VertexTexCoord.x - 0.5)         // put origin at image centre
                      + Yslope*gradient * (VertexTexCoord.y - 0.5));
      return transform_projection * texture_pos;
    }
]],[[

    // Pixel Shader
    
    varying vec3 background;
    
    vec4 effect( vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords ){
      vec3 pixel = Texel(texture, texture_coords ) .rgb;
      return vec4(pixel - background, 1.0);
    }
]])

-- TODO: FFI version for speedup
local function getImageSamples(data, N)
  local x,y, r,g,b = {},{}, {},{},{}
  local I = {}
  do -- sample the image on a grid
    local W,H = data:getDimensions()
    local N = math.floor(math.sqrt(N))
    local delta = 1 / N
    local i = 0
    
    for X = delta, 1 - delta, delta do
      for Y = delta, 1 - delta, delta do
        i = i + 1
        x[i], y[i] = X - 0.5, Y - 0.5                     -- put origin at image centre
        local R, G, B = data:getPixel(W * X, H * Y)
        r[i], g[i], b[i] = R, G, B
        I[i] = R + G + B
      end
    end
  end
  
  -- remove outliers from background samples

  local mean, std = stats(I)
  local X,Y, R,G,B = {},{}, {},{},{}
  local j = 0
  for i = 1, #r do
    if math.abs(I[i] - mean) < std / 2 then
      j = j + 1
      X[j], Y[j] = x[i], y[i]
      R[j], G[j], B[j] = r[i], g[i], b[i]
    end
  end
--  _log ("using %d of %d gradient samples" % {#X, #x})
  return X,Y, R,G,B
end


local mini = lg.newCanvas(100, 100, {format = "rgba16f", dpiscale = 1})  -- tiny canvas to sample the much bigger image

local function background(input, output, controls)

  local elapsed = newTimer()
  
  local w,h = input: getDimensions()
  
  lg.setBlendMode("replace", "premultiplied")
  mini: renderTo(lg.draw, input, 0,0,0, 100/w, 100/h)
  lg.setBlendMode("alpha", "alphamultiply")
    
  local Nsamples = 512
  local gradient = controls.gradient.value or 1
  
--  local data = mipBuffer:newImageData(nil, 7, 0,0, w/64,h/64)
  local data = mini:newImageData()
  local x,y, r,g,b = getImageSamples(data, Nsamples) 
  
  local rx, ry, rz
  local gx, gy, gz
  local bx, by, bz
  do -- solve for planar background in RGB
    rz, rx, ry = solver.fitXYZ(x, y, r)   -- note transposition re. solution order
    gz, gx, gy = solver.fitXYZ(x, y, g)
    bz, bx, by = solver.fitXYZ(x, y, b)
  end
  
  local Offset, Xslope, Yslope
  do -- use shader to apply background subtraction
    Offset = {rz , gz , bz };
    Xslope = {rx, gx, bx};
    Yslope = {ry, gy, by};
    flattener: send ("Offset",  Offset);
    flattener: send ("Xslope",  Xslope);
    flattener: send ("Yslope",  Yslope);
    flattener: send ("gradient", gradient)
    
    lg.setShader(flattener) 
    output:renderTo(lg.draw, input)
    lg.setShader()
  
  end
  
--  if controls.Nstack == 1 then
--    _log(elapsed "%.3f mS, gradient removal")

--    _log("RGB offset: %9.4f %9.4f %9.4f" % Offset)
--    _log("RGB xslope: %9.4f %9.4f %9.4f" % Xslope)
--    _log("RGB yslope: %9.4f %9.4f %9.4f" % Yslope)
--  end

  return data, Offset, Xslope, Yslope       -- available for further analysis   
end

  
return background

-----


