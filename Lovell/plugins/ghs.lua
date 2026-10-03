--
-- ghs.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.03",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – Generalised Hyperbolic Stretch",
}

local _log = require "logger" (_M)


local love = _G.love
local lg = love.graphics

-- 2026.10.01  version 0
-- 2026.10.02  parameter tweaks
-- 2026.10.03  PixInsight-style parameters


local ghs = lg.newShader [[
#pragma language glsl3

uniform float u_x0;
uniform float u_D;
uniform float u_b;
uniform float u_bp = 0.0;   // symmetric curve
uniform float u_S0;
uniform float u_invDenom;

// Standard CIE Rec.709 luminance weights
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

float ghsStretch(float x) {
    if (x <= u_x0) return 0.0;
    float x_norm = (x - u_x0) / (1.0 - u_x0);
    
    if (u_D < 0.001 || u_invDenom == 0.0) return x_norm;

    float S_x = asinh(u_D * (x_norm - u_b) + u_bp);
    return clamp((S_x - u_S0) * u_invDenom, 0.0, 1.0);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 texColor = Texel(tex, texture_coords);
    
    // 1. Calculate linear luminance
    float L = dot(texColor.rgb, LUMA_WEIGHTS);

    // 2. Compute stretched luminance (only 1 GHS call total)
    float L_stretched = ghsStretch(L);

    // 3. Scale RGB by the luminance stretch ratio
    vec3 stretchedRGB = vec3(0.0);
    if (L > 1e-6) {
        float ratio = L_stretched / L;
        stretchedRGB = texColor.rgb * ratio;
    }

    // Optional Gamut Protection for Bright Stars
    float maxChannel = max(stretchedRGB.r, max(stretchedRGB.g, stretchedRGB.b));
    if (maxChannel > 1.0) {
        // Softly compress out-of-bounds RGB back into [0, 1] while preserving hue
        stretchedRGB /= maxChannel; 
    }
    
    return vec4(stretchedRGB, 1.0);
}
]]

-------------------------------

local plugin = {
    id = "GHS",
    lum = {checked = true, text = "luminance mode"},
    D  = {id = "D stretch factor", value = 0, default = 0, max = 20, format = "%0.3f"},
    b  = {id = "b local intensity", value = 10, default = 10, max = 15, format = "%0.3f"},
    SP  = {id = "SP symmetry pt", value = 0, default = 0, format = "%0.3f"},
    HP  = {id = "HP highlight", value = 1, default = 1, format = "%0.3f"},
    LP  = {id = "LP lowlight", value = 0, default = 0, format = "%0.3f"},
    BP  = {id = "BP black point", value = 0, default = 0, format = "%0.3f"},
    
    finetune = {'D', 'b', 'SP', 'BP', selected = 3, default = 3, id = '', size = {50,18}, indent = 0},
    tweak = {id = "tweak", value = 0.5, default = 0.5},
    highly_sensitive = {checked = false, text = "highest sensitivity"},

  }

-- Helper function for asinh in Lua
local function asinh(x)
    return math.log(x + math.sqrt(x * x + 1.0))
end

-------------------------------
--
-- RUN and DRAW
--

function plugin: run(workflow)
  local function v(n) return self[n] .value end
  
  local D_pi, SP_pi, b_pi, BP_pi = v 'D', v 'SP', v 'b', v 'BP'
   
  -- Unwrap PI's logarithmic stretch factor UI control
  local D_raw = math.exp(D_pi) - 1.0
 
  local safeBP = math.min(BP_pi, 0.9999)
  
  -- Remap PixInsight parameters to simplified GHS domain  
  local x0 = safeBP
  local b  = math.max(0.0, math.min(1.0, (SP_pi - safeBP) / (1.0 - safeBP)))
  local D  = D_raw * b_pi * (1.0 - safeBP)
  local bp = 0.0 -- Symmetric curve

  -- Pre-calculate invariant curve endpoints
  local S_0 = asinh(bp - D * b)
  local S_1 = asinh(D * (1.0 - b) + bp)
  local denom = S_1 - S_0
  local invDenom = (math.abs(denom) < 1e-6) and 0.0 or (1.0 / denom)

  workflow: shadeWith(ghs, {
      u_x0 = x0,
      u_D = D,
      u_b = b,
      u_S0 = S_0,
      u_invDenom = invDenom,
    })

    
end

local hrule = ('–'): rep(20)                         -- for menu dividers
local lalign = {align = "left"}
local ralign = {align = "right"}

function plugin: draw(suit)
  local sl = suit.layout

  local W = 180
  local Ws = W - 20
  
  
  suit: Slideable(self.D, sl:row(Ws, 10))
  suit: Slideable(self.b, sl:row())
  suit: Slideable(self.SP, sl:row())
  suit: Slideable(self.HP, sl:row())
  suit: Slideable(self.LP, sl:row())
  suit: Slideable(self.BP, sl:row())
  
  
--  suit: Label(hrule, {color = suit.theme.color.inactive}, sl: row(Ws, 10))
  local x,y, w,h = sl:row(100, 20)
  suit: Choosable(self.finetune, x+50, y, 60, 20)
  suit: Label("adjust: ", lalign, x,y, w,h)
  local tweak = suit: Slider(self.tweak, sl:row(Ws, 10)) 
  suit: Checkbox(self.highly_sensitive, sl:row(Ws, 16))
  
  local item = self[self.finetune[self.finetune.selected]]
  if tweak.changed then
    local delta = self.tweak.value - self.tweak.previous
    local min, max = item.min or 0, item.max or 1
    local scale = self.highly_sensitive.checked and 0.01 or 0.1
    item.value = math.max(min, math.min(max, item.value + delta * scale))
  end
  
  if tweak.hovered then
    suit: Label("%0.3f" % item.value, ralign, x+100, y, 60, 20)
  end
  
  self.tweak.previous = self.tweak.value

end


plugin.documentation = [[
Generalised Hyperbolic Stretch - PixInsight Style

D (Stretch Factor): Controls the magnitude of the localized contrast boost around SP (D≥0).

b (Local Intensity): Controls how rapidly the gain drops off moving away from SP (b>0).

SP (Symmetry point): The pixel intensity value where contrast amplification is centered and maximal (0≤SP≤1).

HP (Protect highlights): Controls the tapering of contrast near bright regions to prevent clipping stars (HP≥0).

LP (Protect shadows): Tapers contrast near deep shadows to avoid amplifying background noise (LP≥0).

BP (Black point): Standard linear offset applied to reset the black background floor (BP in [0,1]).

]]


return plugin

-----


