--
-- suitable.lua
--
-- note that these additions don't appear in the base suit.xxx level, but in instances like foo:xxx
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.18",
    AUTHOR = "AK Booer",
    DESCRIPTION = "SUIT-able, extensions to the SUIT library",
  }

-- 2025.01.05  Rotary widget (for Oculus)
-- 2025.01.06  Popup widget
-- 2025.01.12  Table widget
-- 2025.01.17  rename Popup to Dropdown, and add separate Popup
-- 2025.02.15  refactor Table widget to handle row and column indices
-- 2025.05.18  require Table info.cols with array of formatting information  (width, align, ...)


local _log = require "logger" (_M)

local suit    = require "suit"
local theme = suit.theme

local love = _G.love
local lg = love.graphics
local lm = love.mouse

local sin, cos = math.sin, math.cos
local max, min, floor = math.max, math.min, math.floor

local empty = _G.READONLY {}

--[[

theme.color = {
	normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
	hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
	active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
}

Template for SUIT extensions:

-- WIDGET VIEWS (the draw function)
  
function theme.Widget(text, opt, x,y,w,h)
  -- draw it here using love.graphics...
end
  
-- SUIT WIDGET itself

local function Widget(core, info, ...)
	local opt, x,y,w,h = core.getOptionsAndSize(...)

	opt.id = opt.id or info

	opt.state = core:registerHitbox(opt.id, x,y,w,h)

	if core:isActive(opt.id) then
		-- mouse update
		local mx,my = core:getMousePosition()

		-- keyboard update
		if core:getPressedKey() == SOME_KEY then
		end
	end

	core:registerDraw(opt.draw or core.theme.Widget, fraction, opt, x,y,w,h)

	return {
		id = opt.id,
		hit = core:mouseReleasedOn(opt.id),
		hovered = core:isHovered(opt.id),
		entered = core:isHovered(opt.id) and not core:wasHovered(opt.id),
		left = not core:isHovered(opt.id) and core:wasHovered(opt.id)
	}
end

--]]


-------------------------------
--
-- Rotary
--
-- suit: Rotary(info, [options], x,y,w,h)
--
-- info = {value = 0}                   -- angle of control
-- options = {size = 7, ring = false}   -- size of control button, whether to draw rotary ring
--
local function drawRotary(theta, opt, x,y,w,h)
  -- draw it here using love.graphics...
	local col = theme.getColorForState(opt)
  local size = opt.size or 7
  local color = col.bg
  lg.setColor(color)
  local r = h / 2
  local state = opt.state
  if state ~= "normal" or opt.ring then
    lg.setLineWidth(1)
    lg.circle("line", x + w/2, y + r, r)
  end
  local x0, y0 = x + w/2 + r * sin(theta), y + r - r * cos(theta)
  if state ~= "normal" then
    lg.setColor(col.fg)
  end
  lg.circle("fill", x0, y0, size)
  
end

local function Rotary(core, info, ...)
	local opt, x,y,w,h = core.getOptionsAndSize(...)
	opt.id = opt.id or info
  local theta = info.value or 0
  local size = opt.size or 10
  local value_changed = false
  
  local R = h / 2
  local x0, y0 = x + w / 2, y + R
  local mx, my = core:getMousePosition()
  local sine = mx - x0
  local cosine = my - y0
  local radius2 = sine * sine + cosine * cosine
  local r2, r2plus = (R - size)^2, (R + size)^2
  local hit = radius2 <= r2plus and radius2 >= r2
  
  do -- need to hover for a while before highlighting rotator 
    local delay = info.delay or 0
    delay = hit and (delay + 0.03) or 0
    info.delay = delay
    hit = delay > 1 or core:isHit(opt.id)
  end

  opt.state = core:registerMouseHit(opt.id, x,y, function() return hit end)

	if core:isActive(opt.id) then
		-- mouse update
    info.value = math.atan2(sine, -cosine)
    value_changed = true
	end

	core:registerDraw(opt.draw or drawRotary, theta, opt, x,y,w,h)

	return {
		id = opt.id,
		hit = core:mouseReleasedOn(opt.id),
		changed = value_changed,
		hovered = core:isHovered(opt.id),
		entered = core:isHovered(opt.id) and not core:wasHovered(opt.id),
		left = not core:isHovered(opt.id) and core:wasHovered(opt.id)
	}
end

-------------------------------
--
-- DRAW Modal Menu
--

local function maxWidth(info, opt)
	opt.font = opt.font or love.graphics.getFont()
  local j, max = 0, 0
  for i = 1, #info do
    local nc = #info[i]
    if nc > max then
      max = nc
      j = i
    end
  end
  return opt.font:getWidth(info[j]) + 64
end

local options = {}    -- options cache (saves creating new tables every frame)

local function drawMenu(core, info)
  local n = #info
  local x,y, w,h = unpack(info.active)
  h = h / n
  local hovered, hit = false, false
  for i = 1, n do   -- create a button for each popup item
    local hidden, item = info[i]: match "(%-?)(.*)"
    local option = options[i] or {id = i, cornerRadius = 0}
    options[i] = option
    
    local button
    if hidden == '-' then
      button = core: Label(item, option, x, y + (i - 1) * h, w, h)
    else
      button = core: Button(item, option, x, y + (i - 1) * h, w, h)
    end
    
    hovered = hovered or button.hovered
    hit = hit or button.hit
--    _log(pretty(button))
    if button.hit then
      info.selected = i
      info.active = nil   -- we're done
      break
    end
  end
  return hovered, hit
end

-------------------------------
--
-- POPUP
--

local function Popup(core, info, ...)
	local opt, x,y, w,h = core.getOptionsAndSize(...)
	opt.id = opt.id or info
  opt.itemHeight = opt.itemHeight or 30
  info.selected = info.selected or 1
  
  local entered, hovered, hit, left = false, false, false, false
  if info.active then 
    hovered, hit = drawMenu(core, info, opt)       -- draw the menu
    left = not hovered
  end
  
  if not hovered then 
    info.active = nil 
  end
    
  if lm.isDown(2) and core: mouseInRect(x,y, w,h) then   -- right click, so create popup
    entered = true
    local mx, my = core: getMousePosition()
    local W, H = lg.getDimensions()
    local w, h = maxWidth(info, opt), opt.itemHeight * #info
    local x, y = min(max(0, mx - 20), W - w), min(max(0, my - 20), H - h)   -- keep popup within screen dimensions
    info.active = {x,y, w,h}  -- position for popup menu
  end
   
  opt.state = core:registerMouseHit(opt.id, x,y, function() return hit end)
  
  if info.active then 
    info.active = core: mouseInRect(unpack(info.active)) and info.active or nil   -- still in the box?
  end

	return {
		id = opt.id,
		hit = hit,
		hovered = not not info.active,
		entered = entered,
		left = left
	}
end

-------------------------------
--
-- DROPDOWN
--
-- returns {id, hit, hovered, entered, left}

local function Dropdown(core, info, ...)
	local opt = core.getOptionsAndSize(...)
  local popup = core: Popup(info, ...)
  
  local index = info.selected or info.default or 1
  local name = info[index]
  local button = core: Button(name .. (opt.suffix or "..."), ...)
  if button .hit then
    -- click on button advances list item
    index = (index % #info) + 1
    info.selected = index
    popup.hit = true
  end
  popup.hovered = popup.hovered or button.hovered
  return popup
 end


-------------------------------
--
-- TABLE
--

--[[

  Table info contains:
  
    data = row-wise table of data
    scroll = {value = nnn}      -- slider widget
    
  Table opts contains: (axcept for cols, they are optional!)
  
    row_index  = {n,m, ...}       -- which rows to show from data
    col_index  = {n,m, ...}       -- which cols to show from data
    col_width  = {n,m, ...}       -- width in pixels of each column (default to 50)
    
    highlight  = {[n]  = true, [m]= true}   -- which rows to highlight
    
    cols = {col1_info, col2-info, ...}
    
    colN_info = {
      "Name",         -- required
                      -- the rest are optional...
      w = width,      -- column width
      format  = fmt,  -- formatting function
      align  = "...", -- horizontal alignment: left / center / right
    }

--]]

local scrollOpt = {vertical = true}

local function index(info, opt)
  local data = info.data
  local ridx = opt.row_index
  local cidx = opt.col_index
  local cols = opt.cols
  local nr = ridx and (ridx.n or #ridx) or #data                  -- number of rows
  local nc = cidx and (cidx.n or #cidx) or #(data[1] or empty)    -- number of columns
  
  ridx = ridx or empty                        -- allow indexing anyway   
  cidx = cidx or empty
  
  local highlight = opt.highlight or empty
  local H = opt.font:getHeight() * 1.5

  local function get(r, c)
    r = ridx[r] or r 
    c = cidx[c] or c 
    local value = data[r][c]
    local fmt = cols[c].format
    return fmt and fmt (value, r, c) or value or ''
  end
  
  return {
      size = function() return nr, nc end,
      row = function(r) return ridx[r] or r end,
      col = function(c) return cidx[c] or c end,
      get = get,
      width = function(c) return cols[cidx[c] or c].w or 100 end,     -- width of column c
      align = function(c) return cols[cidx[c] or c].align end,
      rows = function(h) return floor(h / H) - 1, H end,            -- number of visible rows, and row height
      high = function(r) return highlight[ridx[r] or r] end,
    }
end

local function drawTable(info, opt, idx, x,y,w,h)
  w = w
  local normal  = theme.color.normal.fg
  local active  = theme.color.active.bg
  local hovered = opt.state == "normal" and normal or theme.getColorForState(opt).bg
  local spacing = opt.spacing or 2
--  lg.rectangle("line", x,y, w,h)
  local N, H = idx.rows(h)   -- number of visible rows
  local nr, nc = idx.size()
  
  local maxscroll = max(0, nr - N)
  local start = floor(maxscroll * (1 - info.scroll.value)) + 1
  local hirow, hicol = info.row, info.col
  
  for row = start, min(nr, start + N - 1) do
    local x = x   - spacing         -- reset x coordinate
    for col = 1, nc do
      local colour = idx.high(row) and row ~= hirow and active or normal
      if row == hirow then
        colour = hovered
--        if col == hicol then colour = {1,1,1} end
      end
      lg.setColor(colour)
      local w = idx.width(col)
      lg.printf(idx.get(row, col), x, y, w - 2*spacing, idx.align(col))
      x = x + w + spacing
    end  
    y = y + H
  end
  
end

local function Table(core, info, ...)
	local opt, x,y, w,h = core.getOptionsAndSize(...)
	opt.id = opt.id or info
  
	opt.font = opt.font or love.graphics.getFont()
   
  local idx = index(info, opt)
  local nr, nc = idx.size()
  local N, H = idx.rows(h)

  if nr ~= 0 then
    local show_scroll = nr > N
    if not show_scroll then info.scroll.value = 1 end
    local maxscroll = max(0, nr - N)
    
    local function hit(u,v)
      local hit = u > 0 and u < w - 40 and v > 0 and v < N * H
      info.row = nil
      info.col = nil
      if hit then
        -- find which SCREEN row
        local start = floor(maxscroll * (1 - info.scroll.value)) + 1
        local r = floor(v / H) + start
        if r > nr then return end
        info.row = r
        -- find which column
        local j = 0
        info.col = 1
        for c = 1, nc do
          if u < j then break end
          j = j + (idx.width(c))
          info.col = c
        end
      end
      return hit
    end

    opt.state = core:registerMouseHit(opt.id, x,y, hit)
    
    -- build the scroll bar
    if info.scroll and show_scroll then
      core: Slider(info.scroll, scrollOpt, x + w - 20, y + 10, 10, h - 20)
    end
    
    core:registerDraw(opt.draw or drawTable, info, opt, idx, x,y,w - 40,h)
  end

	return {
		id = opt.id,
		hit = core:mouseReleasedOn(opt.id),
		hovered = core:isHovered(opt.id),
		entered = core:isHovered(opt.id) and not core:wasHovered(opt.id),
		left = not core:isHovered(opt.id) and core:wasHovered(opt.id)
	}
end

-------------------------------
--
-- INIT
--

local new = suit.new      -- save parent's new()

function suit.new(theme)
  local instance = new(theme)
  instance.Rotary   = Rotary       -- insert new functionality
  instance.Popup    = Popup
  instance.Dropdown = Dropdown
  instance.Table    = Table
  return instance
end


return _M

-----

