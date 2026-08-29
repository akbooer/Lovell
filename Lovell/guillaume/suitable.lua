--
-- suitable.lua
--
-- note that these additions don't appear in the base suit.xxx level, but in instances like foo:xxx
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.07",
    AUTHOR = "AK Booer",
    DESCRIPTION = "SUIT-able, extensions to the SUIT library",
  }

-- 2025.01.05  Rotary widget (for Oculus)
-- 2025.01.06  Popup widget
-- 2025.01.12  Table widget
-- 2025.01.17  rename Popup to Dropdown, and add separate Popup
-- 2025.02.15  refactor Table widget to handle row and column indices
-- 2025.05.18  require Table info.cols with array of formatting information  (width, align, ...)

-- 2026.05.11  new Dropdown & Menu widgets, with user-defined controls, and remove Popup
-- 2026.05.20  add latency to Dropdown and Menu for better UX
-- 2026.05.31  rename Rotary, Dropdown, Menu, ... --> Rotatable, Controllable, Choosable, ...
-- 2026.06.15  add anyReset() to flag any control resets
-- 2026.06.18  add 'title' option for Choosable title
-- 2026.07.05  add pin to locked popup
-- 2026.07.07  add Draggable and Targetable ("drag and drop")


local _log = require "logger" (_M)

local suit    = require "suit"
local theme = suit.theme

local love = _G.love
local lg = love.graphics
local lk = love.keyboard
local lm = love.mouse
local lt = love.timer

local sin, cos = math.sin, math.cos
local max, min, floor = math.max, math.min, math.floor

local empty = _G.READONLY {}

-- add our own colour extensions
local bluetext = {normal = {fg = suit.theme.color.hovered.bg }}
local inactive = {normal = {fg = {0.5, 0.5, 0.5}}}

suit.theme.color.bluetext = bluetext    -- make accessible externally
suit.theme.color.inactive = inactive

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

------------------------------
--
-- UTILITIES
--

local function rightClick(state)
  local hit, hovered = state.hit, state.hovered
  local rclick = hovered and lm.isDown(2) or hit and (lk.isDown "lshift" or lk.isDown "rshift") 
  return rclick
end

_M.rightClick = rightClick

function _M.anyReset()
  local reset = _M.reset
  _M.reset = false
  return reset
end
  
 
-------------------------------
--
-- Rotatable - rotary control
--
-- suit: Rotatable(info, [options], x,y,w,h)
--
-- info = {value = 0}                   -- angle of control
-- options = {size = 7, ring = false}   -- size of control button, whether to draw rotary ring
--

local Rotatable do
  
  local function draw (theta, opt, x,y,w,h)
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

  Rotatable = function (core, info, ...)
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

    core:registerDraw(opt.draw or draw , theta, opt, x,y,w,h)

    local state =  {
        id = opt.id,
        hit = core:mouseReleasedOn(opt.id),
        changed = value_changed,
        hovered = core:isHovered(opt.id),
        entered = core:isHovered(opt.id) and not core:wasHovered(opt.id),
        left = not core:isHovered(opt.id) and core:wasHovered(opt.id)
      }
    
    if rightClick(state) then 
      info.value = 0
      state.changed = true
    end
    
    return state

  end
  
end


-------------------------------
--
-- SLIDEABLE - slider with labels
--

local Slideable do
  
  local en_space = lg.getFont(): getWidth 'n'
  local Loptions = {align = "left", color = bluetext}     -- fixed labels
  local Soptions = {align = "right"}                      -- dynamic labels

  local function normal(core, control, name, value, x,y, w,h)
    core: Label(name, Loptions, x,y, w,h)
    core.layout: padding (10,7)
    local state = core: Slider(control, core.layout: row(w, h))
    if state.hovered then
      core:Label(value, Soptions, x, y, w, h)
    end
    return state
  end

  local function inline(core, control, name, value, x,y, w,h)
    core.layout: padding (20,5)
    local left  = #name  * en_space + 10
    local right = #value * en_space + 10
    local state = core: Slider(control, x + left, y, w - left - right, 10)
    core: Label(name, Loptions, x,y, w,10)
    core: Label(value, Soptions, x,y, w,10)
    return state
  end


  Slideable = function (core, control, ...)
    local opt, x,y, w,h = core.getOptionsAndSize(...)
    local style = opt.style or control.style
        
    local fmt = control.format or opt.format or "%.2f"
    local value = fmt % control.value
    local name  = opt.id or control.id or "???"

    local fct = style == "inline" and inline or normal
    
    local px, py = core.layout: padding()
    local state =  fct(core, control, name, value, x,y, w,h)
    core.layout: padding(px, py)
    
    if rightClick(state) then
       _M.reset = true
      control.value = control.default or control.value    -- reset to default
    end
   
    return state
   end 
    

end


-------------------------------
--
-- CHOOSABLE - Menu
--

local function reset (self) 
  self.selected = self.default or 1 
end

local Choosable do
  
  local padding = {5, 3}
  local background =  theme.color.normal.bg
  local unchoosable = {color = inactive}
 
 -- note that this draw() function has different parameters from the internal SUIT draw() functions
 -- to match the external format used in SUITABLE widgets such as Controllable()
  local function draw (self, core, opt) --, x,y, w,h)
    local w, h
    local layout = core.layout
    if opt.size then w, h = unpack(opt.size) else w, h = 150, 25 end    -- TODO: make height dynamic
    
    self.hit = nil
    for i, name in ipairs(self) do
      local button
      local hidden, item = name: match "(%-?)(.*)"
      hidden = (hidden == '-')
      if hidden then
        button = core: Label (item, unchoosable, layout: row(w, h))
      else
        button = core: Button (item, layout: row(w, h))
      end
      if button.hit and not hidden then
        self.selected = i
        self.hit = true
        if opt.exit then 
          self.active = nil     -- deactivate on hit
        end
      end
    end
  end

  Choosable = function (core, info, ...)
    local opt, x,y, w,h = core.getOptionsAndSize(...)
    local choice = info[info.selected or 1]
    local id = opt.id or info.id
    id = opt.title or ((id or "???: ")  .. (choice or ''))
    local align = opt.align
    
    local newopt = {
        id = id, 
        draw = draw,                          -- generic menu drawing function
        padding = padding,                    -- gaps around menu items
        align = align,
        background = opt.background or info.background or background,
        size = opt.size or info.size,         -- width & height of menu items
        click = opt.click or info.click,                    -- hit, not just hover, to activate
        exit = opt.exit or info.exit,         -- exit on menu selection
        latency = opt.latency or info.latency,
        indent = opt.indent or info.indent,
        reset = reset,
      }
    
    local popup = core: Controllable(info, newopt, x,y,w,h)
    popup.hit = info.hit 
    info.hit = nil
    return popup
  end
  
end


-------------------------------
--
-- CONTROLLABLE - user-defined controls
--

local Controllable do
  local hi, lo = 0.35, 0.18
  local border  = {hi, hi, hi}
  local default = {lo, lo, lo}
  local color = {bg = default}   -- background colour rather than theme.color.normal
  local selected = {normal = theme.color.hovered}
  
  local function draw(core, info, opt, x,y,w,h)
    local radius = opt.cornerRadius or info.cornerRadius or theme.cornerRadius
    color.bg = opt.background or info.color or default
    core.theme.drawBox(x,y+1, w,h, opt.color or info.color or color, radius)
    lg.setColor(border)
    lg.rectangle('line', x,y+1, w,h, radius)
  end
  
  local function drawButton(text, opt, x,y,w,h)
    if opt.shortcut or true then 
      local r,g,b,a = lg.getColor()
      lg.setColor(.5, .5, .5, 1)
      lg.draw(_G.mac, x + w - 30, y + 5) -- x, y)
      lg.setColor(r,g,b,a)
    end
    suit.theme.Button(text, opt, x,y,w,h)
  end
  
  
  Controllable = function (core, info, ...)
    local opt, x,y, w,h = core.getOptionsAndSize(...)
    local w0, h0 = w, h
    local id = opt.id or info.id or tostring(opt)
    if not info then error ("Missing widget in Controllable: " .. (id or '?')) end
    local layout = core.layout
    local lock   = info.lock
    local active = info.active
    local drawer = info.shortcut and drawButton or nil
    local colour = lock and selected or nil
    local button = core: Button(id, {draw = drawer, color = colour}, x,y, w,h)
    
    local latency = opt.latency or info.latency or 0.4   -- hover latency in seconds
    local reset = opt.reset or info.reset
     
    if active then
      x,y, w,h = unpack(active)
    else
      local _, H = lg.getDimensions()
      x, y = x + (opt.indent or info.indent or 30) , min(max(0, y + h), H - h)   -- keep popup within screen dimensions
    end
  
    if active or info.lock then   -- draw popup
      layout: push(x, y)
      local px, py = 20, 10
      local padding = opt.padding
      if padding then px, py = unpack(padding) end
      layout: padding(px, py)
      layout: row(0, py)                -- add top and left margins
      layout: col(0, py)
      local fct = opt.draw or info.draw 
      fct (info, core, opt, x,y, w0,h0)                  -- draw the user control
      
      local xmax, ymax = layout: nextRow()    -- bottom margin
      xmax = layout: col "max"
      layout: pop()
      h = ymax - y + py  -- add bottom margin
      w = xmax - x
    end
    w = opt.width or id.width or  w
    
    local hovered = not opt.click and button.hovered   
    do -- need to hover for a while before registering a hover
      local delay = info.delay or 0
      delay = hovered and (delay + lt.getDelta()) or 0
      info.delay = delay
      hovered = delay > latency
    end

     if rightClick (button) and reset then 
       _M.reset = true
       reset(info) 
     end

    if hovered then info.active = {x,y, w,h} end
    if button.hit then info.lock = not info.lock end      
 
      -- add pin to popup (needs to survive several frames, so store in info)
      if lock then 
        info.pin = info.pin or {}
        info.pin.checked = true
        if core: Checkbox(info.pin, x+w-25, y+5, 20,20) .hit then
          info.active, info.lock = false, false
        end
      end
    
    if info.active or info.lock then 
      info.active = info.active or {x,y, w,h}
      core:registerDraw(draw, core, info, opt, x,y, w,h)
      core:registerHitbox(id, x,y, w,h)                           -- to avoid anything beneath from activating
      info.active = (core: mouseInRect(unpack(info.active)) or hovered) and info.active or nil   -- still in the box?
    end

    return button
  end

end


-------------------------------
--
-- DRAG-AND-DROP
--
-- Usage:  DaD = suit:DragAndDrop()
--
--  DaD: Targetable(..same args as Button)    -- Targets shold be defined before Draggables.
--  DaD: Draggable(...ditto)
--  DaD: draw()
--
-- option parameters in Draggable() allow onClear(name) and onDrop(name) functions for those events
--

local function DragAndDrop()
  local ui_targets = suit.new()
  local ui_draggables = suit.new()
  local ui_active = suit.new()

  local is_dragging = false
  local active_item_id = nil 
  local offset_x, offset_y = 0, 0
  local hovered_target = nil
  local active_item_submitted = false

  local registry = {}
  local system = {}

  -- TARGETABLE
  function system:Targetable(target, ...)
    local opt, x, y, w, h = suit.getOptionsAndSize(...)
    local state = ui_targets:Button(target, opt, x, y, w, h)
    if state.hovered then
      hovered_target = {id = target, x = x, y = y, w = w, h = h}
    end
    return state
  end

  -- DRAGGABLE
  function system:Draggable(item, ...)
    local opt, x, y, w, h = suit.getOptionsAndSize(...)

    -- Look up and assign internal state using the raw string ID 'item'
    local state = registry[item]
    if not state then
      state = {
        x = x,
        y = y,
        is_targeted = false
      }
      registry[item] = state 
    end

    -- Unconditionally update layout shapes every frame
    state.home_x = x
    state.home_y = y
    state.w = w
    state.h = h

    local mouse_x, mouse_y = love.mouse.getPosition()
    local button_pressed = love.mouse.isDown(1)
    local button_state
    
    if active_item_id == item then
      active_item_submitted = true

      if button_pressed then
        -- Dragging phase
        state.x = mouse_x + offset_x
        state.y = mouse_y + offset_y
        button_state = ui_active:Button(item, opt, state.x, state.y, state.w, state.h)
      else
        -- Drop phase
        if hovered_target then
          state.is_targeted = true
          if opt.onDrop then
            opt.onDrop(hovered_target)
            if opt.float then     -- leave it where you dropped it
              state.x = hovered_target.x + (hovered_target.w - state.w) / 2
              state.y = hovered_target.y + (hovered_target.h - state.h) / 2
            else
              state.x = hovered_target.x
              state.y = hovered_target.y
            end
          end
        else
          state.is_targeted = false
          if opt.onClear then opt.onClear() end
          state.x = state.home_x
          state.y = state.home_y
        end

        button_state = ui_active:Button(item, opt, state.x, state.y, state.w, state.h)
        is_dragging = false
        active_item_id = nil
      end
    else
      -- Idle phase
      if not state.is_targeted then
        state.x = x
        state.y = y
      end

      button_state = ui_draggables:Button(item, opt, state.x, state.y, state.w, state.h)
      if button_state.hovered and button_pressed and not is_dragging then
        is_dragging = true
        active_item_id = item
        active_item_submitted = true -- FIXED: Prevents draw() from wiping the click on frame 1
        offset_x = state.x - mouse_x
        offset_y = state.y - mouse_y
      end
    end
    return button_state
  end

  function system:draw()
    ui_targets:draw()
    ui_draggables:draw()
    ui_active:draw() 

    if active_item_id and not active_item_submitted then
      is_dragging = false
      active_item_id = nil
    end

    hovered_target = nil
    active_item_submitted = false
  end
 
  return system
end


-------------------------------
--
-- TABLE
--

--[[

  Table info contains:
  
    data = row-wise table of data
    scroll = {value = nnn}      -- slider widget
    
  Table opts contains: (except for cols, they are optional!)
  
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
--  local hirow, hicol = info.row, info.col
  local hirow = info.row
  
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
  
  -- insert new functionality here...
  instance.Choosable    = Choosable
  instance.Controllable = Controllable
  instance.DragAndDrop  = DragAndDrop
  instance.Rotatable    = Rotatable 
  instance.Slideable    = Slideable
  instance.Table        = Table
  
  return instance
end


return _M

-----

