--
-- Main screen.lua
--

local _M = require "guillaume.objects" .GUIobject(...)

  _M.NAME = ...
  _M.VERSION = "2026.05.16"
  _M.DESCRIPTION = "GUI - main page"

_log = require "logger" (_M)

-- 2024.11.01  Version 0
-- 2024.11.27  added Flip LR/UD checkboxes
-- 2024.12.02  startup in eyepiece mode
-- 2024.12.14  add popup menus for controls

-- 2025.01.06  use Rotary SUIT widget extension for eyepiece rotation
-- 2025.01.07  use Popup SUIT widget extension
-- 2025.01.17  rename Popup to Dropdown, and add Popup GUI selector
-- 2025.02.24  add double-click to invert image
-- 2025.02.28  correct zoom and rotate origin (centre of displayed image, rather than centre of frame)
-- 2025.03.31  change keyboard shortcuts (Issue #2)

-- 2026.05.16   redesign control layout using new Suitable widgets


local suit      = require "suit"
local suitable  = require "guillaume.suitable"     -- for access to reset flag
local controls  = require "controls"
local utils     = require "utils"

local Objects   = require "guillaume.objects"
local Oculus    = Objects.Oculus
local moveXY    = Objects.moveXY

local infopanel    = require "guillaume.infopanel"
local controlpanel = require "guillaume.controlpanel"

local love = _G.love
local lg = love.graphics
local lk = love.keyboard


local self = suit.new()     -- make a new SUIT instance for ourselves

local margin = 250          -- margin width for left- and right-hand panels

local pin_controls = controls.pin_controls
local pin_info = controls.pin_info

local adjustments, info   -- show side panels
local DRAGGING            -- drag the image


function controls.anyChanges()
  return (suit.anyActive() and not DRAGGING) or suitable.anyReset()
end 
 

-------------
--
-- UPDATE
--
 
local arrow = love.mouse.getSystemCursor "arrow"    -- TODO: does not seem to work...

local ALPHA = 1   -- tweened for visual feedback of snapshot

function _M.update(dt, image) 
  dt = dt
  love.mouse.setCursor(arrow)
  
  local w, h = lg.getDimensions()
  local eyepiece = controls.eyepiece.checked
  

  adjustments = suit.mouseInRect(1, 1, margin + 30, h - 5) or eyepiece or pin_controls.checked
  if adjustments  then
    controlpanel.update(self, controls, image)
  end
  
  info = suit.mouseInRect(w - margin - 30, 1, margin + 28, h - 5) or eyepiece or pin_info.checked
  if info then
    infopanel.update(self)
  end
  
  local rotate = controls.rotate
  if eyepiece then
    local r = Oculus.radius() + 10
    -- rotate.changed is used to stop post-stack processing when being rotated, see session.update()
    rotate.changed = self:Rotatable (rotate, {ring = true}, w / 2 - r, h / 2 - r, r + r, r + r) .changed
  end

  -- shutter tween (animation)
  local s = SHUTTER or 0
  if s > 0 then
    ALPHA = math.abs(2 * s  - 1)
    SHUTTER = s - 2 * dt
  else
    ALPHA = 1
    SHUTTER = 0
  end
end

-------------
--
-- DRAW
--
local final 

local gammaShader = love.graphics.newShader [[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
            vec4 linearColor = Texel(texture, texture_coords) * color;
            return vec4(pow(linearColor.rgb, vec3(1.0 / 2.2)), linearColor.a);
        }]]

function _M.draw(screenImage)
  local W, H = lg.getDimensions()             -- screen size
  local eyepiece = controls.eyepiece.checked  
  local clear = 0.12
  lg.clear(clear,clear,clear,1)
    
  if eyepiece then Oculus.draw() end
  
  if screenImage then
    final = screenImage
    lg.setColor(1,1,1, ALPHA)
    
--    lg.setShader(gammaShader)
    lg.draw(screenImage, W/2,  H/2, moveXY(final))   
--    lg.setShader()
    
    lg.setBlendMode "alpha"
  end

  lg.setStencilTest()  
  
  do  -- add background to left and right panels if needed (ie. not showing eyepiece)
    local c = 1/8
    lg.setColor(c,c,c,0.5)
    if adjustments then 
      lg.rectangle("fill", 0,0, margin, H)
    end    
    if info then
      lg.rectangle("fill", W - margin, 0, margin, H)
    end  
    lg.setColor(1,1,1, 1)
  end
  
  self:draw()

end
  
  
-------------------------
--
-- KEYBOARD
--

local function reset_origin()
  controls.X, controls.Y = 0, 0 
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

local function full_size() 
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
local function fit_to_screen() 
  reset_origin()
  controls.zoom.value = math.max(utils.calcScreenRatios(final)) 
  controls.rotate.value = 0
end

local function zoom_in()  controls.zoom.value = controls.zoom.value * 1.1 end
local function zoom_out() controls.zoom.value = controls.zoom.value / 1.1 end

-- fit whole image onto screen, probably with side margin
local function fit_to_image() 
  reset_origin()
  controls.zoom.value = math.min(utils.calcScreenRatios(final)) 
  controls.rotate.value = 0
end  

local special =  {
  
  ["home"]  = fit_to_screen,
  ["end"]   = fit_to_image,  
  
  ["pageup"]    = zoom_in,
  ["pagedown"]  = zoom_out,

  ["kp="] = full_size,
  ["kp+"] = fit_to_screen,
  ["kp-"] = fit_to_margins,
  ["kp*"] = rotate_to_zero,
  ["kp/"] = rotate_clockwise,
  
--  up        = function() y = y - inc end,
--  down      = function() y = y + inc end,
--  left      = function() x = x - inc end,
--  right     = function() x = x + inc end,
}

local cmd = {
  -- for other app-wide keys see guillaume.init
  t = function() controls.eyepiece.checked = not controls.eyepiece.checked end,   -- toggle eyepiece / landscape

  -- these next two, by analogy to Mac OS Preview commands
  ["0"]   = full_size,                -- one screen pixel = one image pixel 
  ["9"]   = fit_to_margins,           -- fit between side panels
  ["8"]   = fit_to_image,             -- fit whole image onto screen, probably with side margin
  ["7"]   = fit_to_screen,            -- fill the whole screen, probably cropping image
  
  ["="]   = zoom_in,                  -- actually '+'
  ["-"]   = zoom_out,
  
  ["."]   = rotate_to_zero,
  ["/"]   = rotate_clockwise,         -- +90º
  ["\\"]  = rotate_anticlockwise,     -- -90º

  -- note that the escape key returns from anywhere to the main page (eyepiece or landscape)
}

function _M.keypressed(key)
  
  if controls.object.focus then self: keypressed(key) return end     -- pass on to input field
  
  local ctrl = lk.isDown "lctrl" or lk.isDown "rctrl"
  local cmnd = lk.isDown "lgui" or lk.isDown "rgui"
  local action = (ctrl or cmnd) and cmd[key] or special[key]
  if action then action() end
end

function _M.textinput(...)      
  self:textinput(...)
end

-------------------------
--
-- Mouse
--
function _M.mousepressed(mx, my, btn, _, presses)
  local eyepiece = controls.eyepiece.checked
  local on_image = (eyepiece and Oculus.within(mx, my)) or (not eyepiece and mx > margin)
  DRAGGING = btn == 1 and on_image
  -- toggle normal/inverse image
  if presses == 2 and on_image then
    local opt = controls.channel        -- this is the 'channel' plugin (mandatory!)
    opt.selected, opt.revert = opt.selected == 3 and opt.revert or 3, opt.selected
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
    moveXY(final, dx, dy)
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
