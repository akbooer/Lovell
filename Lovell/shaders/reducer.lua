--
-- reducer 
--

local _M = {
  NAME = ...,
  VERSION = "2026.07.19",
  AUTHOR = "AK Booer",
  DESCRIPTION = "Reducer - two-pass strider reduction of 2D canvas to 1D",
}


-- 2026.07.19  Version 0
-- 2026.07.20  add readout()


require "logger" (_M)


local ffi = require "ffi"

local love = _G.love
local lg = love.graphics

--[[

A single-pass full-height loop forces a single fragment shader thread to perform ~1,000s sequential texture 
lookups and conditional checks. While a high-end desktop GPU can brute-force this via raw clock speed, 
it creates severe execution divergence and serialization on mobile or integrated GPUs. 
It throws away the core strength of the GPU: hierarchical, massive parallelism.

To make this hyper-efficient, usa a 2-Pass Strided Column-Parallel Reduction. 
This breaks the vertical loop down from 1,080 linear steps to a two-tier parallel tree, 
bringing total per-thread loop iterations down to just a handful.

The 2-Pass Architecture:

Instead of collapsing all 1,000s pixels straight to 1, we collapse through an intermediate canvas step:

 * Pass 1:  Target an intermediate canvas of Width x S (where S is a small stride dimension like 16 or 32). 
            Each vertical thread only loops through a tiny fraction of the height (~34 or 68 steps).
 * Pass 2:  Target the final Width x 1 canvas. This pass only loops S times (16 or 32 steps) over the 
            intermediate canvas to extract the final peak.

Why This Trashes the Linear Scan Performance:

| Vector Metrics                 | Linear Full-Height Scan        | 2-Pass Strided Parallel |
| Active Threads per Column      | 1 thread                       | 16/32 threads working simultaneously |
| Max Loop Iterations per Thread | 1,080 iterations               | 68 iterations (Pass 1) + 16 (Pass 2) |
| Texture Cache Performance      | Horrible (exceeds local cache) | Excellent (highly localized memory) |

Breaking the operation into two stages, distributes the loop stress horizontally across the execution cores. 
This yields much more stable frame times, especially on hardware architectures sharing memory systems.

--]]


local REDUCTION_TEMPLATE = [[
  #pragma language glsl3

    /*
    %s
    */
    
    uniform float uSrcHeight;
    uniform float uDstHeight;
    uniform int uVStride;
    // CUSTOM_UNIFORMS
    %s

    vec4 effect(vec4 color, Image MainTexture, vec2 texture_coords, vec2 screen_coords) {
        
        // INITIAL_SETUP
        %s
        
        // Loop Bounds
        float sliceSize = uSrcHeight / uDstHeight;
        int start = int(floor(screen_coords.y) * sliceSize);
        int end   = int((floor(screen_coords.y) + 1.0) * sliceSize);
        int step = max(1, uVStride);
        vec2 origin_uv = texture_coords;  // just in case loop body needs the original values

        for (int i = start; i < end; i += step) {
            texture_coords = vec2(origin_uv.x, (float(i) + 0.5) / uSrcHeight);
            
        // LOOP_BODY
            %s
        }

        // RETURN_STATEMENT
        return %s ;
    }
    
]]


local function numberLines(text)
  local n = 0
  local t = {}
  for line in text: gmatch ".-\n" do
    n = n + 1
    t[#t+1] = string.format ("%3d   %s", n, line)
  end
  return table.concat(t)
end


function _M.create(config)

  local code = REDUCTION_TEMPLATE % {
    config.comment or '',
    config.uniforms or '',
    config.init or '',
    config.code or '',
    config.ret or "return vec4(0.0);",
  }

  -- Compile the shader
  local success, shaderOrError = pcall(lg.newShader, code)
  if not success then
    local errfmt = "Shader Compilation Error:\n%s \nShader code: \n%s"
    error(errfmt % {shaderOrError, numberLines(code)}, 2)
  end

  return shaderOrError
end

--[=[

  Example use: AVERAGE / SUM
  
  local sumShader = createReductionShader {
    init = "accumulator = vec4(0.0);", 
    code = [[
        accumulator += currentTexel; // Keep adding values to compute an average later
    ]],
    ret = "accumulator"}

--]=]


------------------------
--
-- FFI Readback
--

function _M.readout(imgData)
  local rawPtr = imgData:getFFIPointer() or imgData:getPointer()
  local floatPtr = ffi.cast("float*", rawPtr)
  local w = imgData: getWidth()
  
  local r, g, b, a =  table.new(w, 0), table.new(w, 0),
                      table.new(w, 0), table.new(w, 0)
                      
  for i = 0, w - 1 do
    local j = i + 1
    local offset = i * 4
    r[j] = floatPtr[offset + 0]
    g[j] = floatPtr[offset + 1]
    b[j] = floatPtr[offset + 2]
    a[j] = floatPtr[offset + 3]
  end
  
  imgData:release()

  return r, g, b, a
end


------------------------
--
-- NEW
--
--[=[

    local reduce = reducer.new {Xborder = 0, Yborder = 0, chunks = 32, stride = 1}    -- these are the defaults
    
    local result1D = reduce(image, {
              pass1 = {uniforms = {...}, init = [[ ]], code = [[ ]]}, 
              pass2 = {uniforms = {...}, init = [[ ]], code = [[ ]]}, 
            })
    
    Uniforms are structured: 
       {["float x"] = 3.14, ["int foo"] = 42, ["Image img"] = canvas}
       
    Example stats:
    
    
--]=]

-- uniforms() converts {["int foo"] = 42, ...} 
-- into: 
--   "uniform int foo; ..." for the shader definition  
--   returning {foo = 42, ...} for the send("foo", 42) calls
--

local function uniforms(uni)
  local uniforms, sends = {}, {}
  if uni then
    for name, value in pairs(uni) do
      local utype, uname = name: match "(%w+)%s+([%w_]+)"
      if not utype then 
        error("syntax error in uniform: " .. name, 3)
      end
      uniforms[#uniforms+1] = table.concat{"uniform ", name, ';'}
      sends[uname] = value
    end
  end
  return sends, table.concat(uniforms, '\n')
end


-- create a shader with uniform declarations
local function createShader(pass)
  local _, uniforms = uniforms(pass.uniforms)
  return _M.create {
        comment = pass.comment,
        uniforms = uniforms,
        init = pass.init,
        code = pass.code,
        ret = pass.ret}
end

-- send the specified uniforms
local function send(shader, uniforms)
  for name, value in pairs(uniforms) do
    shader: send(name, value)
  end
end


function _M.new(opts)
  opts = opts or {}
  
  local canvasIntermediate, canvas1D
  
  local Pass1Shader, Pass2Shader
  
  local BORDER_X = opts.Xborder or 0
  local BORDER_Y = opts.Yborder or 0
  local V_STRIDE = opts.stride or 1
  local CHUNKS   = opts.chunks or 64
  
   
  local function updateCanvases(activeW)
    -- Check against activeW instead of the full image width
    if not canvasIntermediate or canvasIntermediate:getWidth() ~= activeW then
      canvasIntermediate = lg.newCanvas(activeW, CHUNKS, { dpiscale = 1, format = "rgba32f" })
      canvasIntermediate:setFilter("nearest", "nearest") 

      canvas1D = lg.newCanvas(activeW, 1, { dpiscale = 1, format = "rgba32f" })
      canvas1D:setFilter("nearest", "nearest") 
    end
  end
  
  
  local function calculate(rawImage, info)
    local imgW, imgH = rawImage:getDimensions()

    -- 1. Calculate active dimensions
    local activeW = imgW - (2 * BORDER_X)
    local activeH = imgH - (2 * BORDER_Y)
    assert(activeW > 0 and activeH > 0, "Borders are larger than the image dimensions!")

    updateCanvases(activeW)
    
    if not Pass1Shader then                 -- only done on first call
      Pass1Shader = createShader(info.pass1)      
      Pass2Shader = createShader(info.pass2)      
    end

    -- PASS 0:  Init

    lg.push("all")
    lg.origin()
    lg.setBlendMode("replace", "premultiplied")

    -- Create the quad defining the active area to be processed
    local activeQuad = lg.newQuad(BORDER_X, BORDER_Y, activeW, activeH, imgW, imgH)

    -- PASS 1: Raw Image (Quad Culling) -> Intermediate Chunks
    lg.setCanvas(canvasIntermediate)
    lg.clear()
    lg.setShader(Pass1Shader)

    Pass1Shader:send("uSrcHeight", activeH)
    Pass1Shader:send("uDstHeight", CHUNKS)
    Pass1Shader:send("uVStride", V_STRIDE)
        
    -- USER UNIFORMS
    send(Pass1Shader, uniforms(info.pass1.uniforms))

    -- Draw ONLY the active Quad.
    -- The Y-scale squashes the activeHeight into the CHUNKS height
    lg.draw(rawImage, activeQuad, 0, 0, 0, 1, CHUNKS / activeH)

    -- PASS 2: Intermediate Chunks -> 1D Data Strip
    lg.setCanvas(canvas1D)
    lg.clear()
    lg.setShader(Pass2Shader)

    Pass2Shader:send("uSrcHeight", CHUNKS)
    Pass2Shader:send("uDstHeight", 1.0)
    
    -- USER UNIFORMS
    send(Pass2Shader, uniforms(info.pass2.uniforms))

    -- Draw the intermediate canvas (which is already activeW wide).
    -- Scale Y to squash CHUNKS into a 1-pixel high strip.
    lg.draw(canvasIntermediate, 0, 0, 0, 1, 1 / CHUNKS)

    lg.setCanvas()
    lg.setShader()
    lg.pop()
    
    return canvas1D:newImageData()
  end

  return calculate
end
      

return _M


-----
