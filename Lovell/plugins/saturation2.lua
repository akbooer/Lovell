--
-- saturation.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.01",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – alternative saturation",
}

local _log = require "logger" (_M)


local love = _G.love
local lg = love.graphics

-- 2026.10.01  version 0


local saturate = lg.newShader [[
#pragma language glsl3

uniform float u_saturation;         // Saturation multiplier in midtones (e.g., 1.5)
uniform float u_bg_center = 0.09;   // Sky pedestal floor (e.g., 0.09)

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

// Continuous rational shoulder function for smooth asymptotic highlight compression
vec3 soft_shoulder(vec3 c, float threshold) {
    vec3 result;
    for (int i = 0; i < 3; i++) {
        if (c[i] <= threshold) {
            result[i] = c[i];
        } else {
            float num = (1.0 - threshold) * (1.0 - threshold);
            float den = c[i] - 2.0 * threshold + 1.0;
            result[i] = 1.0 - (num / den);
        }
    }
    return result;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
    vec4 texel = Texel(tex, tc) * color;
    
    // 1. Rec. 709 Linear Luminance
    float luma = dot(texel.rgb, LUMA_WEIGHTS);
    
    // 2. Windowed Saturation Factor s(Y):
    // Ramps UP above sky pedestal (0.09), ramps DOWN in extreme highlights (>0.70)
    float sky_ramp       = smoothstep(u_bg_center - 0.02, u_bg_center + 0.05, luma);
    float highlight_ramp = smoothstep(0.65, 0.95, luma);
    
    // s = 0.0 at sky floor, u_saturation in midtones, 0.0 in bright highlights
    float s = mix(0.0, u_saturation, sky_ramp * (1.0 - highlight_ramp));
    
    // 3. Linear vector interpolation
    vec3 rgb_out = mix(vec3(luma), texel.rgb, s);
    
    // 4. Asymptotic soft compression above 0.85 instead of hard clamp
    rgb_out = soft_shoulder(max(rgb_out, vec3(0.0)), 0.85);
    
    return vec4(rgb_out, texel.a);
}
]]


-------------------------------


local saturation  = {id = "saturation ", value = 1, default = 1, max = 2}

-------------------------------
--
-- RUN and DRAW
--

local function run(self, workflow)
  
  local sat = saturation.value
  if sat > 0 then
    workflow: shadeWith(saturate, {u_saturation = saturation.value ^ 1.5})      -- apply saturation stretch
  end
end


local function draw(self, suit)
  local sl = suit.layout

  local W = 180
  local Ws = W - 20

  suit: Slideable(saturation, sl:row(Ws, 10))

end


return {
  id = "Saturation", 
  
  documentation = [[
Experimental saturation function which desaturations low and high intensities.
]],

  -- controls (exported so that they can be reset)
  saturation = saturation,

  -- methods
  draw = draw,
  run = run,
}

-----


