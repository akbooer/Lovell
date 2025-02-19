--
-- Main screen.lua
--

local _M = require "guillaume.objects" .GUIobject(...)

  _M.NAME = ...
  _M.VERSION = "2025.01.17"
  _M.DESCRIPTION = "main GÜI"

local _log = require "logger" (_M)

-- 2024.11.01  Version 0
-- 2024.11.27  added Flip LR/UD checkboxes
-- 2024.12.02  startup in eyepiece mode
-- 2024.12.14  add popup menus for controls

-- 2025.01.06  use Rotary SUIT widget extension for eyepiece rotation
-- 2025.01.07  use Popup SUIT widget extension
-- 2025.01.17  rename Popup to Dropdown, and add Popup GUI selector


local suit      = require "suit"
local session   = require "session"
local snapshot  = require "snapshot"
local utils     = require "utils"

local panels    = require "guillaume.panels"
local Oculus    = require "guillaume.objects" .Oculus

local love = _G.love
local lg = love.graphics
local lk = love.keyboard
local lm = love.mouse

local controls  = session.controls



--lg.setDefaultFilter("nearest", "nearest")   -- smoothstars! ... but blocky if enlarged too much
--lg.setDefaultFilter("linear", "nearest")   -- smoothstars!
--lg.setDefaultFilter("nearest", "linear")   -- smoothstars!
lg.setDefaultFilter("linear", "linear")   -- smoothstars!

local self = suit.new()     -- make a new SUIT instance for ourselves

local margin = 220          -- margin width for left- and right-hand panels

local pin_controls = controls.pin_controls
local pin_info = controls.pin_info

_M.controls = controls

local adjustments, info   -- show side panels
local DRAGGING            -- drag the image

-- replace dummy function set in session
function controls.anyChanges()
  return suit.anyActive() and not DRAGGING
end 

local layout  = self.layout
 
local Loptions = {align = "left",  color = {normal = {fg = suit.theme.color.hovered.bg }}}   -- fixed labels

local toggle = {"Eyepiece", "Landscape"}

-------------

local function slider(name, ...)
  name = name:lower()
  local control = controls[name] or {value = 0.5}
  controls[name] = control
  self: Label(name, Loptions, layout:row(...))
  self: Slider(control, layout:row())
end


local function build_adjustments(controls)
  
  layout:reset(10,10)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  self:Checkbox(pin_controls, {id = "pin_controls"}, layout:row(20, 20))
  
  local w = margin - 20
  local h = lg.getHeight()
  
  self: Dropdown(controls.channelOptions, layout:row(w,30))
  slider ("Background", w, 10)
  slider ("Brightness")
  
  self: Dropdown(controls.gammaOptions, layout:row(w,30))
  slider ("Stretch", w, 10)
  slider "Gradient"
  
  self: Dropdown(controls.colourOptions, layout:row(w,30))
  slider ("Saturation", w, 10)
  slider "Tint"
  
  if self: Button("Processing", layout:row(w,30)) .hit then
    _M.set "workflow"
  end
  slider ("Denoise", w, 10)
  slider "Sharpen"

  -- orientation and snapshot
 
  layout: reset(10, h - 125, 10, 10)
  layout: row(10, 10)
  toggle.selected = controls.eyepiece.checked and 1 or 2
  self: Dropdown(toggle, layout: row(w, 30))
  controls.eyepiece.checked = toggle.selected == 1
 
  if self:Button ("Snapshot", layout:row(80, 50)) .hit then
    snapshot.snap(panels)
  end
  
  layout:col(5, 20)
  
  self:Checkbox (controls.flipUD, layout:col(120, 20))
  self:Checkbox (controls.flipLR, layout:row(120, 20))
 end


-------------
--
-- UPDATE
--

local popup = {"DSOs", "Observations", "Watchlist", "View stack"}

local mode = {
    {"database", "dso"}, 
    {"database", "observations"}, 
    {"database", "watchlist"},
    {"stack"},
  }

function _M.update(dt) 
  dt = dt
  
  local w, h = lg.getDimensions()
  local eyepiece = controls.eyepiece.checked

  if self: Popup(popup, margin, 0, w - margin, h) .hit then
    _M.set (unpack(mode[popup.selected] or {"database"}))
  end
  
  local rotate = controls.rotate
  if eyepiece then
    local r = Oculus.radius() + 10
    -- rotary.changed is used to stop post-stack processing when being rotated, see session.update()
    rotate.changed = self:Rotary (rotate, {ring = true}, w / 2 - r, h / 2 - r, r + r, r + r) .changed
  end

  adjustments = suit.mouseInRect(1,1, margin + 30, h - 5) or eyepiece or pin_controls.checked
  if adjustments  then
    build_adjustments(controls)
  end
  
  info = suit.mouseInRect(w - margin - 30, 1, margin + 28, h - 5) or eyepiece or pin_info.checked
  if info then
    panels.update(self)
  end

  if suit.isHit "landscape" then
    controls.eyepiece.checked = false
  elseif suit.isHit "eyepiece" then
    controls.eyepiece.checked = true
  end

end


-------------
--
-- DRAW
--
local final 

function _M.draw()
  
  local screenImage = session.image()
  local eyepiece = controls.eyepiece.checked
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
  
  local clear = 0.12
  lg.clear(clear,clear,clear,1)
  
  local w, h = lg.getDimensions()             -- screen size
  
  if eyepiece then Oculus.draw() end
  
  if screenImage then

    final = screenImage
    
    local iw, ih = final:getDimensions()  -- image size
    local scale = controls.zoom.value
    local x, y = controls.X, controls.Y
    local sx = scale * flipx
    local sy = scale * flipy
    local angle = controls.rotate.value
  
    local dx, dy = iw/2 , ih/2
    lg.setColor(1,1,1, 1)
    lg.draw(screenImage, w/2 + x,  h/2 + y, angle, sx, sy, dx, dy)   
  
  end

  lg.setStencilTest()  
  
--  local r,g,b,a = lg.getColor()
  local c = 1/8
  lg.setColor(c,c,c,0.5)

  if adjustments or eyepiece then 
    lg.rectangle("fill", 0,0, margin, h)
  end  
  
  if info or eyepiece then
    lg.rectangle("fill", w - margin, 0, margin, h)
  end
  
--  lg.setColor(r,g,b,a)
  lg.setColor(1,1,1, 1)
  self:draw()
--  lg.setColor(1,1,1,1)

end
  
  
-------------------------
--
-- KEYBOARD
--

local function reset_origin()
  controls.X, controls.Y = 0, 0 
end

local function change_mode(mode, submode)
  if lm.getPosition() < (lg.getDimensions() - margin) then 
    _M.set(mode, submode)
  end
end

lk.setKeyRepeat(true)

local function rotate_to_zero() controls.rotate.value = 0 end

local function fit_to_margins() 
  reset_origin()
  local W = lg.getDimensions()
  controls.zoom.value = 1 
  controls.rotate.value = 0
  local R = math.max(utils.calcScreenRatios(final)) 
  controls.zoom.value = R * (W - 2 * margin - 10) / W
end

local function one_to_one() 
  reset_origin()
  controls.zoom.value = 1 
end

local function rotate_clockwise() 
  local pi = math.pi
  controls.rotate.value = (controls.rotate.value + pi / 2) % (2 * pi)
end

local function rotate_anticlockwise() 
  local pi = math.pi
  controls.rotate.value = (controls.rotate.value - pi / 2) % (2 * pi)
end

  -- fill the whole screen, clipping image
local function fill_whole_screen() 
  reset_origin()
  controls.zoom.value = math.max(utils.calcScreenRatios(final)) 
  controls.rotate.value = 0
end

-- fit whole image to screen, with margin
local function fit_whole_image() 
  reset_origin()
  controls.zoom.value = math.min(utils.calcScreenRatios(final)) 
  controls.rotate.value = 0
end  

local keypressed =  {
  
  home      = fill_whole_screen,
  ["end"]   = fit_whole_image,  
  
  pageup    = function() controls.zoom.value = controls.zoom.value * 1.1 end,
  pagedown  = function() controls.zoom.value = controls.zoom.value / 1.1 end,

  ["kp="]   = one_to_one,
  ["kp+"]   = fill_whole_screen,
  ["kp-"]   = fit_to_margins,
  ["kp*"]   = rotate_to_zero,
  ["kp/"]   = rotate_clockwise,

  ["="]   = one_to_one,
  ["+"]   = fill_whole_screen,
  ["-"]   = fit_to_margins,
  ["*"]   = rotate_to_zero,
  ["/"]   = rotate_clockwise,
  ["\\"]  = rotate_anticlockwise,
  
--  up        = function() y = y - inc end,
--  down      = function() y = y + inc end,
--  left      = function() x = x - inc end,
--  right     = function() x = x + inc end,

  d = function() change_mode ("database", "dso") end,
  e = function() controls.eyepiece.checked = true  end,           -- eyepiece
  l = function() controls.eyepiece.checked = false end,           -- landscape
  o = function() change_mode ("database", "observations") end,
  p = function() change_mode "workflow" end,
  s = function() change_mode "settings" end,
  t = function() change_mode ("database", "telescopes") end,
  v = function() change_mode "stack" end,                         -- view stack
  w = function() change_mode ("database", "watchlist") end,

}

function _M.keypressed(key)
  self:keypressed(key)
  if controls.object.focus then return end   -- ignore input when over object text field
  local action = keypressed[key]
  if action then action() end
end

function _M.textinput(...)      
  self:textinput(...)
end

-------------------------
--
-- Mouse
--

function _M.mousepressed(mx, my, btn)
  local eyepiece = controls.eyepiece.checked
  if btn ~= 1 then
    DRAGGING = false
   else    
    DRAGGING = (eyepiece and Oculus.within(mx, my)) or (not eyepiece and mx > margin)
  end
end

function _M.mousereleased(mx, my, btn)
  btn = btn
  mx, my = mx, my           -- not used
  DRAGGING = false
end

function _M.mousemoved(mx, my, dx, dy)
  mx, my = mx, my           -- not used
  if DRAGGING then
    controls.X = controls.X + dx
    controls.Y = controls.Y + dy
  end
end

function _M.wheelmoved(wx, wy)
  wx = wx                   -- not used
  local mag = 1 + wy / 50
  controls.zoom.value = controls.zoom.value * mag
end
 
-----

return _M

-----
