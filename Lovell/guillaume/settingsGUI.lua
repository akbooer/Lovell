--
-- settingsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.03.07"
  _M.DESCRIPTION = "settings GUI, session and observation info"

-- 2024.11.28  Version 0
-- 2024.12.18  add button to show FITS headers

-- 2025.02.17  add latitude and longitude, and signature, from session.controls.settings
-- 2025.03.07  remove old FITS headers.txt before writing new one


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

local settings = controls.settings

  
-------------------------
--
-- UPDATE / DRAW
--


function _M.update(dt)
  dt = dt
  
  local w,h = lg.getDimensions()
  local layout = self.layout
  layout: reset(20, 100)
  layout: row(80,30)
  
  local scope = controls.telescope
  local focal = controls.focal_len
  local pixel = controls.pixelsize
  if self: Button("Clear", {id = "clearScope"}, layout:row()) .hit then
    scope.text = ''
    focal.text = ''
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
    
  -- telescope
  
  layout: reset(120, 100)
  
  self:Label("telescope", {align = "left"}, layout:col(150, 30))
  layout: right(60,30)
  self:Label("focal length (mm)", {align = "left"}, layout:col(120, 30))
  layout: right(60,30)
  self:Label("pixel size (µm)", {align = "left"}, layout:col(120, 30))
  
  layout: reset(120, 130)
  self:Input(scope, {id = "scope", align = "left"}, layout:col(150, 30))
  layout: right(60,30)
  self:Input(focal, {id = "focal", align = "left"}, layout:col(120, 30))
  layout: right(60,30)
  self:Input(pixel, {id = "pixel", align = "left"}, layout:col(120, 30))
  layout: reset(120, 160)

  -- obs notes
  
  self:Label("observing notes", {align = "left"}, layout:row(120, 30))
  self:Input(obs, {id = "obs_notes", align = "left"}, layout:row(w - 250))

  self:Label("session notes", {align = "left"}, layout:row())
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
  self:  Label("latitude", layout: row(120, 30))
  layout: col(40,30)
  self: Label("longitude", layout: col(120, 30))
  
  layout: pop()
--  layout: row(10, 30)
  self: Input(lat, layout: row(120, 30))
  layout: col(40, 30)
  self: Input(long, layout: col(120, 30))

  layout: reset(w - 300, h - 150)
  self:Label("signature (for images)", {align = "left"}, layout:row(250, 30))
  self:Input(sig, {id = "signature", align = "left"}, layout:row())
 
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
