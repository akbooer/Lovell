--
-- rgb.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.09.30",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – RGB workflow",
}

local _log = require "logger" (_M)


-- 2024.11.07  Version 0, @akbooer

-- 2026.06.27  split from poststack module into separate plugin
-- 2026.09.30  skip processing if not needed


local love = _G.love
local lg = love.graphics



-------------------------------

local plugin = {
      id = "Chroma", 
    
      static = true,        -- can't manually insert into workflow
      split = true,         -- start of with split menu display (can be toggled subsequently)
      
      saturation  = {id = "saturation", value = 1, default = 1, max = 2},
      
      tint        = {id = "tint", value = 0, default = 0, min = -1, max = 1},              -- Green : Magenta  (G:RB)
      temperature = {id = "temperature", value = 0, default = 0, min = -1, max = 1},       --  Blue : Yellow   (B:RG)
      -- Subtractive Chromatic Noise Reduction (Green) in percent 100% enabled by default
      scnr = {id = "scnr (green)", value = 80, default = 80, min = 0, max = 100, format = "%d%%"},
    
    }
  
  
plugin.documentation = [[
RGB processing for both one-shot colour (OSC) and filtered mono images.

Saturation and Temperature (Blue : Yellow balance) are visible at the top level if drop-down menu is split.

Tint (Green : Magenta balance) and SCNR (Subtractive Chromatic Noise Reduction - Green) controls are available on the drop-down menu.
]]

 
-------------------------------
--
-- RUN and DRAW and EXTRAS
--

function plugin: run(workflow, ...)
  local temp, tint = self.temperature.value/2, self.tint.value/2
  
  if not workflow.enough_RGB then return end        -- nothing to do
  
  if (temp ~= 0 or  tint ~= 0) then
    workflow: temp_tint(temp, tint)         -- colour temperature and tint
  end
  
  local scnr = self.scnr.value
  if scnr > 0 then
    workflow: scnr( scnr / 100)            -- Subtractive Chromatic Noise Reduction (Green) in percent
  end
  
  local sat = self.saturation.value
  if sat ~= 1 then
--    workflow: satboost((self.saturation.value - 1) * 2 + 1)      -- apply saturation boost
    workflow: satboost(sat ^ 1.5)      -- apply saturation boost
  end
end


function plugin: draw(suit)
  local sl = suit.layout

  local W = 160

  suit: Slideable(self.tint, sl:row(W, 10))
  suit: Slideable(self.scnr, sl:row())
  
  self: extras(suit)    -- draw the additional controls

end


function plugin: extras(suit, width)
  local sl = suit.layout
  local W = width or 180
  
  suit: Slideable(self.saturation, sl:row(W, 10))
  suit: Slideable(self.temperature, sl:row(W, 10))
end


return plugin

-----


