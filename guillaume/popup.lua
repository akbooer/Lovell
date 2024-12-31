--
-- popup.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.30",
    AUTHOR = "AK Booer",
    DESCRIPTION = "popup menus",
  }

-- 2024.12.19  Version 0, extracted from mainGUI
-- 2024.12.30  correct Z-ordering for popup items (TODO: disable menus behind)


local _log = require "logger" (_M)

local suit    = require "suit"

local self = suit.new()

local layout = self.layout

local love = _G.love
local lm = love.mouse


_M.width = 120     -- menu width
_M.height = 30     -- height of each menu item
_M.hit = nil 
_M.active = nil    -- {index = index, list = list}

function _M.draw()
  self: draw()
end

function _M.popup()
  local info = _M.active
  
  layout: push(info.x, info.y)
  layout: padding(0,0)
  
  local w, h = _M.width, _M.height
  for i, item in ipairs(info.list) do
    if suit.Button(item, {id = i, cornerRadius = 0}, layout:row(w, h)) .hit then
      _M.hit = i
      _M.active = nil   -- we're done
      break
    end
  end
  layout: pop()
end

-- new (popup, [options], x,y,w,h)
function _M.new(pop, ...)
  -- popup = {index = index, list = list, [options], x,y,w,h)
  _M.hit = nil
  local index = pop.index
  local list = pop.list
  local name = list[index]
  local q = self:Button(name, ...)

  if q.hit then                   -- click on button advances list item
    return (index % #list) + 1
  end
  
  if _M.active and _M.active.list ~= list then return end
  
  if q.hovered and lm.isDown(2) then    -- right click, so create popup
    local mx, my = lm.getPosition()
    _M.active = {index = index, list = list, x = mx - 20, y = my - 20}
  end

  local info = _M.active
  if not info then return end       -- popup not active
  
  if not suit.mouseInRect(info.x, info.y, _M.width, _M.height * #info.list) then
    _M.active = nil     -- you've wandered outside the box
    return 
  end
    
  _M.popup()  -- draw the menu

  return _M.hit
end

setmetatable(_M, {__call = function(_, ...) return _M.new(...) end})

return _M

-----

