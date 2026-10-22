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


-- PLUGIN with controls (in this case, just a Choosable)

local plugin = {
      id = "Luminance ",    -- trailing space to distinguish from Luminance channel name

      static = true,        -- can't manually insert into workflow
      split = true,         -- start of with split menu display (can be toggled subsequently)
      
      background = {id  = "background", value = 0.5, default = 0.5},
      whitepoint = {id = "white point", value = 1, default = 1},
      
      stretch =  {id = "stretch", default = 1, value = 1, max = 2},
      gradient = {id = "gradient", default = 0, value = 0, min = -1, max = 1},
      vignette = {id = "vignette", default = 0, value = 0, min = -1, max = 1},
      
    }

plugin.documentation =[[
Luminance processing for both one-shot colour (OSC) and mono images (filtered or otherwise).

Background level and Stretch are visible at the top level if drop-down menu is split.

Gradient, Vignetting, and White point controls are available on the drop-down menu.

Vignetting adjustment is particularly valuable for wide-angle (short F-ratio) systems when a master flat is not available.
]]

-- RUN and DRAW and EXTRAS methods


function plugin: run()      -- (workflow, ...)
  -- nothing to do!  (it's all in the graphics)
end


function plugin: extras(suit, width)
  local sl = suit.layout
  local W = width or 180
    
  suit: Slideable(self.background, sl: row(W, 10))
  suit: Slideable(self.stretch, sl: row())

end


function plugin: draw(suit)  

  local sl = suit.layout
  
  local W = 180 - 20
  
  suit: Slideable(self.gradient, sl:row(W, 10))
  suit: Slideable(self.vignette, sl:row())
  suit: Slideable(self.whitepoint, sl:row())
  
  self: extras(suit)

end


return plugin

-----

