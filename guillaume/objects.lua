--
-- objects.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.17",
    AUTHOR = "AK Booer",
    DESCRIPTION = "GUI objects",
  }

-- Generic GUI model

-- 2024.11.23  Version 0
-- 2024.12.29  move Oculus here from utils
-- 2024.12.30  add within() and without(), use SUIT color theme for rotator control

-- 2025.01.06  move rotator to SUIT-able module
-- 2025.01.17  add GUI object class methods: get() / set()


local love = _G.love
local lg = love.graphics
local lm = love.mouse

local function noop () end

local mode, submode

function _M.set(m, s) mode, submode = m, s end
function _M.get() return mode, submode end


function _M.GUIobject ()

--  Different GUI modes may overload any or all of the following callback functions
  
  return {
  
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


return _M

-----
