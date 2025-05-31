--
-- settingsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.05.12"
  _M.DESCRIPTION = "settings GUI, session and observation info"

-- 2024.11.28  Version 0
-- 2024.12.18  add button to show FITS headers

-- 2025.02.17  add latitude and longitude, and signature, from session.controls.settings
-- 2025.03.07  remove old FITS headers.txt before writing new one
-- 2025.05.08  add default stacking mode
-- 2025.05.12  add retain controls settings option (on observation reload)
-- 2025.05.22  add reducer parameter
-- 2025.05.31  show _G.VERSION


local _log = require "logger" (_M)


local suit = require "suit"

local session   = require "session"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local self = suit.new()     -- make a new SUIT instance for ourselves

local controls = session.controls

local ses = controls.ses_notes
local obs = controls.obs_notes

local stack_default = {selected = 1, unpack(controls.stackOptions)}
local showSliderValues, retainControls = {}, {}
local Lalign = {align = "left"}

-------------------------
--
-- UPDATE / DRAW
--


function _M.update(dt)
  dt = dt
  
  local w,h = lg.getDimensions()
  local layout = self.layout
  layout: reset(20, 130)
  layout: row(80,30)
  
  local scope = controls.telescope
  local focal = controls.focal_len
  local reducer = controls.reducer
  local pixel = controls.pixelsize
  
  if self: Button("Clear", {id = "clearScope"}, layout:row()) .hit then
    scope.text = ''
    focal.text = ''
    reducer.text = ''
    pixel.text = ''
  end
  
  layout:row()
  if self: Button("Clear", {id = "clearObs"},   layout:row()) .hit then
    controls.obs_notes.text = ''
  end
  
  layout:row()
  if self: Button("Clear", {id = "clearSes"},   layout:row()) .hit then
    controls.ses_notes.text = ''
  end
   
   -- stacking default
   
  layout: reset(120, 70)  
  self:Label("default stacking mode", Lalign, layout:col(150, 30))
  layout: right(60,30)
  self:Label("show slider values", Lalign, layout:col(150, 30))
  layout: right(30,30)
  self:Label("retain controls", Lalign, layout:col(150, 30))
  
  layout: reset(120, 100)  
  local settings = controls.settings
  
  stack_default.selected = settings.stacking or 1
  self: Dropdown(stack_default, layout:row(150, 30))
  settings.stacking = stack_default.selected
  
  layout: col(110,10)
  showSliderValues.checked = settings.showSliderValues
  self: Checkbox(showSliderValues, layout:col(50, 20))
  settings.showSliderValues = showSliderValues.checked or nil
  
  layout: col(120,10)
  retainControls.checked = settings.retainControls
  self: Checkbox(retainControls, layout:col(50, 20))
  settings.retainControls = retainControls.checked or nil
   
  -- telescope
  
  layout: reset(120, 130)
  
  self:Label("telescope", Lalign, layout:col(150, 30))
  layout: right(60,30)
  self:Label("focal length (mm)", Lalign, layout:col(120, 30))
  layout: right(60,30)
  self:Label("reducer (x)", Lalign, layout:col(120, 30))
  layout: right(60,30)
  self:Label("pixel size (µm)", Lalign, layout:col(120, 30))
  
  layout: reset(120, 160)
  self:Input(scope, {id = "scope", align = "left"}, layout:col(150, 30))
  layout: right(60,30)
  self:Input(focal, {id = "focal", align = "left"}, layout:col(120, 30))
  layout: right(60,30)
  self:Input(reducer, {id = "reducer", align = "left"}, layout:col(120, 30))
  layout: right(60,30)
  self:Input(pixel, {id = "pixel", align = "left"}, layout:col(120, 30))

  -- obs notes
  
  layout: reset(120, 190)
  
  self:Label("observing notes", Lalign, layout:row(120, 30))
  self:Input(obs, {id = "obs_notes", align = "left"}, layout:row(w - 250))

  self:Label("session notes", Lalign, layout:row())
  self:Input(ses, {id = "ses_notes", align = "left"}, layout:row(w - 250, 30))

  
  layout:push(layout: row(0,0))
  layout:row(180, 40)
  if self:Button("open log file", layout:row()) .hit then
    local url = "file://%s/Lövell.log"
    _log "open log file"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end
  
  layout:right(40,40)
  if self:Button("open snapshot folder", layout:col(180, 40)) .hit then
    local url = "file://%s/snapshots"
    _log "open snapshot folder"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end  
  
  layout:right(40,40)
  if self:Button("open masters folder", layout:col(180, 40)) .hit then
    local url = "file://%s/masters"
    _log "open Masters folder"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end  
  
  layout:right(40,40)
  if self:Button("open FITS header", layout:col(180, 40)) .hit then
    local filename = "FITS headers.txt"
    lf.remove(filename)             -- remove the old one
    local file = lf.newFile(filename, 'w')
    local stack = session.stack()
    if stack then
      for _, header in ipairs(stack.headers) do
        file: write(header)
        file: write '\n'
      end
      file: close()
      local url = "file://%s/".. filename
      _log "open FITS header"
      love.system.openURL(url % love.filesystem.getSaveDirectory())
    end
  end
  
  -- SETTINGS
  
  local lat, long = settings.latitude, settings.longitude
  local sig = settings.signature

  layout: pop()
  layout: row(10,100)
  layout: push(layout: row(0,0))
  self:  Label("latitude", Lalign, layout: row(120, 30))
  layout: col(40,30)
  self: Label("longitude", Lalign, layout: col(120, 30))
  
  layout: pop()
--  layout: row(10, 30)
  self: Input(lat, layout: row(120, 30))
  layout: col(40, 30)
  self: Input(long, layout: col(120, 30))

  layout: reset(w - 300, h - 150)
  self:Label("signature (for images)", {align = "left"}, layout:row(250, 30))
  self:Input(sig, {id = "signature", align = "left"}, layout:row())
  layout: down()
  self:Label("version " .. _G.VERSION, layout: row())
end

function _M.draw()
  self: draw()
end
 
-------------------------
--
-- KEYBOARD
--

function _M.keypressed(key)
  self:keypressed(key)
end

function _M.textinput(...)      
  self:textinput(...)
end

-----

return _M

-----
