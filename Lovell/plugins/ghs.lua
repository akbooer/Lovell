--
-- ghs.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.06",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – Generalised Hyperbolic Stretch",
}

local _log = require "logger" (_M)


local love = _G.love
local lg = love.graphics

-- 2026.10.01  version 0
-- 2026.10.02  parameter tweaks
-- 2026.10.03  PixInsight-style parameters
-- 2026.10.06  further parameter (and implementation) tuning


local ghs = lg.newShader [[
#pragma language glsl3

uniform float u_BP;
uniform float u_inv_scale;
uniform float u_SP_norm;
uniform float u_p_norm;
uniform float u_S0;
uniform float u_inv_S_range;

// Vectorized inverse hyperbolic sine
vec3 ghs_asinh(vec3 z) {
    return log(z + sqrt(z * z + vec3(1.0)));
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 tex_color = Texel(tex, texture_coords);
    
    // 1. Pre-normalize input color into [0.0, 1.0] relative to BP
    vec3 x_norm = clamp((tex_color.rgb - vec3(u_BP)) * u_inv_scale, 0.0, 1.0);
    
    // 2. Form argument z = p_norm * (x_norm - SP_norm)
    vec3 z = u_p_norm * (x_norm - vec3(u_SP_norm));
    
    // 3. Compute stretched output anchored at [0.0, 1.0]
    vec3 Sx = ghs_asinh(z);
    vec3 stretched_rgb = (Sx - vec3(u_S0)) * u_inv_S_range;

    return vec4(stretched_rgb, tex_color.a) * color;
}
]]

-------------------------------

local plugin = {
    id = "GHS",
    lum = {checked = true, text = "luminance mode"},
    D  = {id = "D stretch factor", value = 0, default = 0, max = 20, format = "%0.3f"},
    b  = {id = "b local intensity", value = 10, default = 0, max = 15, format = "%0.3f"},
    SP  = {id = "SP symmetry pt", value = 0, default = 0, format = "%0.3f"},
    HP  = {id = "HP highlight", value = 1, default = 1, format = "%0.3f"},
    LP  = {id = "LP lowlight", value = 0, default = 0, format = "%0.3f"},
    BP  = {id = "BP black point", value = 0, default = 0, format = "%0.3f"},
    
    finetune = {'D', 'b', 'SP', 'BP', selected = 3, default = 3, id = '', size = {50,18}, indent = 0},
    tweak = {id = "tweak", value = 0.5, default = 0.5},
    highly_sensitive = {checked = false, text = "highest sensitivity"},
    split_menu = {checked = false, text = "split menu"},

  }

-- Helper function for asinh in Lua
local function asinh(x)
    return math.log(x + math.sqrt(x * x + 1.0))
end


local function calculateGHSUniforms(D, b, BP, SP)
    local safe_BP = math.min(math.max(BP, 0.0), 0.999999)
    local safe_scale = 1.0 - safe_BP
    local inv_scale = 1.0 / safe_scale

    local SP_norm = math.min(math.max((SP - safe_BP) * inv_scale, 0.0), 1.0)
    local b_factor = 10.0 ^ (math.abs(b) / 5.0)

    -- Option A: Linear D (Use math.max to handle D = 0 smoothly)
    local p_raw = D^1.5 * b_factor * safe_scale
    
    -- Option B: Exponential D (Uncomment if you want exponential slider response)
--     local D_eff = math.exp(D) - 1.0
--     local p_raw = D_eff * b_factor * safe_scale

    -- Clamp p_norm to 1e-5 so D = 0 cleanly renders the linear image x_norm
    local p_norm = math.max(p_raw, 1e-5)

    local function asinh(z)
        return math.log(z + math.sqrt(z * z + 1.0))
    end

    local z0 = -p_norm * SP_norm
    local z1 =  p_norm * (1.0 - SP_norm)

    local S0 = asinh(z0)
    local S1 = asinh(z1)

    local inv_S_range = 1.0 / (S1 - S0)

    return {
        u_BP          = safe_BP,
        u_inv_scale   = inv_scale,
        u_SP_norm     = SP_norm,
        u_p_norm      = p_norm,
        u_S0          = S0,
        u_inv_S_range = inv_S_range
    }
end

-------------------------------
--
-- RUN and DRAW
--

function plugin: run(workflow)
  local function v(n) return self[n] .value end
  local D_pi, SP_pi, b_pi, BP_pi = v 'D', v 'SP', v 'b', v 'BP'
  workflow: shadeWith(ghs, calculateGHSUniforms(D_pi, b_pi, BP_pi, SP_pi))
end


local lalign = {align = "left"}
local ralign = {align = "right"}


local function extras(self, suit, width)
  local sl = suit.layout

  local W = width or 180
  
  suit: Slideable(self.D, sl:row(W, 10))
  suit: Slideable(self.b, sl:row())
  suit: Slideable(self.SP, sl:row())
  sl:row(W, 5)
end

function plugin: draw(suit)
  local sl = suit.layout

  local W = 180
  local Ws = W - 20
  
  if self.split_menu.checked then
    self.extras = extras      -- put in separate menu, or...
  else
    self.extras = nil         -- ...include them in this menu
    extras(self, suit, Ws)    -- ...and in a slightly narrower dormat to match
  end
  
  suit: Slideable(self.HP, sl:row(Ws, 10))
  suit: Slideable(self.LP, sl:row())
  suit: Slideable(self.BP, sl:row())  
  sl:row(Ws, 5)
  
  local x,y, w,h = sl:row(100, 20)
  suit: Choosable(self.finetune, x+50, y, 60, 20)
  suit: Label("adjust: ", lalign, x,y, w,h)
  local tweak = suit: Slider(self.tweak, sl:row(Ws, 10)) 
  suit: Checkbox(self.highly_sensitive, sl:row(Ws, 16))
  suit: Checkbox(self.split_menu, sl:row(Ws, 16))
  
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


