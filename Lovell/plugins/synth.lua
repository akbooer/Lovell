--
-- synth_lum.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.08.02",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – Synthetic luminance from RGB",
}

local _log = require "logger" (_M)

-- 2026.08.02  Version 0, extracted from shaders.colour and stacking


local love = _G.love
local lg = love.graphics

-------------------------------
--
-- 


local lrgb = lg.newShader ([[

#pragma language glsl3

  // --- UNIFORMS ---

  // 1. Plane Slopes per channel (X and Y slopes for RGB and Alpha)

  uniform vec4 u_slopes_x;                       // u_slopes_x = vec4(R_x, G_x, B_x, Lum_x)
  uniform vec4 u_slopes_y;                       // u_slopes_y = vec4(R_y, G_y, B_y, Lum_y)
  uniform vec4 u_plane_offset;                   // Static B0 baseline offset for (R, G, B, Lum)
  uniform vec2 u_ref_point = vec2(0.5, 0.5);     // Reference anchor (e.g., vec2(0.5, 0.5) for center)

  // --- VARYINGS ---
  // Hardware rasterizer interpolates 4D plane baseline linearly across the quad

  smooth out vec4 v_plane_baseline;

  vec4 position(mat4 transform_projection, vec4 vertex_position) {
      // Standard normalized UV coordinates (0.0 to 1.0)
      vec2 uv = VertexTexCoord.xy;
      vec2 delta = uv - u_ref_point;

      // Evaluate 4D linear plane equations (R, G, B, Lum) simultaneously
      // Evaluated only 4 times per quad draw call
      v_plane_baseline = delta.x * u_slopes_x + delta.y * u_slopes_y + u_plane_offset;
      
      return transform_projection * vertex_position;
  }

]],[[

#pragma language glsl3

    // Pseudo-constants
    vec2 wh = textureSize(MainTex, 0);
    vec2 aspect = wh / wh.y;

    // --- UNIFORMS ---
    uniform float u_vignette;
    
    // 2. Channel Gains & Offset
    uniform vec4 u_channel_gain;          // RGBL gain factors
    uniform float u_pedestal;             // Black point pedestal
    uniform float u_whitepoint;           // White point
    
    // 3. Intensity Weights
    uniform vec3 u_intensity_weights;     // RGB weights for synthetic lum
    uniform float u_Lratio;               // Lum : synthLum ratio

    // 4. Colour Mode / Saturation Switch
    // false = Pure Monochrome (vec3(I1)) -> Used when data is Lum-only or incomplete RGB
    // true  = Full Chromatic RGB Scaling -> Used when complete RGB color data is available
    uniform bool u_colour_mode = false; 

    const float eps = 1.0e-6;
    
    in vec4 v_plane_baseline;

  vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {
      
      // Read the 32-bit float stacked pixel (RGB + Measured Lum in Alpha)
      
          vec4 raw = Texel(tex, tc);
          
      // Adjust for vignetting

          vec2 xy = (tc - 0.5) * aspect;
//          float v = 1.0 + u_vignette * dot(xy, xy);            // parabolic
          float v = sqrt(1.0 + u_vignette * dot(xy, xy));      // hyperbolic
          // could generalise this sqrt to a power 0.5 .. 1.0 for family of vignetting curves
 
          raw = raw * v;
          
      // Subtract vertex-interpolated planar baseline & apply channel gains & pedestal 
      
          vec4 rgbl = (raw - v_plane_baseline) * u_channel_gain / u_whitepoint;
          rgbl = clamp(rgbl + u_pedestal, 0.0, 1.0); 
          
      // Calculate Mixed Intensity I0
      
          vec3 rgb = rgbl.rgb;
          float Irgb = dot(rgb, u_intensity_weights);
          float mixed_I0 = mix(Irgb, rgbl.a, u_Lratio);
          
      // Exit here if mono only
      
        if (!u_colour_mode) { return vec4(vec3(mixed_I0), 1.0); }

      // Compute Chromatic Vector (RGB Ratio Scaling)
      
        float maxc = max(rgb.r, max(rgb.g, rgb.b)) + eps;
        vec3 chromatic_colour = rgb * mixed_I0 / maxc;       // apply modified intensity

      // Desaturate low intensities
      
        float knee_point = 1.0 * u_pedestal;
        float sat_weight = smoothstep(0.0, knee_point, mixed_I0);    // are these values right?
        vec3 neutral_grey = vec3(mixed_I0);
        rgb = mix(neutral_grey, chromatic_colour, sat_weight);
  

      // Clamp and output to target canvas
        
        return vec4(clamp(rgb, 0.0, 1.0), 1.0);  }
]])


-------------------------
--
-- PLUGIN with controls
-- 

local plugin = {
  id = "SynthL", 
  static = true,
  documentation = [[
This plugin builds an LRGB composite image from any available Chrominance and Luminance channels from the stack.

This includes pure mono, one-shot colour (OSC), separate R G B filters, (or H, S, O).

On arrival of each new image, a mix of channels is updated to create a synthetic luminance for the composite image.  The criteria used to combine the channels is based on the number of images in each channel, the exposures (if available), and possibly the signal-to-noise ratios (variances).

The auto settings may subsequently be over-ridden by the manual controls for Red: Green/Blue ratio, and Green : Blue ratio.  Additionally, if both synthetic luminance from any RGB channels and a separately meanure luminance channel are available, then the balance between these may be changed with the Lum:Synth slider control.

Together these parameters provide complete control of the composite image luminance.
]],

  R_GB = {id = "R:GB",  default = 0.34, value = 0.34, style = "inline"},
  G__B = {id = "G:B ",  default = 0.5,  value = 0.5, style = "inline"},
  lum2synth = {id = "L:S ", value = 1, default = 1, format = "%.2f", style = "inline"},
}


-- RUN and DRAW methods

local sequence    -- last version of stack processed

-- get combined LRGB image from stack,
function plugin: run(workflow, wstack, background, gradient, balance, offset, whitepoint, vignette)

  -- calculate synth/luminance ratio for combination later, also whether enough rgb to do colour processing
  local R, G, B, L, Re, Ge, Be, Le = unpack(workflow.RGBL)  -- get exposure counts AND times

  if Re + Ge + Be + Le > 0 then                     -- use exposure times if available (issue #6)                        
    R, G, B, L = Re, Ge, Be, Le            
  end

  local enough_RGB = R > 0 and G > 0 and B > 0     -- something in all the channels  
  workflow.enough_RGB = enough_RGB

  -- Luminance : Synth Lum ratio
  local sumRGBL = (R + G + B) / 3 + L

  local lum2synth = self.lum2synth
  lum2synth.default = L / sumRGBL             -- ...always update default with latest auto value
  if sequence ~= workflow.sequence then
    sequence = workflow.sequence
    lum2synth.value = lum2synth.default       -- ...and current value if stack has changed
  end

  -- get RGB mixing ratio to calculate synthetic luminance
  local RGBmix, Lratio

  if enough_RGB then
    -- use prescribed values, overriding any calculated ones
    local r, g, b
    r = self.R_GB.value
    g = (1 - r) * self.G__B.value
    b = (1 - r) - g
    RGBmix = {r,g,b}
    Lratio = lum2synth.value
  else                      
    -- calculate best mix of available RGB, adding up to unity
    local sumRGB = (R + G + B) + 1e-6
    RGBmix = {R / sumRGB, G / sumRGB, B / sumRGB}
    Lratio = lum2synth.default
  end

  local pedestal = background.MAD * 4
  local pweight = pedestal * {R, G, B, 3 * L} / (3 * sumRGBL)
--  _log(pretty {workflow.RGBL, RGBmix = RGBmix, pweight = pweight})
  pedestal = pweight: sum()

  -- Transfer 32-bit Float Stack to 16-bit Fixed Target

  local params = {

    -- 1. Plane Slopes
    -- Linear is {Offsets, Xslope, Yslope}
    u_slopes_x = background.Linear[2] * gradient,     -- or * {1,1,1,gradient},
    u_slopes_y = background.Linear[3] * gradient,
    u_plane_offset = background.MEDIAN,               -- 'grey-sky' offsets,
--    u_whitepoint = whitepoint / ((pweight * background.MAX): sum()),
    u_whitepoint = whitepoint,
    u_vignette = vignette,
    u_ref_point = { 0.5, 0.5 },                       -- Plane centered at image midpoint

    -- 2. Channel Gains (Color Balance) & Offset
    u_channel_gain = balance,
    u_pedestal = pedestal * offset, 

    -- 3. Intensity_weights
    u_intensity_weights = RGBmix,
    u_Lratio = Lratio,

    --4. Colour
    u_colour_mode = enough_RGB,

  }

  lg.setBlendMode ("replace", "premultiplied")
  workflow: newInput (wstack.output)
  workflow: shadeWith(lrgb, params)

--  _log (pretty(params))
  return pedestal           -- default grey sky level (for MidTone stretch)

end


local left, right

function plugin: draw(suit)  

  local sl = suit.layout
  left = left or {align = "left", color = suit.theme.color.bluetext } -- only construct once
  right = right or {align = "right" }

  local W = 200 - 20

  local r, g, b
  r = (  100  ) * self.R_GB.value
  g = (100 - r) * self.G__B.value
  b = (100 - r) - g

  suit: Label("Lum:Synth ratio", left, sl:row(W,20))
  suit: Slideable(self.lum2synth, sl:row(W, 10))  

  local x,y = sl:row(0,20)
  suit: Label("R:G:B ratio", left, x,y, W,20)
  suit: Label("%d%%, %d%%, %d%%   " % {r, g, b}, right, x,y, W, 20)
  suit: Slideable(self.R_GB, sl:row(W, 10))
  suit: Slideable(self.G__B, sl:row())
end


return plugin

-----

