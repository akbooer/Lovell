--
-- synth_lum.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.08.02",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Luminance",
  }

require "logger" (_M)

-- 2026.08.02  Version 0, extracted from controls.luminance


local love = _G.love
local lg = love.graphics



local rgb = {Red = {1,0,0}, Green = {0,1,0}, Blue = {0,0,1}, Luminance = {0.3, 0.6, 0.1}}

-- PLUGIN with controls (in this case, just a Choosable)

local plugin = {
        id = "Luminance ",    -- trailing space to distinguish from Luminance channel name
        documentation =[[
Luminance processing for both one-shot colour (OSC) and mono images (filtered or otherwise).

Background level and Stretch are always visible, whereas gradient, vignetting, and white point controls are available on the drop-down menu.

Vignetting adjustment is particularly valuable for wide-angle (short F-ratio) systems when a master flat is not available.
]],

        static = true,
        background = {id  = "background", value = 0.5, default = 0.5},
        whitepoint = {id = "white point", value = 1, default = 1},
--        brightness = {id = "brightness", value = 0.5, default = 0.5},
        
        stretch =  {id = "stretch", default = 1, value = 1, max = 2},
        gradient = {id = "gradient", default = 0, value = 0, min = -1, max = 1},
        vignette = {id = "vignette", default = 0, value = 0, min = -1, max = 1},
        
    }


-- RUN and DRAW methods


function plugin: run(workflow, ...)

end

 
function plugin: draw(suit)  

  local sl = suit.layout
  self.left = self.left or {align = "left", color = suit.theme.color.bluetext } -- only construct once
  self.right = self.right or {align = "right" }
  self.centre = self.centre or {color = suit.theme.color.inactive }
  
  local W = 180 - 20

  suit: Slideable(self.gradient, sl:row(W, 10))
  suit: Slideable(self.vignette, sl:row())
  suit: Slideable(self.whitepoint, sl:row())
  
end


function plugin: extras(suit)
  local sl = suit.layout
  local W = 200 - 20
  
  sl: row(0,0)
  suit: Slideable(self.background, sl: row(W, 10))
  suit: Slideable(self.stretch, sl: row())

end

return plugin

-----

