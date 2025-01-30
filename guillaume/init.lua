--
-- güillaume.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.22",
    DESCRIPTION = "GÜI Library for LÖVELL App Using Minimal Effort (built on SUIT)",
  }


-- 2024.11.01
-- 2024.11.05  use SUIT (Simple User Interface Toolkit)
-- 2024.12.18  search in guillaume folder for loadable GUI modules

-- 2025.01.05  add SUIT-able extensions
-- 2025.01.17  add GUI-wide CLOSE button


local _log = require "logger" (_M)

local suit    = require "suit"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

suit.theme.color.text = suit.theme.color.hovered.bg 

require "guillaume.suitable"    -- add our own SUIT extensions

local layout  = suit.layout

-------------------------------
--
-- LOAD
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
GUI.set "main"


-------------
--
-- UPDATE
--

function _M.update(dt) 
  local mode = GUI.get()
  
  if mode ~= "main" then   -- add close button for window
    layout: reset(10,10, 10, 10)
    if suit.Button("Close", layout: row(80, 50)) .hit then
      GUI.set "main"
      mode = "main"
    end
  end

  GUI = GUIs[mode]
  GUI.update(dt)
end

-------------
--
-- DRAW
--

function _M.draw() 
  local clear = 1/8
  lg.clear(clear,clear,clear,1)
  GUI.draw()                      -- draw the mode-specific stuff
  suit.draw()                     -- and the CLOSE button
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
