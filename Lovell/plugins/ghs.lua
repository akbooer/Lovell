--
-- ghs.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.10.08",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – Generalised Hyperbolic Stretch",
}

local _log = require "logger" (_M)


local love = _G.love
local lg = love.graphics

-- 2026.10.01  version 0
-- 2026.10.02  parameter tweaks
-- 2026.10.03  PixInsight-style parameters
-- 2026.10.08  further parameter (and implementation) tuning

--[[
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
--]]


local ghs = lg.newShader [[
#pragma language glsl3

uniform float u_BP;
uniform float u_SP;
uniform float u_p;

const float eps = 1.0e-5;

// bounds check input to ensure valid calculations
float BP = min(1.0 - eps, u_BP);
float scale = 1.0 - BP;
float inv_scale = 1.0 / scale;

float SP = min(max((u_SP - BP) * inv_scale, 0.0), 1.0);
float p = max(u_p, eps);

float S0 = asinh(-p * SP);
float S1 = asinh(p * (1.0 - SP));
float inv_S_range = 1.0 / (S1 - S0);


vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 tex_color = Texel(tex, texture_coords);
    
    // 1. Pre-normalize input color into [0.0, 1.0] relative to BP
    vec3 x_norm = clamp((tex_color.rgb - vec3(BP)) * inv_scale, 0.0, 1.0);
    
    // 2. Form argument z = p * (x_norm - SP)
    vec3 z = p * (x_norm - vec3(SP));
    
    // 3. Compute stretched output anchored at [0.0, 1.0]
    vec3 Sx = asinh(z);
    vec3 stretched_rgb = (Sx - vec3(S0)) * inv_S_range;

    return vec4(stretched_rgb, tex_color.a) * color;
}
]]

--[[

// 5. Highlight Gamut Protection
    float maxChannel = max(stretched_rgb.r, max(stretched_rgb.g, stretched_rgb.b));
    if (maxChannel > 1.0) {
        stretched_rgb / maxChannel;
    }
]]

-------------------------------

local GREY_SKY = 0.09   -- default SP

local plugin = {
    id = "GHS",
    lum = {checked = true, text = "luminance mode"},
    D  = {id = "D stretch", value = 0, default = 0, max = 20, format = "%0.3f"},
    b  = {id = "b local intensity", value = 10, default = 0, max = 15, format = "%0.3f"},
    SP  = {id = "SP symmetry pt", value = GREY_SKY, default = GREY_SKY, format = "%0.3f"},
    HP  = {id = "HP highlight", value = 1, default = 1, format = "%0.3f"},
    LP  = {id = "LP lowlight", value = 0, default = 0, format = "%0.3f"},
    BP  = {id = "BP black point", value = 0, default = 0, format = "%0.3f"},
    
    finetune = {'D', 'b', 'SP', 'BP', selected = 3, default = 3, id = '', size = {50,18}, indent = 0},
    tweak = {id = "tweak", value = 0.5, default = 0.5},
    highly_sensitive = {checked = false, text = "highest sensitivity"},

  }


local function calculateGHSUniforms(D, b, BP, SP)
    local safe_BP = math.min(math.max(BP, 0.0), 0.999999)
    local safe_scale = 1.0 - safe_BP
    
    local b_factor = 10.0 ^ (math.abs(b) / 5.0)

    -- Option A: Linear D (Use math.max to handle D = 0 smoothly)
    local p = D ^ 1.5 * b_factor * safe_scale
    
    -- Option B: Exponential D (Uncomment if you want exponential slider response)
--     local D_eff = math.exp(D) - 1.0
--     local p = D_eff * b_factor * safe_scale

    return {u_BP = BP, u_SP = SP, u_p  = p}
end

-------------------------------
--
-- RUN and DRAW
--

function plugin: run(workflow)
    
  if self.D.value == 0 then return end    -- linear stretch
  
  local function v(n) return self[n] .value end
  local D_pi, SP_pi, b_pi, BP_pi = v 'D', v 'SP', v 'b', v 'BP'
  
  workflow: shadeWith(ghs, calculateGHSUniforms(D_pi, b_pi, BP_pi, SP_pi))
end


local lalign = {align = "left"}
local ralign = {align = "right"}


function plugin: extras(suit, width)
  local sl = suit.layout

  local W = width or 180
  
  suit: Slideable(self.D, sl:row(W, 10))
  suit: Slideable(self.b, sl:row())
  suit: Slideable(self.SP, sl:row())

end

local hrule = ('–'): rep(25)    -- for menu dividers
local hrule_opt
local blank = {format = ''}   -- remove value display from tweak slider

function plugin: draw(suit)
  local sl = suit.layout
  hrule_opt = hrule_opt or {color = suit.theme.color.inactive}

  local W = 160
  
  local SP = self.SP.value
  self.HP.value = math.max(self.HP.value, SP)
  self.LP.value = math.min(self.LP.value, SP)
  
--  suit: Slideable(self.HP, sl:row(W, 10))
--  suit: Slideable(self.LP, sl:row())
  suit: Slideable(self.BP, sl:row(W, 10))  
--  sl: row(W, 0)

--  self: extras(suit, W)
  
  sl: row(nil, 2)
  local x,y, w,h = sl:row(100, 20)
  suit: Choosable(self.finetune, x+50, y, 60, 20)
  suit: Label("adjust: ", lalign, x,y, w,h)
  local tweak = suit: Slideable(self.tweak, blank, sl:row(W, 10)) 
  suit: Checkbox(self.highly_sensitive, sl:row(W, 16))
--  suit: Slideable(self.BP, sl:row(W, 10)) 

  self: extras(suit, W)
  
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

 
D, b, and SP are visible at the top level if drop-down menu is split.

]]


return plugin

-----


