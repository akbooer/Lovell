--
-- güillaume.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.19",
    DESCRIPTION = "GÜI Library for LÖVELL App Using Minimal Effort (built on SUIT)",
  }


-- 2024.11.01
-- 2024.11.05  use SUIT (Simple User Interface Toolkit)

--[[

  Different display modes use different GUI object instances
  
--]]

local _log = require "logger" (_M)

local love = _G.love
local lm = love.mouse
local lg = love.graphics
local lt = love.timer

local suit  = require "suit"

local GUIs  = {}
local MODES = {"main", "test", "settings"}

for _, mode in ipairs(MODES) do
  GUIs[mode] = require ("guillaume.%sGUI" % mode) 
end

local GUI = GUIs.main


--
-- fix the checkbox appearance (narrower tick mark, space before text label)
--
local theme = suit.theme
 
function theme.Checkbox(chk, opt, x,y,w,h)
	local c = theme.getColorForState(opt)
	local th = opt.font:getHeight()

	theme.drawBox(x+h/10,y+h/10,h*.8,h*.8, c, opt.cornerRadius)
	love.graphics.setColor(c.fg)
	if chk.checked then
		love.graphics.setLineStyle('smooth')
		love.graphics.setLineWidth(2)
		love.graphics.setLineJoin("bevel")
		love.graphics.line(x+h*.2,y+h*.55, x+h*.45,y+h*.75, x+h*.8,y+h*.2)
	end

	if chk.text then
		love.graphics.setFont(opt.font)
		y = y + theme.getVerticalOffsetForAlign(opt.valign, opt.font, h)
		love.graphics.printf(chk.text, x + h + 5, y, w - h, opt.align or "left")
	end
end

-----

local margin = 220      -- margin width for left- and right-hand panels
local footer = 30       -- footer height for button array

-------------

--local font11  = lg.newFont(11)
local layout  = suit.layout
--local options = {align = "left", font = XXXfont11,  color = {normal = {fg = {.9,.6,.7}}}}
--local options = {align = "left", color = {normal = {fg = {.6,.4,.5}}}}

-- meta needed because Widget options are mutable (by SUIT itself)
--local buttonMeta = { cornerRadius = 0, font = XXXfont11, bg = {normal =  {bg = {0,0,0}}} }
local buttonMeta = { cornerRadius = 0, bg = {normal =  {bg = {0,0,0}}} }
local function opt(x) return setmetatable(x or {}, {__index = buttonMeta}) end


local function build_modes()
  local w, h = lg.getDimensions()
  layout:reset(margin, h - footer)
--  Suit.ImageButton( lumIcon, {bg, align = "center", cornerRadius = 0}, layout:col())
  suit.Button( "adjustments", opt(), layout:col((w - 2*margin)/7, footer))
  suit.Button ("test",        opt(), layout:col())
  suit.Button( "-", opt(), layout:col())
  suit.Button ("eyepiece",    opt(), layout:col())
  suit.Button ("snapshot",    opt(), layout:col())
  suit.Button ("settings",    opt(), layout:col())
  suit.Button ("info",        opt(), layout:col())
end


-------------
--
-- UPDATE
--

function _M.update(dt) 
  
  local x, y = lm.getPosition()
  local w, h = lg.getDimensions()
  
  local modes = x < w - margin and y > h - 100 
  if modes then
    build_modes()
  end
  
  if suit.isHit "eyepiece" and GUI ~= GUIs.main then 
    GUI = GUIs.main
  end
  
  if suit.isHit "test" then 
    GUI = GUIs.test
  end
  
  if suit.isHit "settings" then 
    GUI = GUIs.settings
  end
  
  if suit.isHit "snapshot" then
   lg.captureScreenshot "snapshots/snapshot.png"
   _log "snapshot"
  end

  GUI.update(dt)
end

-------------
--
-- DRAW
--

function _M.draw(screenImage) 
  local clear = 1/8
  lg.clear(clear,clear,clear,1)
  
  GUI.draw(screenImage)       -- draw the mode-specific stuff
  suit.draw()                 -- and the modes menu at the bottom
end
  

-------------------------
--
-- KEYBOARD
--

function love.keypressed(...)   GUI.keypressed(...)   end
function love.keyreleased(...)  GUI.keyreleased(...)  end
function love.textedited(...)   GUI.textedited(...)   end
function love.textinput(...)    GUI.textinput(...)    end

-------------------------
--
-- MOUSE
--

function love.mousepressed(...)   GUI.mousepressed(...)   end
function love.mousereleased(...)  GUI.mousereleased(...)  end
function love.mousemoved(...)     GUI.mousemoved(...)     end
function love.wheelmoved(...)     GUI.wheelmoved(...)     end

-----

return _M

-----
