--
-- settingsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.06.15"
  _M.DESCRIPTION = "settings GUI, session and observation info"

-- 2024.11.28  Version 0
-- 2024.12.18  add button to show FITS headers

-- 2025.02.17  add latitude and longitude, and signature, from session.controls.settings
-- 2025.03.07  remove old FITS headers.txt before writing new one
-- 2025.05.08  add default stacking mode
-- 2025.05.12  add retain controls settings option (on observation reload)
-- 2025.05.22  add reducer parameter
-- 2025.05.31  show _G.VERSION
-- 2025.06.15  tidy up formatting with pre-computed layouts


local _log = require "logger" (_M)


local suit = require "suit" .new()

local session   = require "session"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local controls = session.controls
local settings = controls.settings

local ses = controls.ses_notes
local obs = controls.obs_notes

local stack_default = {selected = 1, unpack(controls.stackOptions)}
local showSliderValues, retainControls = {}, {}
local Lalign = {align = "left"}
 
-------------------------
--
-- UTILITIES
--

local layout = suit.layout
local row, col = _M.rowcol(layout)

local function widget(info, ...)
  local sw
  if type(info) == "string" then 
    sw = suit.Label
  elseif info.selected then
    sw = suit.Dropdown
  elseif info.cursor then
    sw = suit.Input
  else
    sw = suit.Checkbox
  end
  return sw(suit, info, ...)
end

local widgets do
  widgets = function (ws)
    for i, x,y,w,h in ws.coords() do
      local item, opt = unpack(ws[i])
      if opt then
        widget(item, opt, x,y, w,h)
      else
        widget(item, x,y, w,h)
      end
    end
  end
end


-------------------------
--
-- panels
--

local coords = {}
local ditto = _G.READONLY {}

  
coords.stickies1 = layout: cols {pos = {120, 70}, padding = {20, 0}, {200, 20}, ditto, ditto}
coords.stickies2 = layout: cols {pos = {120, 95}, padding = {20, 0}, {150, 30}, {80}, {200, 20}, ditto}

local function stickies()  
 
  stack_default.selected = settings.stacking or 1
  showSliderValues.checked = settings.showSliderValues
  retainControls.checked = settings.retainControls
  
  widgets {
    coords = coords.stickies1,
    {"default stacking mode", Lalign},
    {"show slider values", Lalign},
    {"retain controls", Lalign}}
  
  widgets {
    coords = coords.stickies2,
    {stack_default},
    {''},
    {showSliderValues},
    {retainControls}}
  
  settings.stacking = stack_default.selected
  settings.showSliderValues = showSliderValues.checked or nil
  settings.retainControls = retainControls.checked or nil
end


coords.telescope1 = layout: cols {pos = {120, 135}, padding = {20, 0}, {200, 20}, ditto, ditto, ditto}
coords.telescope2 = layout: cols {pos = {120, 160}, padding = {20, 0}, {200, 30}, ditto, ditto, ditto}

local function telescope()
  
  local scope = controls.telescope
  local focal = controls.focal_len
  local reducer = controls.reducer
  local pixel = controls.pixelsize
  
  widgets {
    coords = coords.telescope1,
    {"telescope", Lalign},
    {"focal length (mm)", Lalign},
    {"reducer (x)", Lalign},
    {"pixel size (µm)", Lalign}}
   
  layout: reset(20, 160)
  if suit: Button("Clear", {id = "clearScope"}, row(80, 30)) .hit then
    scope.text = ''
    focal.text = ''
    reducer.text = ''
    pixel.text = ''
  end

  widgets {
    coords = coords.telescope2,
    {scope, {id = "scope", align = "left"}},
    {focal, {id = "focal", align = "left"}},
    {reducer, {id = "reducer", align = "left"}},
    {pixel, {id = "pixel", align = "left"}}}

end


coords.notes1 = layout: rows {pos = {120, 200}, padding = {20, 5}, {200, 20}, {860, 30}}
coords.notes2 = layout: rows {pos = {120, 265}, padding = {20, 5}, {200, 20}, {860, 30}}

local function notes()
  
  layout: reset(20, 225)  
  if suit: Button("Clear", {id = "clearObs"}, row(80, 30)) .hit then
    controls.obs_notes.text = ''
  end
  
  widgets {
    coords = coords.notes1,
    {"observing notes", Lalign},
    {obs, {id = "obs_notes", align = "left"}}}
  
  layout: reset(20, 290)  
  if suit: Button("Clear", {id = "clearSes"}, row(80, 30)) .hit then
    controls.ses_notes.text = ''
  end

  widgets {
    coords = coords.notes2, 
    {"session notes", Lalign},
    {ses, {id = "ses_notes", align = "left"}}}

end


local function buttons()
  
  layout: reset(120, 400, 20, 0)
  if suit:Button("open log file", col(200, 40)) .hit then
    local url = "file://%s/Lövell.log"
    _log "open log file"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end
  
  if suit:Button("open snapshot folder", col()) .hit then
    local url = "file://%s/snapshots"
    _log "open snapshot folder"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end  
  
  if suit:Button("open masters folder", col()) .hit then
    local url = "file://%s/masters"
    _log "open Masters folder"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end  
  
  if suit:Button("open FITS header", col()) .hit then
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
  
end


local function lat_long_api()
  layout: reset(120, 500, 20, 0)
  suit:  Label("latitude", Lalign, layout: col(120, 30))
  suit: Label("longitude", Lalign, layout: col())
  suit: Label("Astrometry key", Lalign, layout: col())
  
  layout: reset(120, 530, 20, 0)
  suit: Input(settings.latitude, layout: row(120, 30))
  suit: Input(settings.longitude, layout: col())
  suit: Input(settings.apikey, layout: col())
  
end


local function signature()
  local sig = settings.signature
  local w,h = lg.getDimensions()
  layout: reset(w - 300, h - 150)
  suit:Label("signature (for images)", {align = "left"}, row(250, 30))
  suit:Input(sig, {id = "signature", align = "left"}, row())
  layout: down()
  suit:Label("version " .. _G.VERSION, layout: row())
end

-------------------------
--
-- UPDATE / DRAW
--

function _M.update(dt)
  dt = dt
  stickies()
  telescope()
  notes()
  buttons()
  lat_long_api()
  signature()
end

function _M.draw()
  suit: draw()
end
 
-------------------------
--
-- KEYBOARD
--

function _M.keypressed(key)
  suit:keypressed(key)
end

function _M.textinput(...)      
  suit:textinput(...)
end

-----

return _M

-----
