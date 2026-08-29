--
-- bilateral.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.05",
    AUTHOR = "AK Booer / Yang",
    DESCRIPTION = "PLUGIN – O(1) bilateral filter [Quingxiong Yang 2009]",
  }

local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.06.24  Version 0
-- 2026.07.05  considerable re-engineering to simplify buffer handling

local docs = ([[
Qingxiong Yang, Kar-Han Tan, and Narendra Ahuja, 
"Real-Time O(1) Bilateral Filtering," 
in IEEE Conference on Computer Vision and Pattern Recognition (CVPR), 2009, 
pp. 557-564.
]]): gsub ('\n', ' ') : gsub("%s+", ' ')

-------------------------------------------------------------------------------
-- INLINE GLSL v3 SHADER DEFINITIONS
-------------------------------------------------------------------------------

-- This shader handles the mathematical generation of the 
-- Principal Bilateral Filtered Intensity Component (PBFIC) layers

local slice_shader = lg.newShader [[
#pragma language glsl3
uniform float k;       
uniform float Nhat;    
uniform float sigmaR;  // Now perfectly matches your 0.1 to 0.5 normalized units!

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // Input is your stretched r16 monochrome frame [0.0, 1.0]
    float Iy = Texel(tex, texture_coords).r;
    
    // Convert directly to Yang's Ix matrix scale [1.0, Nhat] for indexing
    float Ix = Iy * (Nhat - 1.0) + 1.0;
    
    // --- EQUATION 4 (Adjusted to your 0..1 intensity units) ---
    // Convert the current layer index 'k' back into normalized intensity [0.0, 1.0]
    float k_normalized = (k - 1.0) / (Nhat - 1.0);
    
    // Calculate the range weight using the true normalized distance!
    float Wk = exp(-pow(Iy - k_normalized, 2.0) / (2.0 * pow(sigmaR, 2.0)));
    
    // --- EQUATION 5 ---
    float Jk = Wk * Iy;
    
    return vec4(Jk, Wk, 0.0, 1.0);
}

]]

-- This shader performs the cross-channel division and executes the linear hat interpolation step. 

local accum_shader = lg.newShader [[
#pragma language glsl3
uniform Image raw_image, accum_tex;   
uniform float k;           
uniform float Nhat;        

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    float Iy = Texel(raw_image, texture_coords).r;
    
    // --- EQUATION 8 (Part 1: Adjusted to your 0..1 intensity units) ---
    // We scale our hat function to match the spacing of our normalized levels.
    // The distance between layers in the 0..1 domain is exactly: 1.0 / (Nhat - 1.0)
    float step_size = 1.0 / (Nhat - 1.0);
    float k_normalized = (k - 1.0) * step_size;
    
    // The hat function now spans exactly across the normalized gaps
    float interp_weight = max(0.0, 1.0 - (abs(Iy - k_normalized) / step_size));
    
    // Fetch the Kovesi-blurred values from the active pipeline texture
    vec2 blurred_data = Texel(tex, texture_coords).rg;
    float Jk_blurred = blurred_data.r; 
    float Wk_blurred = blurred_data.g; 
    
    // --- EQUATION 6 ---
    float eps = 1e-5;
    float Jk_final = Jk_blurred / (Wk_blurred + eps);
    
    // --- EQUATION 8 (Part 2) ---
    float IBx_step = interp_weight * Jk_final;
    
    // Fetch the previously accumulated running total
    float old_accum = Texel(accum_tex, texture_coords).r;
    
    return vec4(vec3(old_accum + IBx_step), 1.0);
}

]]


-------------------------------------------------------------------------------
-- ENGINE INITIALISATION
-------------------------------------------------------------------------------

    
--    -- Allocate High-Precision 16-Bit Fixed Point VRAM Canvases
--    canvas_raw_starfield = love.graphics.newCanvas(w, h, {format = "r16"})
--    canvas_accum         = love.graphics.newCanvas(w, h, {format = "r16"})
    
--    canvas_slice         = love.graphics.newCanvas(w, h, {format = "rg16"})
--    canvas_blurred       = love.graphics.newCanvas(w, h, {format = "rg16"})
    

-------------------------------------------------------------------------------
-- PIPELINE EXECUTION ENGINE
-------------------------------------------------------------------------------

local left = {align = "left"}

local plugin = {
    documentation = docs,
    sigma_s  = {id = "sigma_s", value = 0, max = 10, default = 0},                          -- space dimension
    sigma_c  = {id = "sigma_c", value = 0.15, min = 0.1, max = 0.5, default = 0.15},      -- colour dimension (sigmaR)
  }

function plugin:run(workflow)
  if self.sigma_s.value < 0.02 then return end
   -- Clamp the user input to a safe minimum to prevent background posterisation
  local current_sigmaR = math.max(0.08, self.sigma_c.value) -- user feeds 0.1 to 0.5
  
  -- Automatically scale the loop density based on spatial sigma
  local Nhat = 12
  if current_sigmaR >= 0.35 then
      Nhat = 6   -- Wide blur: needs only 6 passes
  elseif current_sigmaR >= 0.22 then
      Nhat = 8   -- Standard blur: needs 8 passes
  elseif current_sigmaR >= 0.14 then
      Nhat = 10  -- Fine blur: needs 10 passes
  end
  -- If current_sigmaR is very narrow, it falls back to 12 levels 
  -- to guarantee high-fidelity edge protection.
  
-- Reset output accumulator buffer to absolute zero
  workflow: save "temp"             -- temp is 'canvas_raw_starfield'
  workflow: save "temp1"            -- temp1 is 'canvas_accum'
  workflow: clear "temp1"

-- Run Core Yang Lua Iteration Loop
  for k = 1, Nhat do
    -- PASS 1: Build unblurred slice parameters

    workflow: newInput "temp"                   -- 'canvas_raw_starfield'
    workflow: shadeWith(slice_shader, {
                k = k,
                Nhat = Nhat,
                sigmaR = self.sigma_c.value})

    -- PASS 2: Execute spatial averaging convolution 
    
    workflow: gaussian(self.sigma_s.value)      -- apply KovesiBlur(canvas_slice, canvas_blurred)

    -- PASS 3: Normalise & aggregate into the r16 canvas registry
     
    workflow: shadeWith (accum_shader , {
                raw_image = workflow["temp"],   -- 'canvas_raw_starfield'
                accum_tex = workflow["temp1"],  -- 'canvas_accum'
                k = k,
                Nhat = Nhat})
    
    workflow: swap("output", "temp1")           -- put output back into temp1
  
  end

  workflow: swap("temp1", "output")             -- put final accumulation back into workflow
end

-----
  
function plugin:draw(suit)
  local sl = suit.layout
  sl:padding(20, 5)
  left.color = suit.theme.color.bluetext
  self.centre = self.centre or {color = suit.theme.color.inactive }
  local W = 160
  
  suit: Slideable(self.sigma_s, sl:row(W, 10))
  suit: Slideable(self.sigma_c, sl:row())
end


return plugin

-----


