--
-- Main screen.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.12.31"
  _M.DESCRIPTION = "main GÜI"

local _log = require "logger" (_M)

-- 2024.11.01  Version 0
-- 2024.11.27  added Flip LR/UD checkboxes
-- 2024.12.02  startup in eyepiece mode
-- 2024.12.14  add popup menus for controls


local suit      = require "suit"
local session   = require "session"
local snapshot  = require "snapshot"
local utils     = require "utils"

local Popup     = require "guillaume.popup"
local panels    = require "guillaume.panels"
local Oculus    = require "guillaume.objects" .Oculus

local love = _G.love
local lg = love.graphics
local lk = love.keyboard

local controls  = session.controls



--lg.setDefaultFilter("nearest", "nearest")   -- smoothstars! ... but blocky if enlarged too much
--lg.setDefaultFilter("linear", "nearest")   -- smoothstars!
--lg.setDefaultFilter("nearest", "linear")   -- smoothstars!
lg.setDefaultFilter("linear", "linear")   -- smoothstars!

local self = suit.new()     -- make a new SUIT instance for ourselves

local margin = 220          -- margin width for left- and right-hand panels
local footer = 30           -- footer height for button aarray

local pin_controls = controls.pin_controls
local pin_info = controls.pin_info

_M.controls = controls

local adjustments, info   -- show side panels
local DRAGGING            -- drag the image
local ROTATING            -- rotate the image

-- replace dummy function set in session
function controls.anyChanges()
  return suit.anyActive() and not (Popup.active or DRAGGING)
end 

local layout  = self.layout
 
local Loptions = {align = "left",  color = {normal = {fg = {.6,.4,.5}}}}
local Roptions = {align = "right", color = {normal = {fg = {.6,.4,.5}}}}

-------------

local function build_adjustments(controls)
  local function slider(name, ...)
    name = name:lower()
    local control = controls[name] or {value = 0.5}
    controls[name] = control
    self: Label(name, Loptions, layout:row(...))
    self: Slider(control, layout:row())
  end
  
  layout:reset(10,10)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  self:Checkbox(pin_controls, {id = "pin_controls"}, layout:row(20, 20))
  
  local w = margin - 20
  local h = lg.getHeight()
  
  local newChan = Popup({index = controls.channel, list = controls.channelOptions}, layout:row(w,30))
  controls.channel = newChan or controls.channel
  slider ("Background", w, 10)
  slider ("Brightness")
  
  local newG = Popup({index = controls.gamma, list = controls.gammaOptions}, layout:row(w,30))
  controls.gamma = newG or controls.gamma
  slider ("Stretch", w, 10)
  slider "Gradient"
  
  local newC = Popup({index = controls.colour, list = controls.colourOptions}, layout:row(w,30))
  controls.colour = newC or controls.colour 
  slider ("Saturation", w, 10)
  slider "Tint"
  
  local newE = Popup({index = controls.enhance, list = controls.enhanceOptions}, layout:row(w,30))
--  controls.enhance = newE or controls.enhance
  slider ("Denoise", w, 10)
  slider "Sharpen"

  -- orientation and snapshot
  
  layout:reset(10, h - 200)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  
  if self:Button ("snapshot", layout:col(80, 50)) .hit then
    snapshot.snap(panels)
  end
  
  self:Checkbox (controls.flipUD, layout:col(120, 20))
  self:Checkbox (controls.flipLR, layout:row())

end


-------------
--
-- UPDATE
--

function _M.update(dt) 
  dt = dt
  
  local w, h = lg.getDimensions()
  local eyepiece = controls.eyepiece.checked
  
  adjustments = suit.mouseInRect(1,1, margin + 30, h - footer) or eyepiece or pin_controls.checked
  if adjustments  then
    build_adjustments(controls)
  end
  
  info = suit.mouseInRect(w - margin - 30, 1, margin + 28, h - footer) or eyepiece or pin_info.checked
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

  if eyepiece then Oculus.draw(controls, ROTATING) end
  
  if screenImage then

    final = screenImage
    
    local iw, ih = final:getDimensions()  -- image size
    local scale = controls.zoom.value
    local x, y = controls.X, controls.Y
    local sx = scale * flipx
    local sy = scale * flipy
    local angle = controls.rotate.value
    
--    local dx, dy = iw/2 - x/sx , ih/2 - y/sy
--    lg.draw(screenImage, w/2,  h/2, angle, sx, sy, dx, dy)   
    
    local dx, dy = iw/2 , ih/2
    lg.draw(screenImage, w/2 + x,  h/2 + y, angle, sx, sy, dx, dy)   
  
  end

  lg.setStencilTest()  
  
  local r,g,b,a = lg.getColor()
  local c = 1/8
  lg.setColor(c,c,c,0.5)

  if adjustments or eyepiece then 
    lg.rectangle("fill", 0,0, margin, h)
  end  
  
  if info or eyepiece then
    lg.rectangle("fill", w - margin, 0, margin, h)
    layout:reset(w - 100, h - footer)             -- position the layout origin...
    self: Label(os.date "%H:%M", Roptions, layout: row(80,20))
  end
  
  lg.setColor(r,g,b,a)
  self:draw()
  lg.setColor(1,1,1,1)

  Popup.draw()    -- ensure this is on top of other widgets (TODO: disable them!)
end
  
  
-------------------------
--
-- KEYBOARD
--

local function reset_origin()
  controls.X, controls.Y = 0, 0 
end

lk.setKeyRepeat(true)

local keypressed =  {
  -- fill the whole screen, clipping image
  home      = function() 
                reset_origin()
                controls.zoom.value = math.max(utils.calcScreenRatios(final)) 
                controls.rotate.value = 0
              end,
  -- fit whole image to screen, with margin
  ["end"]   = function() 
                reset_origin()
                controls.zoom.value = math.min(utils.calcScreenRatios(final)) 
                controls.rotate.value = 0
              end,  
  
  pageup    = function() controls.zoom.value = controls.zoom.value * 1.1 end,
  pagedown  = function() controls.zoom.value = controls.zoom.value / 1.1 end,

  ["kp*"]     = function() reset_origin(); controls.zoom.value = 1 end,
  
  ["kp="]     = function() controls.rotate.value = 0 end,
    
--  up        = function() y = y - inc end,
--  down      = function() y = y + inc end,
--  left      = function() x = x - inc end,
--  right     = function() x = x + inc end,

}

function _M.keypressed(key)
  self:keypressed(key)
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
    DRAGGING, ROTATING = false, false
   else    
    DRAGGING, ROTATING = 
          not ROTATING and ((eyepiece and Oculus.within(mx, my)) or (not eyepiece and mx > margin)),
          not DRAGGING and   eyepiece and Oculus.without(mx, my)
  end
  if ROTATING then _M.mousemoved(mx, my, 0,0) end   -- immediately move to clicked angle
end

function _M.mousereleased(mx, my, btn)
  btn = btn
  mx, my = mx, my           -- not used
  DRAGGING, ROTATING = false, false
end

function _M.mousemoved(mx, my, dx, dy)
  mx, my = mx, my           -- not used
  if DRAGGING then
    controls.X = controls.X + dx
    controls.Y = controls.Y + dy
  elseif ROTATING then
    local w, h = lg.getDimensions()
    controls.rotate.value = math.atan2(mx - w/2,  h/2 - my + 0.5)
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
