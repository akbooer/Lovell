--
-- fitsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.12.05"
  _M.DESCRIPTION = "FITS GÜI"

local _log = require "logger" (_M)

-- 2024.12.05  Version 0


local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local suit = require "suit"

local self = suit.new()     -- make a new SUIT instance for ourselves
local session = require "session"
 
local scroll = {value = 1}
local options = {align = "left", color = {normal = {fg = {.6,.4,.5}}}}


local colWidth = {250, 80, 80}

local wheel
local glide = 0

local function tween(dt)
  scroll.value = math.min(1, math.max(0, scroll.value + glide / 10000))
  glide = wheel or glide
  wheel = nil
  glide = glide * 0.8
end

function _M.update(dt)
  tween(dt)
  
--    self: Label("%s: %.2f" % {name, control.value}, options, layout:row(...))
  local w, h = lg.getDimensions()
  local layout = self.layout
  layout:reset(w - 20, 50)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  self: Slider(scroll,{vertical = true}, layout:col(10,h-100))

end


function _M.draw()

--  lg.print("Hello from TEST", 100,100)
--  lg.push()
  
  lg.setColor(.9, .8, .6, 1)
  local h = 2 * lg.getFont() :getHeight()
  local H = lg.getHeight() - 80
  
--  local line = "%-30s %15s %15s %15s %15s"
--  lg.print(line % dso[1], x, 20)
  local keywords = session.stack().keywords
  
  local keys = {}
  for k,v in pairs(keywords) do
    keys[#keys+1] = {k,tostring(v)}
  end
  table.sort(keys, function(a,b) return a[1] < b[1] end)
--  _log(pretty(keys))
  local Nkeys = #keys
  for i = 1, Nkeys do
--    local Name, RA, Dec, Con, OT, Mag, Diam, Other  
    local x = 20
    local y = 30 + i * h
    local position = Nkeys*(1 - scroll.value)
    local fraction = math.floor(h * (position % 1))
    local cols = keys[math.min(Nkeys, i + math.floor(position))]
    for j = 1,#cols do
      local col = cols[j]
      lg.print(col, x + scroll.value % 100, y)
--      lg.print(col, x + scroll.value % 100, y - fraction)
      x = x + (colWidth[j] or 50)
    end
    if y > H then break end
  end
  
--  lg.pop()
  self: draw()
  lg.setColor(1,1,1,1)
end

function _M.wheelmoved(wx, wy)
  wheel = wy
end


return _M

-----
