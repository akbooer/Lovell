--
-- workflowGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.12.18"
  _M.DESCRIPTION = "workflow GÜI"

local _log = require "logger" (_M)

-- 2024.12.18  Version 0


local session = require "session"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local suit = require "suit"

local self = suit.new()     -- make a new SUIT instance for ourselves

local w = session.controls.workflow   -- export

local M = 60    -- margin
local W = 120

local layout = self.layout

local lalign = {align = "left"}
local ralign = {align = "right"}

local function reset()
  local x, y = layout:down(20, 20)
  layout: reset(M, y, 10, 10)
end

local function down()
   layout: down(5,5) 
end

-------------------------------
--
-- UPDATE / DRAW

function _M.update(dt)
  layout: reset(50,100, 10, 10)
  
  reset()
  self: Checkbox(w.badpixel, layout: row(200, 20))
  down()
  self: Label("ratio", ralign, layout:col(W, 10))
  self: Slider(w.badratio, layout: col(W, 10))

  reset()
  self: Checkbox(w.debayer, layout: row(W, 20))
  down()
  self: Label("pattern", ralign, layout:col(W, 20))
  self: Input(w.bayerpat, {id = "bayer", align = "left"}, layout:col(W, 20))

  reset()
  self: Label("star finder", lalign, layout: row(W, 20))
  
  reset()
  self: Label("alignment", lalign, layout: row(W, 20))
  
  reset()
  self: Label("stacking mode", lalign, layout: row(W, 20))
  
  reset()
  self: Label("colour denoise", lalign, layout: row(W, 20))
  
  reset()
  self: Label("denoise", lalign, layout: row(W, 20))
  
  reset()
  self: Label("sharpening", lalign, layout: row(W, 20))
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
