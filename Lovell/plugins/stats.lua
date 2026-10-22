--
-- stats.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – Report image statistics",
  }

require "logger" (_M)

-- 2026.10.14  Version 0


local plugin = {
    id = "Statistics",
    lum_only = {checked = false, default = false, text = "lum only", },
}

plugin.documentation = [[
Statistical analysis of a population sample from the stacked image (typically 10,000 points).

MAD (Mean Absolute Deviation) is calculated as the median value of the the lower half of the intensity distribution.
]]


-- RUN and DRAW methods

local line = {}
local left = {align = "left"}
local titles = table.concat({"name", 'R', 'B', 'G', 'L'}, (' '): rep(14))
local subs = {}

function plugin: run(workflow)
  local b = workflow.wstack.info.background    -- shouldn't have to dig this depp!
  if b then
    line = {
        {"mean",    unpack(b.Linear[1])},
        {"median",  unpack(b.MEDIAN)},
        {"MAD",     unpack(b.MAD)},
        {"min",     unpack(b.MIN)},
        {"max",     unpack(b.MAX)},
      }
    subs = {"#subs", unpack(workflow.RGBL)}
  end
end


function plugin: draw(suit)  
  local W, H = 315, 20
  local sl = suit.layout
  local x,y = sl: row(W, H)
  
  suit: Label(titles, left, x,y, W,H)
  
  local fmt = "%s"
  for col = 1, 5 do   -- column-wise to ensure alignment (variable width font)
    local xc = x + (col-1) * 65
    for i, item in ipairs(line) do
      suit: Label(fmt % item[col], left, xc, y + (i+1) * H, W, H)
    end
    suit: Label(tostring(subs[col]), left, xc, y + (#line+2) * H, W, H)
    fmt = "%7.5f"
  end
  
  sl: row(W, (#line+1) * H)
  sl: row(W,1)    -- TODO: somehow necessary to avoid lower items being pushed down - WHY?

end


return plugin

-----

