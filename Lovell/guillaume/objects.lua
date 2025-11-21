--
-- objects.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.06.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "GUI objects",
  }

-- Generic GUI model

-- 2024.11.23  Version 0
-- 2024.12.29  move Oculus here from utils
-- 2024.12.30  add within() and without(), use SUIT color theme for rotator control

-- 2025.01.06  move rotator to SUIT-able module
-- 2025.01.17  add GUI object class methods: get() / set()
-- 2025.02.24  add session to access controls.(sub)page
-- 2025.03.01  add moveXY() (moved from mainGUI, and also used by snapshot)
-- 2025.06.21  add rowcol() utility


local session = require "session"

local love = _G.love
local lg = love.graphics
local lm = love.mouse

local function noop () end

local controls = session.controls

function _M.set(m, s) controls.page, controls.subpage = m, s end
function _M.get() return controls.page, controls.subpage end

function _M.rowcol(layout)
  return 
    function(...) return layout:row(...) end,
    function(...) return layout:col(...) end
end
  

function _M.GUIobject ()

--  Different GUI modes may overload any or all of the following callback functions
  
  return {
  
    rowcol = _M.rowcol,
    
    -------------------------
    --
    -- MODE
    --

    set = _M.set,
    get = _M.get,
  
    -------------------------
    --
    -- UPDATE / DRAW
    --

    update  = noop,           -- (dt)
    draw    = noop,
    
    -------------------------
    --
    -- KEYBOARD
    --

    keypressed  = noop,     -- (key)
    keyreleased = noop,     -- (key)
    textedited  = noop,
    textinput   = noop,

    -------------------------
    --
    -- MOUSE
    --

    mousepressed  = noop,   -- (mx, my, btn)
    mousereleased = noop,   -- (mx, my, btn)
    mousemoved    = noop,   -- (mx, my, dx, dy)
    wheelmoved    = noop,   -- (wx, wy)
    
    }
 
end


-------------------------
--
--  Oculus draw the eyepiece on the screen
--

_M.Oculus = {}

local min = math.min

--[[

theme.color = {
    normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
    hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
    active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
  }
  
]]

local Oculus = _M.Oculus

function Oculus.radius()
  local margin = 30  -- default footer size
  local w, h = lg.getDimensions()             -- screen size
  return min(w, h) / 2 - margin - 10, w, h
end

-- is (x,y) inside the Oculus?
function Oculus.within(x, y)
  if not x then
    x, y = lm.getPosition()
  end
  local radius, w, h = Oculus.radius()
  local dist2  = (x - w/2)^2 + (y - h/2)^2
  return dist2 < radius * radius
end

function Oculus.stencil()
  local c = 0.09            -- background within the oculus
  lg.setColor(c,c,c,1)
  lg.setColorMask(true, true, true, true)
  local radius, w, h = Oculus.radius()
  lg.circle("fill", w/2, h/2, radius)
  lg.setColor(1,1,1,1)
end

function Oculus.draw()
  lg.stencil(Oculus.stencil, "replace", 1)
  lg.setStencilTest("greater", 0)
end

-------------------------
--
-- transform image offset by screen coordinate increment
-- used by mainGUI and snapshotter
--

function _M.moveXY(image, dx, dy, ratio)
  ratio = ratio or 1                          -- screen scaling for snapshot to correct for screen size
  local x, y = controls.X, controls.Y
  local w, h = image:getDimensions()          -- image size
  local scale = controls.zoom.value
  local angle = tonumber(controls.rotate.value) or 0
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
  
  if dx then
    dx, dy = dx / scale, dy / scale
    local s, c = math.sin(-angle), math.cos(-angle)
    dx, dy = dx * c - dy * s, dx * s + dy * c
    x, y = x - dx * flipx, y - dy * flipy
    controls.X, controls.Y = x, y
  end
  
  local sx = scale * flipx * ratio
  local sy = scale * flipy * ratio
  
  return angle, sx, sy, w/2 + x, h/2 + y      -- all the parameters needed by lg.draw()
end

return _M

-----
