--
-- balance.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.08.04",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – RGB channel balance gains",
  }

require "logger" (_M)

-- 2026.08.04  Version 0, extracted from RGB plugin


local love = _G.love
local lg = love.graphics

local align = {align = "left"}

-------------------------------
--
-- CONTROLS
--

local plugin = {
    id = "Balance",
    R = {id = 'R', value = 1, default = 1, min = .5, max = 1.5, format = "%.1f", style = "inline"},
    G = {id = 'G', value = 1, default = 1, min = .5, max = 1.5, format = "%.1f", style = "inline"},
    B = {id = 'B', value = 1, default = 1, min = .5, max = 1.5, format = "%.1f", style = "inline"},
    
    documentation = [[
Balance controls for R,G, and B channels.
    
These should only be used to compensate for filter transmissibility changes, used sparingly, and not for adjusting colour balance... 
    
For that, use the chroma-specific plugin controls such as temperature or tint (for RGB) or gold_boost or un_green (for Hubble / HSO).]],
    
  }

-------------------------------
--
-- RUN and DRAW
--

function plugin: run(workflow)
  -- required, but nothing to do here, since other processing uses these values directly
  -- ... this means that it doesn't matter where it appears in the post-processing chain
end


function plugin: draw(suit)
  local sl = suit.layout
  local W, Hb = 180, 25
  local Ws = W - 20

  suit: Label("channel weights", sl:row(W, 15))
  suit: Slideable(self.R, sl:row(Ws, 10))
  suit: Slideable(self.G, sl:row())
  suit: Slideable(self.B, sl:row())
end

return plugin

-----

