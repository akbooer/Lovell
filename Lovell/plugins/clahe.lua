--
-- clahe.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.26",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Contrast Limited Adaptive Histogram Equalisation",
  }

local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.06.24  Version 0
-- 2026.07.03  use enternal smooth reference


local claheShader = lg.newShader [[
#pragma language glsl3

uniform sampler2D u_smoothReference; // Your pre-blurred canvas
uniform float EffectStrength;
uniform float ClipLimit;            // Lower values clamp noise tightly. Higher values enhance aggressively.

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    // 1. Grab raw canvas data from both targets (No LÖVE tints)
    vec4 centerColor = Texel(tex, texture_coords);
    vec4 smoothColor = Texel(u_smoothReference, texture_coords);
    
    // 2. Calculate the local deviation from the mean (component-wise)
    // Positive means center is brighter than its neighborhood; negative means darker.
    vec4 deviation = centerColor - smoothColor;
    
    // 3. Apply a contrast stretching factor
    // We simulate the local histogram slope by multiplying the deviation.
    // In a flat area, deviation is near 0.0, so enhancement stays low.
    vec4 equalizedColor = smoothColor + (deviation * (1.0 + ClipLimit * 5.0));
    
    // 4. Clip Limit Protection (The Noise Gate)
    // If the enhanced color overshoots too far from the original, we clamp the amplification.
    vec4 clShift = abs(equalizedColor - centerColor);
    vec4 allowedClimb = vec4(ClipLimit) / max(clShift, vec4(0.0001));
    
    // Smoothly blend back to prevent harsh pixel stepping if we hit the clip threshold
    equalizedColor = mix(centerColor, equalizedColor, clamp(allowedClimb, 0.0, 1.0));
    equalizedColor = clamp(equalizedColor, 0.0, 1.0);
    
    // 5. Blend back with original image based on user strength
    vec4 finalColor = mix(centerColor, equalizedColor, EffectStrength);
    
    // 6. Restore original alpha so transparency pipeline doesn't break
    finalColor.a = centerColor.a;
    
    return finalColor;
}

]]


local plugin = {
    id = "CLAHE",
    
    -- multi-scale 2, 8, 32 sigma, with clip default of .1, .2, .5
    {id = "fine", value = 0, max = 1, default = 0, sigma = 4},
    {id = "medium", value = 0, max = 1, default = 0, sigma = 8},
    {id = "coarse", value = 0, max = 1, default = 0, sigma = 32},

    -- ids are unique from above (trailing space)
    {id = "fine ",   value = 0.1, min = 1e-3, max = 0.2, default = 0.1},
    {id = "medium ",  value = 0.2, min = 1e-3, max = 0.4, default = 0.2},
    {id = "coarse ", value = 0.5, min = 1e-3, max = 1.0, default = 0.5},
    
    documentation = [[
Contrast Limited Adaptive Histogram Equalisation.  

This is a multi-scale implementation with individual strength and contrast limits.  

The three scales correspond to structures of around 4, 8, and 32 pixels.]]
    
  }

function plugin:run(workflow)
  local shader = claheShader
  
  for i = 1, 3 do
    local strength = self[i].value
    local sigma = self[i].sigma 
    local limit = self[i + 3].value
    
    if strength > 0 then
      workflow: save "temp"                 -- original input
      workflow: gaussian(sigma)             -- average background
      workflow: swap("output", "temp")      -- output is now original input, temp is average background
            
      workflow: shadeWith (shader, {
                    u_smoothReference = workflow["temp"],
                    EffectStrength = strength,
                    ClipLimit = limit})
    end
  end
end

  
function plugin:draw(suit)
  local sl = suit.layout
  sl: padding(20, 5)
  self.centre = self.centre or {color = suit.theme.color.inactive }
  local W = 180 - 40
  
  suit: Label("multiscale contrast", sl: row(W, 10)) 
  sl: row(W, 0)
  for i = 1, 3 do
    suit: Slideable(self[i], sl:row(W, 10))
  end
    
  sl: row(W, 5)
  suit: Label("contrast limits", sl: row(W, 10)) 
  for i = 1, 3 do
    suit: Slideable(self[i + 3], sl:row())
  end
  
end


return plugin

-----
