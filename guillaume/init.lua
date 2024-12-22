--
-- güillaume.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.18",
    DESCRIPTION = "GÜI Library for LÖVELL App Using Minimal Effort (built on SUIT)",
  }


-- 2024.11.01
-- 2024.11.05  use SUIT (Simple User Interface Toolkit)
-- 2024.12.18  search in guillaume folder for loadable GUI modules


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local suit  = require "suit"

-------------------------------
--
-- Load all the GUI modules
-- Different display modes use different GUI object instances
--

local GUIs  = {}
local folder = "guillaume"
local dir = lf.getDirectoryItems(folder)

for _, file in ipairs(dir) do
  local gui = file: match "^(%w+)GUI%.lua"
  if gui then
    GUIs[gui] = require ("%s.%sGUI" % {folder, gui}) 
  end
end

local GUI = GUIs.main

-------------
--
-- INIT
--

local layout  = suit.layout
local margin = 220      -- margin width for left- and right-hand panels
local footer = 30       -- footer height for button array

local buttonMeta = { cornerRadius = 0, bg = {normal =  {bg = {0,0,0}}} }
local function opt(x) return setmetatable(x or {}, {__index = buttonMeta}) end

local modes = {"workflow", "settings", "landscape", "eyepiece", "test", "exit"}

GUIs.landscape = GUIs.main      -- set up aliases
GUIs.eyepiece  = GUIs.main 

GUIs.exit = {
    update = function() love.event.push "quit" end,
    draw = function() end,
  }

local function build_modes()
  local w, h = lg.getDimensions()
  layout:reset(margin, h - footer)
  
  for _, mode in ipairs(modes) do
    if suit.Button(mode,    opt(), layout:col((w - 2*margin)/#modes, footer)) .hit then
      GUI = GUIs[mode]
    end
  end
end

-------------
--
-- UPDATE
--

function _M.update(dt) 
  local w, h = lg.getDimensions()
  
  local modes = suit.mouseInRect(margin, h - 1.5 * footer, w - 2 * margin, 1.5 * footer - 2)
  if modes then
    build_modes()
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
  GUI.draw(screenImage)           -- draw the mode-specific stuff
  suit.draw()                     -- and the modes menu at the bottom
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
