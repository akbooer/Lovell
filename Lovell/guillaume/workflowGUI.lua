--
-- workflowGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.12.23"
  _M.DESCRIPTION = "workflow GÜI"

local _log = require "logger" (_M)

-- 2024.12.18  Version 0


local session = require "session"


local suit = require "suit"

local self = suit.new()     -- make a new SUIT instance for ourselves

local w = session.controls.workflow   -- export

local M = 60    -- margin
local W = 120

local layout = self.layout

local lalign = {align = "left"}
local ralign = {align = "right"}
local valign = {valign = "top"}

local function reset(margin)
  M = margin or M
  local x, y = layout:down(20, 20)
  layout: reset(M, y, 10, 10)
end

local function down(w, h)
   layout: down(w or 5, h or 5) 
end

local function row(...)
  return layout: row(...)
end

local function col(...)
  return layout: col(...)
end

-------------------------------
--
-- Luminance / LRGB
--
  
local function mono()
  layout: reset(50,100, 10, 10)
  
  reset(60)
  self: Button("Luminance", row(W, 30))
  down()
    
  self: Checkbox(w.badpixel, row(200, 20))
  down()
  self: Label("ratio", ralign, col(W, 10))
  self: Slider(w.badratio, col(W, 10))
  self: Label("%.1f" % w.badratio.value, col(W/3, 10))
  
--  reset()
--  self: Checkbox(w.debayer, layout: row(W, 20))
--  down()
--  self: Label("pattern", ralign, layout:col(W, 20))
--  self: Input(w.bayerpat, {id = "bayer", align = "left"}, layout:col(W, 20))

  reset()
  self: Label("star finder", lalign, row(W, 20))
  down()
  self: Label("max #stars", ralign, col(W, 10))
  self: Slider(w.maxstar, col())
  self: Label("%.0f" % w.maxstar.value, col(W/3, 10))
  reset()
  down()
  self: Label("radius", ralign, col(W, 10))
  self: Slider(w.keystar, col())
  self: Label("%.1f" % w.keystar.value, col(W/3, 10))
  
  reset()
  self: Label("alignment", lalign, row(W, 20))
  down()
  self: Label("max offset", ralign, col(W, 10))
  self: Slider(w.offset, col())
  self: Label("%.0f" % w.offset.value, col(W/3, 10))
  
  
  reset()
  self: Label("stacking mode", lalign, row(W, 20))
  row(W/2, 30)
  self: Button("Average", col(W, 30))
--  reset()
--  self: Label("colour denoise", lalign, layout: row(W, 20))
  
  reset()
  self: Label("denoise", lalign, row(W, 20))
  
  reset()
  self: Label("sharpening", lalign, row(W, 20))
end


-------------------------------
--
-- COLOUR
--
  
local function colour()
  layout: reset(450,100, 10, 10)
  
  reset(460)
  self: Button("Colour", row(W, 30))
  down()
  
  reset()
  self: Checkbox(w.debayer, row(W, 20))
  down()
  self: Label("pattern", ralign, col(W, 20))
  self: Input(w.bayerpat, {id = "bayer", align = "left"}, col(W, 20))
  
  reset()
  self: Label("RGB weights", lalign, row(W,20))
  
  self: Label("R", ralign, row())
  self: Slider(w.Rweight, col(W, 10))
  layout: left()
  row()
  self: Label("G", ralign, row())
  self: Slider(w.Gweight, col())
  layout: left()
  row()
  self: Label("B", ralign, row())
  self: Slider(w.Bweight, col())
  
  reset()
  self: Label("colour denoise", lalign, row(W, 20))
end


-------------------------------
--
-- UPDATE / DRAW

function _M.update(dt)
  layout: reset(200,20, 10, 10)
  
  self: Button ("Processing Workflow", col(200, 30))

  mono()
  colour()
  
end

function _M.draw()
  self: draw()
end

 
-------------------------
--
-- KEYBOARD
--

function _M.keypressed(key)
  self:keypressed(key)
end

function _M.textinput(...)      
  self:textinput(...)
end

return _M

-----
