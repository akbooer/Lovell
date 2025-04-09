--
-- guillaume.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.07",
    DESCRIPTION = "GUI Library for Lövell App Using Minimal Effort (built on SUIT)",
  }


-- 2024.11.01
-- 2024.11.05  use SUIT (Simple User Interface Toolkit)
-- 2024.12.18  search in guillaume folder for loadable GUI modules

-- 2025.01.05  add SUIT-able extensions
-- 2025.01.17  add GUI-wide CLOSE button
-- 2025.04.07  add app-wide ctrl-/cmd-keyboard actions to change page


local _log = require "logger" (_M)

local suit    = require "suit"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem
local lk = love.keyboard

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

local special = {
 ["escape"] = function() GUI.set "main" end, 
}

local cmd = {
  c = function() GUI.set ("database", "calibration") end,
  d = function() GUI.set ("database", "dso") end,
  o = function() GUI.set ("database", "observations") end,                    -- open previous observation
  p = function() GUI.set "workflow" end,                                      -- processing workflow
  s = function() GUI.set "settings" end,
--  t = function() controls.eyepiece.checked = not controls.eyepiece.checked end,   -- toggle eyepiece / landscape
  v = function() GUI.set "stack" end,                                         -- view stack
}

function love.keypressed(key, ...)
  local ctrl = lk.isDown "lctrl" or lk.isDown "rctrl"
  local cmnd = lk.isDown "lgui" or lk.isDown "rgui"
  local action = (ctrl or cmnd) and cmd[key] or special[key]
  
  if action then 
    action() 
  else
    GUI.keypressed(key, ...)      -- pass keypress to GUI
  end
end



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
