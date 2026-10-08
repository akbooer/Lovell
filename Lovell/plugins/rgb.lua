--
-- rgb.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.0.30",
  AUTHOR = "AK Booer",
  DESCRIPTION = "PLUGIN – RGB workflow",
}

local _log = require "logger" (_M)


-- 2024.11.07  Version 0, @akbooer

-- 2026.06.27  split from poststack module into separate plugin
-- 2026.09.30  skip processing if not needed


local color, centre

-------------------------------


local saturation  = {id = "saturation", value = 1, default = 1, max = 2}
local tint        = {id = "tint", value = 0, default = 0, min = -1, max = 1}              -- Green : Magenta  (G:RB)
local temperature = {id = "temperature", value = 0, default = 0, min = -1, max = 1}       --  Blue : Yellow   (B:RG)

-- Subtractive Chromatic Noise Reduction (Green) in percent 100% enabled by default
local scnr = {id = "scnr (green)", value = 80, default = 80, min = 0, max = 100, format = "%d%%"}

-------------------------------
--
-- RUN and DRAW
--

local function run(self, workflow)
  local temp, tint = temperature.value/2, tint.value/2
  
  if not workflow.enough_RGB then return end        -- nothing to do
  
  if (temp ~= 0 or  tint ~= 0) then
    workflow: temp_tint(temp, tint)         -- colour temperature and tint
  end
  
  local scnr = scnr.value
  if scnr > 0 then
    workflow: scnr( scnr / 100)            -- Subtractive Chromatic Noise Reduction (Green) in percent
  end
  
  local sat = saturation.value
  if sat ~= 1 then
--    workflow: satboost((saturation.value - 1) * 2 + 1)      -- apply saturation stretch
    workflow: satboost(saturation.value ^ 1.5)      -- apply saturation stretch
  end
end


local function draw(self, suit)
  local sl = suit.layout
  color = suit.theme.color.bluetext
  centre = centre or {color = suit.theme.color.inactive }

  local W = 180
  local Ws = W - 20

  suit: Slideable(tint, sl:row(Ws, 10))
  suit: Slideable(scnr, sl:row(Ws, 10))

end

local function extras(self, suit)
  local sl = suit.layout
  sl:padding(20, 5)
  local Ws = 180
  suit: Slideable(self.saturation, sl:row(Ws, 10))
  suit: Slideable(self.temperature, sl:row())
end


return {
  id = "Chroma", 
  
  documentation = [[
RGB processing for both one-shot colour (OSC) and filtered mono images.

Saturation and Temperature (Blue : Yellow balance) are always visible, Tint (Green : Magenta balance) and SCNR (Subtractive Chromatic Noise Reduction - Green) controls are available on the drop-down menu.
]],

  static = true,

  -- controls (exported so that they can be reset)
  saturation = saturation,
  tint = tint,
  temperature = temperature,
  scnr = scnr,

  -- methods
  extras = extras,
  draw = draw,
  run = run,
}

-----


