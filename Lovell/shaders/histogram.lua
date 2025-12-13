--
-- histogram.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.11.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "image histogram using SHADER",
  }

-- 2025.11.21  Version 0


local _log = require "logger" (_M)

local newTimer = require "utils" .newTimer

local lg = require "love.graphics"


local vertex = [[

uniform Image tex;

vec4 position(mat4 _, vec4 vertex_position) {
    vec4 color = Texel(tex, vertex_position.xy);

    // 2. Calculate Luma (Intensity)
    float luma = dot(color.rgb, vec3(0.299, 0.587, 0.114));

    // 3. Map Luma (0.0 to 1.0) to Clip Space X (-1.0 to 1.0)
    // This moves the vertex to the correct "bin" column on screen
    float x_ndc = (luma * 2.0) - 1.0;

    // 4. Output final position
    // We lock Y to 0.0 (center of our 1px high canvas)
    return vec4(x_ndc, 0.0, 0.0, 1.0);
  }
]]

local pixel = [[

const vec4 one = vec4(1.0, 0.0, 0.0, 1.0);    // With additive blending, this counts the pixels.

vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
    return one;
  }
]]

local shader = lg.newShader (vertex, pixel)


local img, histCanvas
local pointMesh, histogramData

local function load()
    -- 1. Load Image
    img = love.graphics.newImage("test_image.png")
    local w, h = img:getDimensions()

    -- 2. Create Histogram Canvas
    -- Must use 'rgba32f' (floats) or 'rgba16f' to count > 255 without clamping.
    -- If your GPU does not support floats, this method will saturate at 255.
    histCanvas = love.graphics.newCanvas(256, 1, {format = "rgba32f"})
    
    -- 3. Create Shader
--    shader = love.graphics.newShader("histogram_v11.glsl")

    -- 4. Generate a Mesh of Points (One per pixel)
    -- This acts as our "Work Group". 
    local vertices = {}
    
    -- We map every pixel center to a UV coordinate (0 to 1)
    for y = 0, h - 1, 1 do
        for x = 0, w - 1, 1 do
            -- Store UVs in the position slots (x, y) of the vertex
            local u = (x + 0.5) / w
            local v = (y + 0.5) / h
            table.insert(vertices, {u, v}) -- defaults: {u, v, 0, 0, 1, 1, 1, 1}) 
        end
    end

    -- Create a mesh configured to draw points
    pointMesh = love.graphics.newMesh(vertices, "points", "static")
    
    -- 5. Prepare data table
    histogramData = {}
    for i = 1, 256 do histogramData[i] = 0 end
    
    -- Calculate immediately
    local t = love.timer.getTime()
    computeHistogram()
    t = love.timer.getTime() - t
    print("Time", t)
end

function computeHistogram()
    -- 1. Setup Canvas
    love.graphics.setCanvas(histCanvas)
    love.graphics.clear(0, 0, 0, 0)
    
    -- 2. Setup State
    love.graphics.setShader(shader)
    love.graphics.setBlendMode("add", "premultiplied")
    
    -- 3. Draw the "Pixel Cloud"
    -- The shader will read the image texture and scatter these points into bins
    shader:send("tex", img) -- Send image to shader
    love.graphics.draw(pointMesh, 0, 0)
    
    -- 4. Reset State
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.setBlendMode("alpha")

    -- 5. Readback Data
    if histCanvas.newImageData then
        -- Love 11.x way
        local data = histCanvas:newImageData()
        local maxVal = 1
        
        for x = 0, 255 do
            -- Read Red channel (where we accumulated counts)
            local r = data:getPixel(x, 0)
            
            -- In a float canvas, 'r' is the actual count (e.g., 500.0)
            histogramData[x+1] = r
            if r > maxVal then maxVal = r end
        end
    end
end

--function love.draw()
--    love.graphics.draw(img, 0, 0)
    
--    -- Visualization
--    local graphX, graphY = 10, 10
--    local graphH = 150
    
--    love.graphics.setColor(1, 0, 0, 1)
--    for i = 1, 256 do
--        local val = histogramData[i]
--        local h = (val / maxVal) * graphH
--        love.graphics.rectangle("fill", graphX + (i-1)*2, graphY + graphH - h, 2, h)
--    end
--    love.graphics.setColor(1, 1, 1, 1)
--    love.graphics.rectangle("line", graphX, graphY, 256*2, graphH)
--    love.graphics.print("Max: "..math.floor(maxVal), graphX, graphY + graphH + 5)
--end