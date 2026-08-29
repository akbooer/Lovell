--
-- sampler 
--


local _M = {
    NAME = ...,
    VERSION = "2026.07.18",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Sampler - extract pixels from image at given coordinates",
  }

require "logger" (_M)

local ffi = require "ffi"

local love = _G.love
local lg = love.graphics

-- 2026.07.18  Version 0, using instanced mesh sampling and FFI data retrieval
-- 2026.07.21  use getSystemLimits(), reuse oneD and vertices if right-sized


local MAX = lg.getSystemLimits() .texturesize    -- maximum number of sample points


local sampler = lg.newShader([[
    #pragma language glsl3
    
    attribute float PointIndex; 
    out vec4 v_sampleColor;
    
    uniform Image mainTexture;
    uniform float targetWidth; 

    vec4 position(mat4 transform_projection, vec4 vertex_position) {
        // VertexPosition is provided by LÖVE as a vec4. We just take x and y.
        v_sampleColor = Texel(mainTexture, VertexPosition.xy);
        
        float x_pos = (PointIndex + 0.5) / targetWidth;
        return vec4(x_pos * 2.0 - 1.0, 0.0, 0.0, 1.0);    
    }
    
]], [[

    #pragma language glsl3
    
    in vec4 v_sampleColor;
    
    vec4 effect(vec4 color, Image texture, vec2 tc, vec2 sc) {
        return v_sampleColor; 
    }
    
]])


local oneD
local vertices = {}

local meshFormat = { {"VertexPosition", "float", 2}, {"PointIndex", "float", 1}}


local function sample(image, coords)
    local N = #coords
    if N > MAX then
      error("number of coordinates %d exceeds system limit of %d" % {N, MAX}, 2)
    end
    if N ~= #vertices then
      vertices = table.new(N, 0)
      oneD = lg.newCanvas(N, 1, {format = "rgba32f", dpiscale = 1}) 
    end
  
    -- 1. Build the vertex data table
--    local vertices = table.new(N, 0)
    for i = 1, N do
        vertices[i] = {coords[i][1], coords[i][2], i - 1}
    end

    -- 2. Create the new mesh dynamically
    local sample_mesh = lg.newMesh(meshFormat, vertices, "points", "static")
  
    -- 3. Render
    lg.push("all")
    lg.setColor(1, 1, 1, 1)
    lg.origin()                                     
    lg.setShader(sampler)
  
    sampler:send("mainTexture", image)          
    sampler:send("targetWidth", N)              
  
    lg.setBlendMode("replace", "premultiplied")
    oneD:setFilter("nearest", "nearest")
  
    -- Draw our temporary single mesh
    oneD:renderTo(lg.draw, sample_mesh)
  
    -- 4. Retrieve via FFI
    local data = oneD:newImageData(1, 1, 0, 0, N, 1) 
    local ptr = ffi.cast("float*", data:getFFIPointer()) 
    
    -- pre-allocate table dimensions
    local r, g, b, a = table.new(N, 0), table.new(N, 0), table.new(N, 0), table.new(N, 0)
  
    for i = 1, N do
        local base = (i - 1) * 4            
        r[i] = ptr[base + 0]
        g[i] = ptr[base + 1]
        b[i] = ptr[base + 2]
        a[i] = ptr[base + 3]
    end
    
    -- 5. Clean up
    data:release()
    sample_mesh:release()
    lg.setShader()
    lg.pop()
 
    return r, g, b, a
end


return sample

-----
