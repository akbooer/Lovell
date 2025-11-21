--
-- workflowGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.06.12"
  _M.DESCRIPTION = "workflow GUI"

local _log = require "logger" (_M)

-- 2024.12.18  Version 0
-- 2025.06.12  improve layout handling


local session = require "session"
local suit    = require "suit" .new()     -- make a new SUIT instance for ourselves

local love = _G.love
local lg = love.graphics

local controls = session.controls
local w = controls.workflow           -- export

local lalign = {align = "left"}
local ralign = {align = "right"}

local layout = suit.layout
local row, col = _M.rowcol(layout)

-------------------------------
--
-- PRESTACK
--

local function prestack(xywh)
  local X, Y, W = unpack(xywh)
  layout: reset(X, Y, 10, 10)
  
  suit: Button("Prestack", row(W - 100, 30))
   
  suit: Checkbox(w.do_dark, row(200, 20))
  suit: Checkbox(w.do_flat, row())
  suit: Checkbox(w.badpixel, row())
  
  suit: Label("ratio", ralign, row(W/4, 10))
  layout: push(layout: nextCol())
    suit: Slider(w.badratio, col(W/4, 10))
    suit: Label("%.1f" % w.badratio.value, lalign, col())
  layout: pop()
  
  suit: Checkbox(w.debayer, row(W, 20))
  suit: Label("pattern", ralign, row(W/4, 20))
  suit: Dropdown(w.bayer_opt, {id = "bayer"}, col(120, 30))

end

-------------------------------
--
-- STACKING
--

local function stack(xywh)
  local X, Y, W = unpack(xywh)
  layout: reset(X, Y, 10, 10)
  
  suit: Button("Stack", row(W - 100, 30))
  
  suit: Label("star finder", lalign, row(W, 20))
  suit: Label("max #stars", ralign, row(W/4, 10))
  layout: push(layout: nextCol())
    suit: Slider(w.maxstar, col(W/4, 10))
    suit: Label("%.0f" % w.maxstar.value, lalign, col(W/3, 10))
  layout: pop()

--  self: Label("radius", ralign, col(W, 10))
--  self: Slider(w.keystar, col())
--  self: Label("%.1f" % w.keystar.value, col(W/3, 10))
  
  suit: Label("alignment", lalign, row(W, 20))
  suit: Label("max offset", ralign, row(W/4, 10))
  layout: push(layout: nextCol())
    suit: Slider(w.offset, row(W/4, 10))
    suit: Label("%.0f" % w.offset.value, lalign, col(W/3, 10))
  layout: pop()
  
  suit: Label("stacking", lalign, row(W, 20))
  suit: Label("mode", ralign, row(W/4, 30))
  suit: Dropdown(controls.stackOptions, col(W/3, 30))
end

-------------------------------
--
-- POSTSTACK
--
  
local function poststack(xywh)
  local X, Y, W = unpack(xywh)
  layout: reset(X, Y, 10, 10)
  
  suit: Button("Poststack", row(W - 100, 30))
  
  suit: Label("denoise", lalign, row(W, 20))
  suit: Label("sharpening", lalign, row(W, 20))

end

-------------------------------
--
-- COLOUR
--

local Cr, Cg, Cb = {}, {}, {}   -- unique IDs
local fmt = "%4.1f"

local function colour(xywh)
  local X, Y, W = unpack(xywh)
  layout: reset(X, Y, 10, 10)
    
  suit: Button("Colour", row(W - 100, 30))
  
  suit: Label("Channel weights", lalign, row(W, 20))
  
  suit: Label("R", ralign, row(40, 10))
  layout: push(layout: nextCol())
    suit: Slider(w.Rweight, col(W/4, 10))
    suit: Label(fmt % (w.Rweight.value), Cr, col(40, 10))
  layout: pop()
  
  suit: Label("G", ralign, row())
  layout: push(layout: nextCol())
    suit: Slider(w.Gweight, col(W/4, 10))
    suit: Label(fmt % (w.Gweight.value), Cg, col(40, 10))
  layout: pop()
  
  suit: Label("B", ralign, row())
  layout: push(layout: nextCol())
    suit: Slider(w.Bweight, col(W/4, 10))
    suit: Label(fmt % (w.Bweight.value), Cb, col(40, 10))
  layout: pop()
  
end

-------------------------------
--
-- UPDATE / DRAW

function _M.update()
  local w, h = lg.getDimensions()
  layout: reset(200,20, 10, 10)
  
  suit: Button ("Processing Workflow", col(200, 30))

  local col = layout:cols {pos = {50, 100}, min_width = w, {"fill", 20}, "fill", "fill"}
  
  for i, panel in ipairs {prestack, stack, poststack} do
    panel(col[i])
  end
  
  colour {50, 50 + h/2, w/3, h/2}
  
end

function _M.draw()
  suit: draw()
end

-------------------------
--
-- KEYBOARD
--

function _M.keypressed(key)
  suit:keypressed(key)
end

function _M.textinput(...)      
  suit:textinput(...)
end


return _M

-----
