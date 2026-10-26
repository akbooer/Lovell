--
-- infopanel.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.12",
    AUTHOR = "AK Booer",
    DESCRIPTION = "info panel for main display",
  }

-- 2024.12.19  Version 0, extracted from mainGUI

-- 2025.02.24  move formatting functions to utils module
-- 2025.05.23  added reducer to focal length calculation
-- 2025.05.28  add indication of calibration: dark / flat

-- 2026.05.19  minor tidy, controls have own module
-- 2026.06.11  use new stack object directly
-- 2026.10.12  use controls.pixel_size()
-- 2026.10.26  use controls.info for essential information


require "logger" (_M)


local controls    = require "controls"
local dsos        = require "databases.dso"
local GUIobjects  = require "guillaume.objects"
local utils       = require "utils"

local bluetext = require "suit" .theme.color.bluetext

local getDimensions = require "utils" .getDimensions

local Oculus = GUIobjects.Oculus

local love = _G.love

local pager = love.thread.getChannel "pager"   -- a way for components to change display page

local margin = 220          -- margin width for left- and right-hand panels
local Wcol = margin/2 - 30  -- column width for narrower fields

_M.width = margin

local empty = _G.READONLY {}

local formatRA          = utils.formatRA
local formatDEC         = utils.formatDEC
local formatDegrees     = utils.formatDegrees
local formatAngle       = utils.formatAngle
--local formatArcMinutes  = utils.formatArcMinutes


local Ioptions = {id = "search", align = "left"}                          -- input fields
local Loptions = {align = "left",  color = bluetext}      -- fixed labels
local Woptions = {align = "left"}                                         -- white text                        
local Toptions = {align = "left", valign = "top"}                         -- top
local Moptions = {align = "left", valign = "middle", color = bluetext}

-------------------------
--
-- UPDATE annotation panel
--

function _M.update(suit, image)
  local eyepiece = controls.eyepiece.checked
  local pin_info = controls.pin_info
  local layout = suit.layout
  local row, col = GUIobjects.rowcol(layout)
--  local stack = stacking.get () or empty
  local info = controls.info or empty
  
  -- search DSO database for object name, if necessary
  local obj = controls.object
  obj.previous = obj.previous or ''
  if obj.previous ~= obj.text then
    obj.previous = obj.text
    obj.OBJ, obj.RA, obj.DEC, obj.DIA = dsos.search(obj.text)  
  end

  local w, h = getDimensions(image)
  layout:reset(w - margin + 10, 10)    -- position the layout origin...
  layout:padding(10,10)                 -- ...and put extra pixels between cells in each direction

  layout: push (w - 30, 10)
  suit:Checkbox(pin_info, {id = "pin_info"}, row(20, 20))
  layout: pop()
  
  suit:Input(controls.object, Ioptions, row(margin - 20, 30))

  suit:Label("object", Loptions, row(margin - 60, 10))
  
--  local diam = obj.DIA and ", Ø" .. formatArcMinutes(obj.DIA) or ''
  suit:Label(obj.OBJ or '', Woptions, row(margin, 15))
  
  suit:Label("RA", Loptions, row(Wcol, 10))
  suit:Label("DEC", Loptions, col(Wcol, 10))
  layout:left()
  suit:Label(formatRA(obj.RA or ''),   Woptions, row())
  suit:Label(formatDEC(obj.DEC or ''), Woptions, col())
  layout:left()
  
  row()
  
  local caminfo
  if image then
    local w, h = image: getDimensions()
    caminfo = ("[%d x %d]  %s" % {w, h, controls.BAYER or "Mono"})
  end
  local camera = info.camera or image and caminfo  or ''
  local temp = tonumber(info.temperature)
  local tcam = temp and (" @ %dºC" % temp) or ''
  
  -- telescope and camera 
  
  local telescope = controls.telescope.text
  
  suit:Label("date", Loptions, row(margin, 15))
  suit:Label(info.date or '?', Woptions, row(margin, 10))
  
  suit:Label("telescope", Loptions, row(margin, 15))
  suit:Label(telescope,   Woptions, row(margin, 15)) 
  
  suit:Label("camera" .. tcam, Loptions, row(margin, 15))
  suit:Label(camera or '??', Woptions, row(margin, 15))

  -- FOV
  
  local angle = formatDegrees(controls.rotate.value or 0, 1)    -- 1 decimal place
  local arcsize = controls.pixel_size()
  local fov = ''
  if arcsize then
    arcsize = arcsize / controls.zoom.value                           -- screen pixel size
    local radius, w, h = Oculus.radius()
    if eyepiece then
      fov = formatAngle(arcsize * radius * 2)
    else
      fov = table.concat({formatAngle(w * arcsize), formatAngle(h * arcsize)}, " x\n")
    end
  end
  suit: Label("fov", Loptions, row(Wcol, 15))
  suit: Label("rotation", Loptions, col(Wcol, 15))
  layout: left()
  suit: Label(fov, Woptions, row(Wcol, 15))
  suit: Label(angle, Woptions, col(Wcol, 15))
  layout: left()
  
  row()  
  
--  self:Label("stacked ", Loptions, row(Wcol, 10))
  local so = controls.stackOptions
  suit:Label(so.displayname[so.selected] or '', Loptions, row(Wcol, 10))
  suit:Label("mm:ss", Loptions, col(Wcol, 10))
  layout:left()
  local stacks = "%d/%d" % {info.Nstack or 0, info.subs and #info.subs or 0}
  
  suit:Label(stacks, Woptions, row(Wcol, 15))
  local exp = info.exposure or 0
  exp = [[%d:%02d]] % {math.floor(exp / 60), exp % 60}
  suit:Label(exp, Woptions, col(Wcol, 15))
  layout:left()

  local dark, flat = info.dark_calibration and "dark ", info.flat_calibration and "flat "
  if dark or flat then
    local calib = "calibration: " .. (dark or '') .. (flat or'')
    suit: Label(calib, Loptions, row(margin - 20, 15))
  end
  
  local obs_notes = controls.obs_notes.text
  if #obs_notes > 0 then
    suit:Label("observing notes", Loptions, row(margin, 15))
    suit:Label(obs_notes, Toptions, row(margin - 20, 50))
  end
  
  local ses_notes = controls.ses_notes.text
  if #ses_notes > 0 then
    suit:Label("session notes", Loptions, row(margin, 15))
    suit:Label(ses_notes, Toptions, row(margin - 20, 50))
  end

  -- settings and time
 
  layout:reset(w - margin + 10, h - 125, 10, 10)             -- position the layout origin...
  layout: row(10, 10)
  if suit: Button("Settings", layout: row(margin - 20, 30)) .hit then
    pager: push "settings"
  end
  layout: row(20, 50)
  suit: Label(os.date "%a  %H:%M", Moptions, layout: col(80,50))
  
  -- EXIT
  
  if suit:Button ("Exit", col(80, 50)) .hit then
    love.event.push "quit"    
  end
 
end


return _M

-----


