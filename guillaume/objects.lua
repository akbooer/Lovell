--
-- objects.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.30",
    AUTHOR = "AK Booer",
    DESCRIPTION = "GUI objects",
  }

-- Generic GUI model

-- 2024.11.23  Version 0
-- 2024.12.29  move Oculus here from utils
-- 2024.12.30  add within() and without(), use SUIT color theme for rotator control


local suit = require "suit"     -- for theme colour palette only

local love = _G.love
local lg = love.graphics
local lm = love.mouse

--[[

  Different GUI modes may overload any or all of the following callback functions
  
--]]

local function noop () end

function _M.GUIobject ()
  
  return {
  
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

local sin, cos, min = math.sin, math.cos, math.min

--[[

theme.color = {
    normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
    hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
    active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
  }
  
]]

local color = suit.theme.color
local normal = color.normal.bg 
local hover  = color.hovered.bg 
local active = color.active.bg 

local hovered = 0
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

-- is (x,y) outside the Oculus (but close to its edge) ?
function Oculus.without(x, y)
  if not x then
    x, y = lm.getPosition()
  end
  local radius, w, h = Oculus.radius()
  local dist2  = (x - w/2)^2 + (y - h/2)^2
  return dist2 > radius * radius and dist2 < (radius + 20) ^2
end

function Oculus.stencil()
  local c = 0.09            -- background within the oculus
  lg.setColor(c,c,c,1)
  lg.setColorMask(true, true, true, true)
  local radius, w, h = Oculus.radius()
  lg.circle("fill", w/2, h/2, radius)
  lg.setColor(1,1,1,1)
end

function Oculus.draw(controls, rotating)
  hovered = Oculus.without() and (hovered + 0.02) or 0    -- add delay before highlighting rotator
  local radius, w, h = Oculus.radius()
  local r = radius + 10
  local theta = controls.rotate.value
  local s, c = sin(theta), cos(theta)
  local v = rotating and active or hovered > 1 and hover or normal
-- illuminate ring
--  if v ~= normal then
--    lg.setColor(hover)
--    lg.setLineWidth(1)
--    lg.circle("line", w/2, h/2, r)
--  end
  lg.setColor(v)
  local x, y = w/2 + r * s, h/2 - r * c
  lg.circle("fill", x, y, 7)
  lg.stencil(Oculus.stencil, "replace", 1)
  lg.setStencilTest("greater", 0)
end


return _M

-----
