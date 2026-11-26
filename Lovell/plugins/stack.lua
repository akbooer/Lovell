--
-- stack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.11.26",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – stacking and alignment options",
  }

require "logger" (_M)

-- 2026.11.20  Version 0, extracted from controls
-- 2026.11.26  add reset(), but comment out temporarily for issue #22 (RELOAD loop)


local stackOptions = require "shaders.stacker".stackOptions

local love = _G.love
local le = love.event

local lalign = {align = "left"}


local plugin = {
    id = "Stack",
    static = true,
    stack_opt = stackOptions,
    
    -- max # stars to find
    maxstar = {id = "#stars", value =  30, default =   30, min = 10, max = 40,  format = "%3d", style = "inline"},
}

plugin.documentation = [[
'View Stack...' switches to the stack viewer page.

'Mode: ...' menu switches between Average and Minimum Variance stacking modes.  The stack immediately starts recomputing.

'#stars" controls the number of stars used for the image alignment process.

]]


-- RUN and DRAW methods


--function plugin: reset()
  
--end

function plugin: run()
  -- required, but does nothing
end

 
function plugin: draw(suit)  
  local sl = suit.layout
  local Hb = 25
  local W = 160
  
  sl: row(0, 0)
  if suit: Button("View Stack...", sl:row(W, Hb)) .hit then 
    le.push ("page", "stack")
  end 
  
  local mode = self.stack_opt
  local old = mode.selected
  suit: Choosable(mode, sl:row(W)) 
  if mode.selected ~= old then
    le.push("target", "RELOAD")
  end
  
  suit: Label("Alignment", lalign, sl:row(W, 20))
  suit: Slideable(self.maxstar, sl:row(W, 10))
  suit: Label('', lalign, sl:row(W, 20))

end


return plugin

-----

