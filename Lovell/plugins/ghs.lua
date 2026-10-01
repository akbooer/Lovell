--
-- ghs.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.01",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – Generalised Hyperbolic Stretch",
}

local _log = require "logger" (_M)


local love = _G.love
local lg = love.graphics

-- 2026.10.01  version 0


local ghs = lg.newShader [[

    // GHS Uniforms
    uniform float u_D;   // Stretch factor
    uniform float u_b;   // Symmetry point (SP)
    uniform float u_bp;  // Local intensity focus
    uniform float u_x0 = 0.001;  // Black point offset

    // Core GHS stretching function
    float ghsStretch(float x, float D, float b, float bp, float x0) {
        if (x <= x0) return 0.0;
        float x_norm = (x - x0) / (1.0 - x0);
        
        if (D < 0.001) return x_norm;

        float S_x = log((D * (x_norm - b) + bp) + sqrt(pow(D * (x_norm - b) + bp, 2.0) + 1.0));
        float S_0 = log((bp - D * b) + sqrt(pow(bp - D * b, 2.0) + 1.0));
        float S_1 = log((D * (1.0 - b) + bp) + sqrt(pow(D * (1.0 - b) + bp, 2.0) + 1.0));

        float denom = S_1 - S_0;
        if (abs(denom) < 1e-6) return x_norm;

        return clamp((S_x - S_0) / denom, 0.0, 1.0);
    }

    vec4 effect(vec4 color, Image tex, vec2 tex_coords, vec2 screen_coords) {
        vec4 pixel = Texel(tex, tex_coords);
        
        // 1. Extract luminance to decouple contrast expansion from color ratios
        float lumaIn = dot(pixel.rgb, vec3(0.2126, 0.7152, 0.0722));
        
        // 2. Apply GHS strictly to the luminance channel
        float lumaOut = ghsStretch(lumaIn, u_D, u_b, u_bp, u_x0);
        
        // 3. Rescale RGB channels by the luminance ratio to preserve star/nebula chromaticity
        float safeLumaIn = max(lumaIn, 1e-5);
        vec3 finalRGB = pixel.rgb * (lumaOut / safeLumaIn);
        
        return vec4(finalRGB, 1.0);
    }
]]

-------------------------------

local plugin = {
    id = "GHS",
    stretch  = {id = "ghs stretch", value = 1, default = 1, max = 15},
    symmetry  = {id = "ghs symmetry ", value = 0.1, default = 0.1, max = 0.5},
    focus  = {id = "ghs focus ", value = 0.1, default = 0.1, max = 0.5},
    BP  = {id = "ghs bp ", value = 0.09, default = 0.09, max = 0.3},
    documentation = [[
Generalised Hyperbolic Stretch

Stretch factor: The hyperbolic aggressiveness parameter governing contrast scaling around the symmetry point.

Symmetry point: The coordinate on the input intensity scale where the GHS curve achieves its peak gradient slope.

Local focus: The local transition shape parameter in GHS.

BP: Black point
]],

  }

-------------------------------
--
-- RUN and DRAW
--

function plugin: run(workflow)
  
  local stretch = self.stretch.value
  if stretch ~= 1 then
    workflow: shadeWith(ghs, {
        u_D = stretch,
        u_b = self.symmetry.value,
        u_bp = self.focus.value,
        u_x0 = self.BP.value,
      })
  end
end


function plugin: draw(suit)
  local sl = suit.layout

  local W = 180
  local Ws = W - 20

  suit: Slideable(self.stretch, sl:row(Ws, 10))
  suit: Slideable(self.symmetry, sl:row())
  suit: Slideable(self.focus, sl:row())
  suit: Slideable(self.BP, sl:row())

end


return plugin

-----


