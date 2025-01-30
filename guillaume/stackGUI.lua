--
-- stackGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.12.18"
  _M.DESCRIPTION = "stack GÜI, view each stack frame"

-- 2025.01.22  Version 0


local _log = require "logger" (_M)


local suit = require "suit"

local poststack   = require "poststack"
local session     = require "session"
local workflow    = require "workflow" .new(session.controls)

local love = _G.love
local lg = love.graphics
local lm = love.mouse
local lt = love.timer

local self = suit.new()     -- make a new SUIT instance for ourselves

local empty = _G.READONLY {}

local margin = 200
local controls = session.controls

--[[

theme.color = {
	normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
	hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
	active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
}

--]]

local layout = self.layout
local active = suit.theme.color.active.bg
local hovered = suit.theme.color.hovered.bg
local colour = suit.theme.color.text


local subs

local scroll = {value = 0}
local scrollOpt = {vertical = true}

local slider = {value = 0}
local sliderOpt = {}

local Loptions = {align = "left",  color = {normal = {fg = colour}}}      -- fixed labels
local Woptions = {align = "left"}


local frame = {
    image  = nil,     -- image  
    workflow = workflow,
  }

local floor = math.floor

-------------------------
--
-- INIT
--

-- mark position of alignment stars

local idata = { 
          {1,1,1,1,1},
          {1,0,0,0,1},
          {1,0,0,0,1},
          {1,0,0,0,1},
          {1,1,1,1,1},
        }

local imageData = love.image.newImageData(5,5, "rgba8")

imageData: mapPixel( 
  function(x,y, r,g,b,a)
    local i = idata[y+1][x+1]
    return i,i,i, i
  end)

local marker  = lg.newImage(imageData, {dpiscale=1, linear = true})  

local sprites = love.graphics.newSpriteBatch(marker, 1000)    -- a thousand stars?!


-------------------------
--
-- UPDATE / DRAW
--

local W, H      -- screen dimensions
local w, h      -- thumbnail dimensions
local scale
local index
local thumbnail

local lasttime = 0
local lastindex 
local showstars             -- toggle star display

local function row(...)
  return layout: row(...)
end

local function col(...)
  return layout: col(...)
end

-- control panel
local xy = "(%0.1f, %0.1f)"
local theta = "%0.3fº"

local function panel(subframe)
  layout:reset(50,150, 10,10)                 -- leaving space for CLOSE button
  local w = 120
  self: Button("Blink", row(w, 30))
  self: Button("Play", row())
  self: Label("rate", Loptions, row(w, 20))
  self: Slider(slider, row(w, 10))
  row(w, 10)
  self: Button("Stop", row(w, 30))
  row(w,50)
  if self: Button("Show stars", row(w,30)) .hit then
    showstars = not showstars
  end
  if showstars then
    local stars = #(subframe.stars or empty)
    local matched = #(subframe.matched_pairs or empty)
    self: Label("matched", Loptions, row(w / 2, 20))
    self: Label(matched, Woptions, col(w / 2 , 20))
    layout: left()
    self: Label("found", Loptions, row())
    self: Label(stars, Woptions, col())
    layout: left()
  else
    row(w, 50)
  end
  row(w, 60)
  
  self: Label("alignment", Loptions, row(w, 20))
  local align = subframe.align
  if align[3] then
    self: Label(xy % align, Woptions, row())
    self: Label(theta % align[3], Woptions, row())
  end
end

-- vertical scroll
local function scrollbar(n)
  local x = (W + w * scale) / 2 + 30                        -- location of scrollbar
  local y = (H - scale * h) / 2
  if self: Slider(scroll, scrollOpt, x, y, 15, h * scale) .hovered then
--    local _, my = lm.getPosition()
--    self: Label(my, Woptions, x + 20, my - 5, 50, 20)
  end
  index = floor((n - 0.01) * scroll.value) + 1
  self: Label(index, Woptions, x + 20, y + (1 - scroll.value) * h * scale - 15, 50, 30)
  return index
end

-- Add stars to sprite batch for drawing.
local function markstars(stars, scale)
	sprites:clear()
  for i = 1, #stars do
    local star = stars[i]
    local x, y = star[1] * scale - 3, star[2] * scale - 3
		sprites:add(x, y)
	end
end
  
-- draw the top frame
local function draw_image()
  lg.setColor(1,1,1, 1)
  local ws, hs = w * scale, h * scale
  local x, y = (W - ws) / 2, H / 2
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
--  local thumbnail = session.stack().thumbnail
  local thumbnail = workflow.output
  lg.draw(thumbnail, W / 2, H / 2, 0, scale * flipx, scale * flipy, w / 2, h / 2) 
  
  lg.setColor(unpack(active))
  y = y - scale * h / 2
  lg.rectangle("line", x, y, ws, hs)

  if showstars then
    lg.draw(sprites,  W / 2, H / 2, 0, scale * flipx, scale * flipy, w / 2, h / 2) 
  end
  
end

-- tween
local function tween()
  
end


function _M.update()
  local timenow = lt.getTime()
  if timenow > lasttime + 1 then    -- we've just arrived at this page...
    thumbnail = nil                 -- ...so wipe previous thumbnail
    lastindex = nil
  end
  lasttime = timenow
  
  local layout = self.layout
  local stack = session.stack()
  
  if not stack then subs = nil return end
  
  W,H = lg.getDimensions()
  layout: reset(margin, 100, 10,10)
  
  subs = stack.subs
  w,h = subs[1].thumb: getDimensions()  
  local ws, hs = stack.image: getDimensions()
  scale = 0.70 * H / h          -- image is X % of screen height
  local n = #subs
  index = 1
  if n > 1 then
    scrollbar(n)
  end
  
  local subframe = subs[index]
  frame.image = subframe.thumb
  panel(subframe)
  if index ~= lastindex then
    frame.gradients = stack.gradients   -- use the offset and gradients from the whole stack
    frame.bayer = stack.bayer
    thumbnail = poststack(frame)        -- run poststack processing chain
    markstars(subframe.stars, w / ws)   -- mark new star positions
  end
  lastindex = index
end


function _M.draw()
  if not subs then return end
  local colour = {unpack(hovered)}
  
--[[
  -- draw the stack of (empty) frames
  
  local top = TOP
  for i = 50, 2, -1 do
    local shrink = top / TOP
    top = top - OFF * shrink
    colour[4] = shrink ^ 2     -- choose alpha to fade into distance
    local x, y = w * shrink, h * shrink
    lg.setColor(colour)
    lg.rectangle("line", (W - x) / 2 , top, x, y)
  end
--]]

  draw_image ()
  self: draw()
  lg.setColor(1,1,1, 1)

end


-------------------------
--
-- KEYBOARD
--

local keypressed =  {
  
  ["home"]  = function() scroll.value = 1  end,
  ["end"]   = function() scroll.value = 0 end,
  
  pageup    = function() scroll.value = 1  end,
  pagedown  = function() scroll.value = 0 end,

  up        = function(x) scroll.value = math.min(1, scroll.value + 0.1 * (x or 1)) end,
  down      = function(x) scroll.value = math.max(0, scroll.value - 0.1 * (x or 1)) end,
}

function _M.keypressed(key)
  self:keypressed(key)
  local action = keypressed[key]
  if action then action() end
end

-------------------------
--
-- Mouse
--

function _M.wheelmoved(_, wy)
  if wy > 0 then 
    keypressed.down(0.3) 
  elseif wy < 0 then
    keypressed.up(0.3)
  end
end


return _M

-----
