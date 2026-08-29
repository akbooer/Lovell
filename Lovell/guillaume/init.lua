--
-- guillaume.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.14",
    DESCRIPTION = "GUI Library for Lövell App Using Minimal Effort (built on SUIT)",
  }


-- 2024.11.01  Version 0
-- 2024.11.05  use SUIT (Simple User Interface Toolkit)
-- 2024.12.18  search in guillaume folder for loadable GUI modules

-- 2025.01.05  add SUIT-able extensions
-- 2025.01.17  add GUI-wide CLOSE button
-- 2025.04.07  add app-wide ctrl-/cmd-keyboard actions to change page

-- 2026.05.19  controls now in their own module
-- 2026.06.14  add pager control to here (from session module)


local _log = require "logger" (_M)

local suit      = require "suit"
local controls  = require "controls"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem
local lk = love.keyboard

require "guillaume.suitable"    -- add our own SUIT extensions

local layout  = suit.layout

local pager = love.thread.getChannel "pager"   -- a way for components to change display page


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

local GUI = GUIs.main   -- initialise to main display

controls.page = "main"

-------------------------------
--
-- UTILITIES
--

do
  local imgData = love.image.newImageData "resources/mac-cmd.png"

  imgData: mapPixel(function (x, y, r,g,b,a)
                      return 1,1,1, a   -- for some reason, it's all in the alpha channel
                    end)

  _G.mac = lg.newImage (imgData)
  _G.macFont = lg.newImageFont(imgData, '8')
  imgData: release()
end


local function pageSet(page) 
  local m, s = page: match "(%w+)%W*(.*)"   -- page, subpage 
  controls.page = m 
  if #s > 0 and m == "database" then
    local DBnames = controls.DBnames
    local lookup = DBnames.lookup
    DBnames.selected = lookup[s] or 1
  end
end

-------------
--
-- UPDATE
--

function _M.update(dt, ...) 
  
  -- handle external (non-GUI) page change requests
  local newpage = pager: pop()
  if newpage then 
    pageSet(newpage)   -- split into page and subpage parameters
  end
    
  if controls.page ~= "main" then   -- add close button for window
    layout: reset(10,10, 10, 10)
    if suit.Button("Close", layout: row(80, 50)) .hit then
      pageSet "main"
    end
  end

  GUI = GUIs[controls.page] or GUI.main
  GUI.update(dt, ...)
end

-------------
--
-- DRAW
--

function _M.draw(image) 
  local clear = 1/8
  lg.clear(clear,clear,clear,1)
  GUI.draw(image)                 -- draw the mode-specific stuff...
  suit.draw()                     -- ...and the CLOSE button
end
  
-------------------------
--
-- KEYBOARD
--

local eyepiece = controls.eyepiece

local special = {
 ["escape"] = function() pageSet "main"; eyepiece.checked = true end, 
}


local cmd = {
  c = function() pageSet "database, calibration" end,
  d = function() pageSet "database, dso" end,
  e = function() pageSet "main";    eyepiece.checked = true end,
  f = function() pageSet "database, fits headers" end,
  l = function() pageSet "main";    eyepiece.checked = false end,
  o = function() pageSet "database, observations" end,                -- open previous observation
  p = function() pageSet "process" end,                               -- processing workflow
  s = function() pageSet "settings" end,
--  t = function() pageSet "database, telescopes" end,                -- clashes with eyepiece 'toggle'
  v = function() pageSet "stack" end,                                 -- view stack of subs
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
