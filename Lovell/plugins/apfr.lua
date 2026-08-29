--
-- apfr.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.27",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – APF-R sharpening [Kaltseis 2015]",
  }

local _log = require "logger" (_M)


-- 2024.11.07  Version 0, @akbooer

-- 2025.05.14  consolidate apf() for different numbers of backgrounds into one single code

-- 2026.06.27 split into separate plugin, add separate controls for each scale
-- 2026.07.04  use workflow:shadeWith()


local love = _G.love
local lg = love.graphics

-------------------------------
--
-- APF-R
--

--[[

The APF-R (Absolute Point of Focus Reduction or simply Absolute Point of Focus) method was invented and developed by Christoph Kaltseis, an award-winning Austrian astrophotographer, image processing expert, and co-founder of the Central European Deepsky Imaging Conference (CEDIC). [1, 2, 3] 

------------------------------

The Origin and Timeline

* Development (2010–2015): Kaltseis spent roughly five years researching, testing, and experimenting with various astronomical and daylight images. He wanted to solve a major flaw in traditional sharpening tools (like High-Pass, Wavelets, or Deconvolution), which often distort stars, add clipping artifacts, and introduce harsh digital noise into delicate deep-sky images. [4, 5, 6, 7, 8] 
* Public Debut (2015): Kaltseis first publicly revealed and explained the foundational concepts of the APF-R workflow at the CEDIC conference in Linz, Austria. [3] 
* The Manual Era: Originally, APF-R was not a software program. It was a complex, time-consuming sequence of layer masks, blending modes, and subtraction steps executed manually inside Adobe Photoshop. Kaltseis eventually packaged these steps into Photoshop "Actions" to automate the tedious math for amateur astronomers. [4, 9] 


##Scientific Validation: The Hubble Connection

Shortly after debuting the method in 2015, Kaltseis sent the workflow documentation to the image processing specialists managing the Hubble Space Telescope for NASA and ESA. [3, 10] 

* The team initially found the claims "too good to be true" because it extracted micro-details from space imagery without adding high-frequency noise. [3, 5] 
* After rigorous testing, the Hubble Space Telescope team adopted APF-R into their official post-processing toolkit. [2, 3] 
* It has been used to process heavily publicized public space imagery, including the famous "Return to the Veil Nebula" Picture of the Week released on 29 March 2021. [3] 


## Commercialization and Modern Accessibility

In June 2021, Kaltseis partnered with the software development firm Picture Instruments to translate the underlying mathematical workflow into a compiled, retail C++ architecture. They launched the official APF-R Plugin for Adobe Photoshop, turning a massive stack of manual layer operations into a streamlined, automated, single-click image processing module. [1, 5, 9, 11] 

## The Philosophical Breakthrough

The fundamental genius behind Kaltseis’s method –and why it translates beautifully into the custom LÖVE GLSL v3 shader framework– is its rejection of linear sharpening. Traditional tools uniformly inflate the contrast of edges, which causes star halos and dark artifacts. APF-R treats an image like a multi-scale sculpture. By isolating specific structural scales and gating them using non-linear equations (the exponential curve we used), it mirrors how light actually diffuses through astronomical gas and optical lenses. It gives deep-sky details an organic sense of three-dimensional depth rather than a flat, artificial, over-processed overlay. [1, 10, 12] 

[1] [https://picture-instruments.com](https://picture-instruments.com/products/index.php?id=41&lang=en)
[2] [https://www.baader-planetarium.com](https://www.baader-planetarium.com/en/blog/apf-r-absolute-point-of-focus/)
[3] [https://picture-instruments.com](https://picture-instruments.com/news/blog.php?lang=en&blog=2021_6_story_apfr)
[4] [https://www.baader-planetarium.com](https://www.baader-planetarium.com/de/blog/apf-r-absolute-point-of-focus/)
[5] [https://www.youtube.com](https://www.youtube.com/watch?v=6DxDrYrtPUw)
[6] [https://www.youtube.com](https://www.youtube.com/watch?v=T_7-wlmy_1Q&t=73)
[7] [https://www.baader-planetarium.com](https://www.baader-planetarium.com/en/blog/apf-r-absolute-point-of-focus/)
[8] [https://pmc.ncbi.nlm.nih.gov](https://pmc.ncbi.nlm.nih.gov/articles/PMC3594524/)
[9] [https://www.youtube.com](https://www.youtube.com/watch?v=mA2LcL69QqU&t=12)
[10] [https://picture-instruments.com](https://picture-instruments.com/products/index.php?id=41)
[11] [https://vimeo.com](https://vimeo.com/561766972)
[12] [https://www.youtube.com](https://www.youtube.com/watch?v=U10GVjirknk)

--]]


local apfr = lg.newShader [[
#pragma language glsl3

uniform Image u_smoothReference;
uniform float u_sharpenFactor; 
uniform float u_sensitivity;          // Range: 4.0 (Very Soft) to 24.0 (Aggressive)

vec4 effect(vec4 color, Image MainTex, vec2 texture_coords, vec2 screen_coords) {
    // 1. Isolate raw texture data completely from global LÖVE tints to protect dead channels.
    vec4 centerColor = Texel(MainTex, texture_coords);
    vec4 smoothColor = Texel(u_smoothReference, texture_coords);

    // 2. Extract structural detail delta across all channels (RGBA) in parallel.
    // If a channel is missing (like G or B in "r16f"), both center and smooth 
    // will be 0.0, so the delta automatically results in a perfectly safe 0.0.
    vec4 detailDelta = centerColor - smoothColor;
    
    // 3. ENHANCED ADAPTIVE SHARPNESS EQUATION (Per-Channel Vector)
    // Using abs() on the vector evaluates the scale factor for each channel individually.
    vec4 modulationWeight = vec4(1.0) - exp(-abs(detailDelta) * u_sensitivity);

    // 4. Construct the focus detail layer for all channels
    vec4 apfrDetail = detailDelta * modulationWeight * u_sharpenFactor;

    // 6. Combine details and output the safe final structure.
    vec4 finalColor = centerColor + apfrDetail;

    // 7. Force the Alpha channel back to its original state or 1.0 
    // This stops sharpening math from accidentally making transparent areas opaque.
    finalColor.a = centerColor.a;

    return finalColor;
}

]]

--[[
APFR.globalNoiseFloor = 0.03 -- Default setting: mutes anything below 3% brightness

APFR.pipeline = {
    scales = {
        { name = "Fine Stars (4px)",     sigma = 1.7,  strength = 0.15, sensitivity = 20.0, useGate = true },
        { name = "Dust Filaments (8px)",  sigma = 3.4,  strength = 0.30, sensitivity = 14.0, useGate = true },
        { name = "Gas Billows (16px)",    sigma = 8.0,  strength = 0.50, sensitivity = 8.0,  useGate = false },
    }
}

--]]


local plugin = {
    id = "Sharpen",    -- "APF-R", 
--    indent = 0,
  
    {id = " fine",   value = 0.0, max = 1, default = 0, sigma = 2,  sensitivity = 20},
    {id = " medium", value = 0.0, max = 1, default = 0, sigma = 8,  sensitivity = 10},
    {id = " coarse", value = 0.0, max = 2, default = 0, sigma = 32, sensitivity = 5},

  documentation = [[The APF-R (Absolute Point of Focus Reduction or simply Absolute Point of Focus) method was invented and developed by Christoph Kaltseis, an Austrian astrophotographer.
  
Traditional tools uniformly inflate the contrast of edges, which causes star halos and dark artifacts. APF-R isolates specific structural scales and applies non-linear transformations.

There is an official APF-R Plugin for Adobe Photoshop.  This is a simplified implementation which attempts to capture something of the essence of the original process.]],
  
  } 
  

function plugin:run(workflow, ...)
    
  workflow: save "temp"             -- reference image for blurring
  
  for i = 1, 3 do
    local sharpen = self[i].value
    if sharpen > 0.02 then
      
      workflow: save "temp1"                -- current image
      workflow: newInput "temp"             -- reference image for blurring
      workflow: gaussian(self[i].sigma)
    
      workflow: newInput "temp1"
      workflow: shadeWith (apfr, {
                  u_smoothReference = workflow["output"],   -- this is OK, since temp1 is new input, not previous output
                  u_sharpenFactor = sharpen,
                  u_sensitivity = self[i].sensitivity})
    end
  end
  
end
  
  
function plugin: draw(suit)
  local sl = suit.layout
  sl:padding(20, 5)
  local W = 180 - 20
  suit: Label("multiscale sharpen", sl:row(W, 20))
      
  for i = 1, 3 do
    suit: Slideable(self[i], sl:row(W, 10))
  end

end


return plugin


-----


