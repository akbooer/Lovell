--
-- controlpanel.lua
--

local _M = require "guillaume.objects" .GUIobject(...)

  _M.NAME = ...
  _M.VERSION = "2026.09.25"
  _M.DESCRIPTION = "control panel for main display"

local _log = require "logger" (_M)


-- 2026.05.19  split from mainGUI and redesign control layout using new Suitable widgets
-- 2026.09.25  use plugins.process_sequence() iterator


local controls  = require "controls"
local snapshot  = require "guillaume.snapshot"
local plugins   = require "plugins"

local love = _G.love
local lg = love.graphics

local margin = 240          -- margin width for panel
local Hb = 25               -- button height

local pin_controls = controls.pin_controls

local ocular = {[true] = "Eyepiece...", [false] = "Landscape..."}

local layout      -- set in update()

local pager = love.thread.getChannel "pager"   -- a way for components to change display page

local function row(...) return layout:row(...) end
--local function col(...) return layout:col(...) end

-- SUITable helper function to display plugins
local function Plugin(suit, name, ...)
  plugins: draw (name, suit, ...)
end

-------------------------------
--
-- UPDATE
--

function _M.update(suit, controls, image)
  suit.Plugin = Plugin          -- ensure plugin helper function is installed in suit instance

  layout = suit.layout
  layout:reset(10,10)             -- position the layout origin...
  layout:padding(10,5)           -- ...and put extra pixels between cells in each direction
    
  suit:Checkbox(pin_controls, layout:row(20, 20))
  
  local W = margin - 40
  local Wn = W - 20   -- narrow
  local Wh = W / 2   -- half
  local H = lg.getHeight()

--  suit: Choosable(controls.channelOptions, {size = {140, 25}}, row(W,Hb))

  suit: Plugin ("channel", row(W,Hb))
  
  -- LUMINANCE
  
  row(0,0)
  local Hb = 25
  local x,y, w,h 
  x,y, w,h = row(W/2 - 2, Hb)
  
  suit: Choosable(controls.gammaOptions, {id = '  ', shortcut= "G"}, x + Wh + 2, y, w, h)
  suit: Plugin("luminance", x,y, w,h)
 
  -- CHROMINANCE

  row(0,0)
  x,y, w,h = row(W/2 - 2, Hb)
  suit: Choosable(controls.palette, {id = ' '}, x + Wh + 2, y, w, h)
  
  local chroma = controls.palette: get()    -- selected chroma workflow name
  suit: Plugin(chroma, x,y, w,h)
  
  row(0,0)
  
  x,y, w,h = row(W/2 - 2, Hb)
  suit: Plugin("synth", x,y, w,h)
  
  -- CONFIGURABLE PLUGINS
  
  local new_row
  for _, plugin in plugins.process_sequence() do
    if new_row then
      x,y, w,h = row(W/2 - 2, Hb)
      suit: Plugin(plugin, x,y, w,h)
    else
      suit: Plugin(plugin, x + Wh + 2, y, w, h)
    end
    new_row = not new_row
  end
      
  -- PRESTACK and STACK
  
  row(W, 40)
  x,y, w,h = row(W/2 - 2, Hb)
  suit: Controllable(controls.prestack, x,y, w,h)
  suit: Controllable(controls.stacking, {indent = 60 - Wh / 2}, x + Wh + 2, y, w, h)
     
  -- DATABASES
  
  local button = suit: Choosable(controls.DBnames, {title = "Databases..."}, row(W, Hb))
  if button.hit then
    pager: push "database"
  end

-- TODO: PLATE SOLVE

--  slider (core, "Magnitude", w, 10)

  -- orientation and snapshot
 
  layout: reset(10, H - 125, 10, 10)
  layout: row(10, 10)
  local label = ocular[controls.eyepiece.checked]
  if suit: Button(label, layout: row(W, 30)) .hit then
    controls.eyepiece.checked = not controls.eyepiece.checked
  end
 
  if suit:Button ("Snapshot", layout:row(80, 50)) .hit then
    snapshot.snap(image) 
  end
  
  layout:col(5, 20)
  
  suit:Checkbox (controls.flipUD, layout:col(120, 20))
  suit:Checkbox (controls.flipLR, layout:row(120, 20))
 end


return _M

-----
