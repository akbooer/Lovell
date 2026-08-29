--
-- hubble.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.06.29",
  AUTHOR = "AK Booer / Bill Blanshan",
  DESCRIPTION = "PLUGIN – Hubble colour palette (Bill Blanshan)",
}

local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

-- 2026.06.29 Version 0


local color, centre
local align = {align = "left"}

-------------------------------
--
-- HUBBLE (pseudo-SHO)
--
-- based on Bill Blanshan's "Narrowband Normalization" PixInsight code
--

local blanshan = lg.newShader [[

  uniform float gold_shift = 0.4;
  uniform float blue_shift = 0.3;
  uniform float blue_green = 0.5;
  uniform float un_green = 0.65;
  uniform float OIII_sub = 0.2;
  
  vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
      // 1. Sample the original unfiltered RGB pixel
      vec3 pixel = Texel(texture, texture_coords).rgb;
      
      float R = pixel.r;
      float G = pixel.g;
      float B = pixel.b;
      
      // 2. Isolate the channels based on Blanshan's logic
      // For unfiltered OSC, Ha is dominant in Red. OIII splits across Green and Blue.
      float Ha  = R;
      float OIII = mix(B, G, blue_green); // Blend green and blue to get a cleaner OIII signal
      
      // Since we don't have true SII, we synthesize a pseudo-SII.
      // A common Blanshan technique subtracts a portion of OIII from Ha to find the "core" red structures.
      float SII = clamp(Ha - (OIII * OIII_sub), 0.0, 1.0); 

      // 3. Map to the Hubble Palette (SHO)
      // Red = SII, Green = Ha, Blue = OIII
      vec3 sho = vec3(SII, Ha, OIII);
      
      // 4. Color Normalization (The Blanshan "Un-greening" shift)
      // Because Ha is mapped to Green, the image will look heavily green. 
      // We shift the green tones toward gold/orange, and amplify the blues.
      
      // Reduce pure green, blending some green into the red channel to create gold
      sho.r += sho.g * gold_shift;
      sho.g *= un_green;        
      sho.b += OIII * blue_shift;  // Boost the deep blues
      
      // Clamp values to stay in valid 0.0 - 1.0 range
      sho = clamp(sho, 0.0, 1.0);

      // Return the final color
      return vec4(sho, 1.0);
  }
]]


local plugin = {
    id = "Chroma",
    static = true,
    gold_boost  = {id = "gold_boost", value = 0.4, default = 0.4},
    blue_boost  = {id = "blue_boost", value = 0.3, default = 0.3, max = 2},

    blue_green  = {id = "blue_green", value = 0.5, default = 0.5},       --  Blue : Green   (B:G)
    un_green    = {id = "un_green", value = 0.85, default = 0.85, max = 2},
    OIII_sub    = {id = "OIII_sub", value = 0.2, default = 0.2},
    
    documentation = [[
HUBBLE (pseudo-SHO) based on Bill Blanshan's "Narrowband Normalization" PixInsight code.

This treats RGB channels as HSO and swizzles them to be SHO ordered.

The controls are specfic to his process and more details can be found online, but feel free to experiment, the names are fairly self-explanatory.
]],

  }


-- on entry, the workflow contains 3-channel multi-spectral data from the stack
function plugin:run(workflow, ...)
  workflow: shadeWith (blanshan, {
              gold_shift =  self.gold_boost.value,
              blue_shift = self.blue_boost.value,
              blue_green = self.blue_green.value,
              un_green = self.un_green.value,
              OIII_sub = self.OIII_sub.value})
end


function plugin:draw(suit)
  local sl = suit.layout
  color = suit.theme.color.bluetext
  centre = centre or {color = suit.theme.color.inactive }

  local W, Hb = 180, 25
  local Ws = W - 20

  suit: Slideable(self.blue_green, sl:row(Ws, 10))
  suit: Slideable(self.un_green, sl:row(Ws, 10))
  suit: Slideable(self.OIII_sub, sl:row(Ws, 10))

end

function plugin:extras(suit)
  local sl = suit.layout
  sl:padding(20, 5)
  local Ws = 180
  suit: Slideable(self.gold_boost, sl:row(Ws, 10))
  suit: Slideable(self.blue_boost, sl:row())
end


return plugin

-----


