--
-- blurCompare.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.01",
    AUTHOR = "AK Booer / Kovesi",
    DESCRIPTION = "PLUGIN – compare Gaussian and several Mipmap blurs",
  }

local _log = require "logger" (_M)

-- 2026.07.01  Version 0, @akbooer



-- PLUGIN with controls


local plugin = {
    id = "Blur", 
    sigma = {id = "sigma",  value = 0, default = 0, max = 50},    -- filter width
    choice = {"Kovesi", "MipBlur", "Tetrad", selected = 1, default = 1}, 
  }

-- RUN and DRAW methods

local options = {}

function plugin: run(workflow, ...)
  local sigma = self.sigma.value
  if sigma < 0.2 then return end
      
  -- swap out the implementation FOR THE WHOLE CHAIN!
  options[1] = workflow.kovesi
  options[2] = workflow.mipblur
  options[3] = workflow.tetrad
  
  local choice = options[self.choice.selected]
  workflow.gaussian = choice
    
  workflow: gaussian(sigma)   -- might be any of the options

end

 
function plugin: draw(suit)  
  local sl = suit.layout
  local W = 180 - 20
  suit: Label("sigma width", sl:row(W, 20))
  suit: Choosable(self.choice, sl:row(W, 20))
  suit: Label('', sl:row())
  suit: Slideable(self.sigma, sl:row(W, 10))      -- draw the width slider
  suit: Label('', sl:row())
end


return plugin

-----

