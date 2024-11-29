--
-- Main screen.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.11.28"
  _M.DESCRIPTION = "main GÜI"

local _log = require "logger" (_M)

-- 2024.11.01  Version 0
-- 2024.11.27  added Flip LR/UD checkboxes


local suit    = require "suit"
local session = require "session"

local love = _G.love
local lm = love.mouse
local lg = love.graphics
local lk = love.keyboard
local lt = love.timer

local dsos     = session.dsos

local controls = session.controls
controls.anyChanges = function() return suit.anyActive() end    -- update the function


lg.setDefaultFilter("linear", "linear")   -- smoothstars!

local self = suit.new()     -- make a new SUIT instance for ourselves

local margin = 220      -- margin width for left- and right-hand panels
local footer = 30       -- footer height for button aarray


--local lumIcon = lg.newImage "resources/luminance.png"

local display = {
  flipLR = {checked = false, text = "flip L/R"},
  flipUD = {checked = false, text = "flip U/D"},
  }

_M.controls = controls
_M.display = display
 
local popup
local adjustments, info    -- menu flags
local showAdjustments, showInfo

-------------

--local font11  = lg.newFont(11)
local layout  = self.layout
--local options = {align = "left", font = XXXfont11,  color = {normal = {fg = {.9,.6,.7}}}}
local options = {align = "left", color = {normal = {fg = {.6,.4,.5}}}}
local Woptions = {align = "left", color = {normal = {fg = {.6,.6,.6}}}}

local function build_adjustments(controls)
  local function slider(name, ...)
    name = name:lower()
    local control = controls[name] or {value = 0.5}
    controls[name] = control
--    self: Label("%s: %.2f" % {name, control.value}, options, layout:row(...))
    self: Label(name, options, layout:row(...))
    self: Slider(control, layout:row())
  end
  
  layout:reset(10,30)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  local gamma = controls.gammaOptions[controls.gamma]
  local channel = controls.channelOptions[controls.channel]
  
  local w = margin - 20
  self:Button(channel, {id = "channel"}, layout:row(w,30))
  slider ("Background", w, 10)
  slider ("Brightness")
  
  self:Button(gamma, {id = "gamma"}, layout:row(w,30))
  slider ("Stretch", w, 10)
  slider "Gradient"
  
  self:Button("Colour", {id = "colour"}, layout:row(w,30))
  slider ("Saturation", w, 10)
  slider "Red"
  slider "Blue / Green"
  
--  self:Button("Post processing", {id = "processing"}, layout:row(w,30))
--  slider ("Noise reduction", w, 10)
--  slider "Sharpen"
   
  adjustments = true

end
 
-- meta needed because Widget options are mutable (by SUIT itself)
--local buttonMeta = { cornerRadius = 0, bg = {normal =  {bg = {0,0,0}}} }
--local function opt(x) return setmetatable(x or {}, {__index = buttonMeta}) end
local eyepiece


local search = {text = ''}
local checkbox = {check = true, text = "pin"}

local OBJ, RA, DEC = '', '', ''
local function build_info()
  
  info = true
  local stack = session.stack() or {}

  local Wcol = margin/2 - 30
  local w, h = lg.getDimensions()
  layout:reset(w - margin + 10, 30)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction

  self:Input(search, {id = "search", align = "left"}, layout:row(margin- 20, 30))
  self:Label("object", options, layout:row(margin, 10))
  self:Label(OBJ, Woptions, layout:row(margin, 15))
  
  self:Label("RA", options, layout:row(Wcol, 10))
  self:Label("DEC", options, layout:col(Wcol, 10))
  layout:left()
  self:Label(RA, Woptions, layout:row())
  self:Label(DEC, Woptions, layout:col())
  layout:left()
  
  self:Label ('', layout:row())
  
  local image = stack.image
  local temp = stack.temperature
  local camera = stack.camera or image and ("[%d x %d]" % {image: getDimensions()})  or ''
  local tcam = temp and (" @ %sC" % temp) or ''
  
  local telescope = session.settings.telescope.text
  
  self:Label("date", options, layout:row(margin, 15))
  self:Label(stack.date or '?', Woptions, layout:row(margin, 10))
  self:Label("telescope", options, layout:row(margin, 15))
  self:Label(telescope, Woptions, layout:row(margin, 10))
  self:Label("camera" .. tcam, options, layout:row(margin, 15))
  self:Label(camera or '??', Woptions, layout:row(margin, 10))
  
  self:Label ('', layout:row())
  
  self:Label("stacked ", options, layout:row(Wcol, 10))
  self:Label("exposure", options, layout:col(Wcol, 10))
  layout:left()
  self:Label(stack.Nstack or '0', Woptions, layout:row(Wcol, 15))
  self:Label(stack.exposure or '?', Woptions, layout:col(Wcol, 15))
  layout:left()
  
--  self:Label("Bayer: " .. (stack.bayer or 'none'), options, layout:row())

  
  layout:reset(w - margin + Wcol + 10, h - 150)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
   
  self:Checkbox (display.flipLR, layout:row(120, 20))
  self:Checkbox (display.flipUD, layout:row())

  
end


-------------
--
-- UPDATE
--

local SEARCH = ''

function _M.update(dt) 
  dt = dt
  local text = search.text
  if SEARCH ~= text then
    SEARCH = text
    if #text > 0 then 
      local text = text: lower()            -- case insensitive search
      for i = 1, #dsos do
        local dso = dsos[i]                 -- { Name, RA, Dec, Con, OT, Mag, Diam, Other } 
        local name = dso[1]: lower()
        if name == text then                                      -- matched from the start
          local mag = dso[6]
          mag = (mag == mag) and ("Mag " .. mag .. ' ') or ''    -- ie. not NaN
          OBJ = "%s%s in %s" % {mag, dso[5], dso[4]}
          RA, DEC = dso[2], dso[3]
          break 
        else
          OBJ, RA, DEC = '', '', ''
        end
      end
    end
  end
  
  local w, h = lg.getDimensions()
  
  local x, y = lm.getPosition()
  adjustments = x < margin
  if adjustments or showAdjustments then
    build_adjustments(controls)
  end
  
  info = x > w - margin and y < h - 100
  if info or showInfo then
    build_info()
  end
 
  if self:isHit "gamma" then
    controls.gamma = (controls.gamma) % #controls.gammaOptions + 1
  end
 
  if self:isHit "channel" then
    controls.channel = (controls.channel) % #controls.channelOptions + 1
  end

  if suit.isHit "eyepiece" then
    eyepiece = not eyepiece
    showAdjustments = eyepiece
    showInfo = eyepiece
  end

  if suit.isHit "adjustments" then
    showAdjustments = not showAdjustments
  end

  if suit.isHit "info" then
    showInfo = not showInfo
  end

end


-------------
--
-- my camera
--

local my_camera = {
    x = 0, y = 0,
    scale = 1,
    rot = 0,
  }

function my_camera: zoomTo(zoom, yoom)
  self.scalex = zoom
  self.scaley = yoom or zoom
end

function my_camera:lookAt(x,y)
	self.x, self.y = x, y
	return self
end

function my_camera: rotateTo(phi)
	self.rot = phi
	return self
end

function my_camera:lookAt(x,y)
	self.x, self.y = x, y
	return self
end

function my_camera:attach(x,y,w,h)
	x,y = x or 0, y or 0
	w,h = w or love.graphics.getWidth(), h or love.graphics.getHeight()

	local cx,cy = x+w/2, y+h/2
	love.graphics.push()
	love.graphics.translate(cx, cy)
	love.graphics.scale(self.scalex, self.scaley)
	love.graphics.rotate(self.rot)
	love.graphics.translate(-self.x, -self.y)
end

function my_camera:detach()
	love.graphics.pop()
--	love.graphics.setScissor(self._sx,self._sy,self._sw,self._sh)
end


-------------
--
-- DRAW
--
local final 

function _M.draw()
  local screenImage = session.image()
  local clear = 0.12
  lg.clear(clear,clear,clear,1)
  
  local w, h = lg.getDimensions()             -- screen size
  
  if screenImage then

    -- final image polishing
--    final = buffer(screenImage, final, {mipmaps = "auto"})
--    final: renderTo(lg.draw, screenImage)
    final = screenImage
    
    local iw, ih = final:getDimensions()  -- image size
    local scale = controls.zoom
    local x, y = controls.x, controls.y
    local angle = 0
 
--
-- NAIVE
--
--    local sx = display.flipLR.checked and -scale or scale
--    local sy = display.flipUD and -scale or scale
    
--    lg.draw(screenImage, w/2 + x - scale*iw/2,  h/2 + y - scale*ih/2, angle, scale, scale)   -- zoom from image centre
  
  if eyepiece then
--    local t = love.timer.get Time()
    local function Oculus()
      local c = 0.09            -- background within the oculus
       lg.setColor(c,c,c,1)
       lg.setColorMask(true, true, true, true)
       lg.circle("fill", w/2, h/2, math.min(w,h) / 2 - footer - 10)
       lg.setColor(1,1,1,1)
    end
    lg.stencil(Oculus, "replace", 1)
    lg.setStencilTest("greater", 0)
  end


--
-- CAMERA
----
    local flipx = display.flipLR.checked and -1 or 1
    local flipy = display.flipUD.checked and -1 or 1
    
    local sx, sy = scale*flipx, scale*flipy
    my_camera: zoomTo(sx, sy)
    my_camera: lookAt(iw/2 - x/sx, ih/2 - y/sy)
    
    my_camera: attach()
    lg.draw(final)
--     _log ("stack mipmaps: %d" % screenImage: getMipmapCount())

    my_camera: detach()
  
  end

  lg.setStencilTest()  
  
  lg.print("fps: " .. lt.getFPS( ), 10, 10)
  
  local r,g,b,a = lg.getColor()
  local c = 1/8
  lg.setColor(c,c,c,0.5)

  if adjustments or eyepiece then 
    lg.rectangle("fill", 0,0, margin, h)
  end  
  
  if info or eyepiece then
    lg.rectangle("fill", w - margin, 0, margin, h)
    lg.setColor(0.6,0.6,0.6,1)
    lg.getFont(): setLineHeight(1.2)
    lg.printf(session.settings.ses_notes.text, w - margin + 10, h/2, margin - 40)
  end
  
  lg.setColor(r,g,b,a)
  self:draw()

  lg.setColor(1,1,1,1)
end
  
  
-------------------------
--
-- KEYBOARD
--

local function reset_origin()
  controls.x, controls.y = 0, 0 
end

do
  lk.setKeyRepeat(true)

  local keypressed =  {
    home      = function() reset_origin(); controls.zoom = 0.3 end,
  --  up        = function() y = y - inc end,
  --  down      = function() y = y + inc end,
  --  left      = function() x = x - inc end,
  --  right     = function() x = x + inc end,
    
    ["kp="]     = function() 
                  local h = lg.getHeight()
                  if not final then return end
                  local ih = final:getHeight()
                  reset_origin()
                  controls.zoom = h / ih
                end,
    ["kp/"]     = function() 
                  local w,h = lg.getDimensions()
                  if not final then return end
                  local iw,ih = final:getDimensions()
                  reset_origin()
                  controls.zoom = math.max(h / ih, w / iw)
                end,
    ["kp*"]     = function() 
                  reset_origin()
                  controls.zoom = 1 
                end,
    pageup    = function() controls.zoom = controls.zoom * 1.1 end,
    pagedown  = function() controls.zoom = controls.zoom / 1.1 end,
    noop      = function() end,

    kp8       = function() controls.stretch.value = controls.stretch.value + 0.05 end,
    kp6       = function() controls.background.value = controls.background.value - 0.002 end,
    kp5       = function() controls.stretch.value = 0.3; controls.background.value = 0 end,
    kp4       = function() controls.background.value = controls.background.value + 0.002 end,
    kp2       = function() controls.stretch.value = controls.stretch.value - 0.05 end,

  }

  function _M.keypressed(key)
    self:keypressed(key)
    local action = keypressed[key]
    if not action then
      action = keypressed.noop
--      print("unimplemented key", key)
    end
    action()
  end
end  

function _M.textinput(...)      
  self:textinput(...)
end

-------------------------
--
-- Mouse
--

local function within(mx, my)
  local w, h = lg.getDimensions()
  local radius2 = (math.min(w,h) / 2 - footer - 10)^2
  local dist2  = (mx - w/2)^2 + (my - h/2)^2
  return dist2 < radius2
end

do  

  local Mx,My = 0,0
  local mousedown

  function _M.mousepressed(mx, my, btn)
    mx, my = mx, my
    mousedown = btn == 1 and within(mx, my)
    popup = popup or btn == 2
  end

  function _M.mousereleased(mx, my, btn)
    btn = btn
    mx, my = mx, my
    mousedown = false
  end

  function _M.mousemoved(mx, my, dx, dy)
    Mx, My = mx, my
    dx, dy = dx, dy
    if mousedown then
      controls.x = controls.x + dx
      controls.y = controls.y + dy
    end
  end

  function _M.wheelmoved(wx, wy)
    wx, wy = wx, wy
    local mag = 1 + wy / 50
    controls.zoom = controls.zoom * mag
  end

end
 
-----

return _M

-----
