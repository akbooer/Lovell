--
-- panels.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "panels for display and snapshots",
  }

-- 2024.12.19  Version 0, extracted from mainGUI


local _log = require "logger" (_M)

local session     = require "session"
local controls    = session.controls
local databases   = require "databases"
local GUIobjects  = require "guillaume.objects"

local suit = require "suit"

local getDimensions = require "utils" .getDimensions

local Oculus = GUIobjects.Oculus

local love = _G.love
local lm = love.mouse

local margin = 220          -- margin width for left- and right-hand panels
local Wcol = margin/2 - 30  -- column width for narrower fields

_M.width = margin


local formatRA  = databases.formatRA
local formatDEC = databases.formatDEC

local colour = suit.theme.color.text

local Ioptions = {id = "search", align = "left"}                          -- input fields
local Loptions = {align = "left",  color = {normal = {fg = colour}}}      -- fixed labels
local Woptions = {align = "left"}                                         -- white text                        
local Toptions = {align = "left", valign = "top"}                         -- top
local Moptions = {align = "left", valign = "middle", color = {normal = {fg = colour}}}

-- return degrees / minutes / seconds of input angle (in arc seconds)
local function format_angle(x)
  local hhmm = os.date([[!%Hº %M']], x + 30)    -- round to nearest minute
  hhmm = hhmm: gsub("0(%d)", "%1")              -- remove leading zeros
  return hhmm
end

-- return degrees given radians
local function degrees(x)
  return "%dº" % (x * 180 / math.pi + 0.5)
end


-------------------------
--
-- UPDATE annotation panel
--

function _M.update(self, screen)
  local eyepiece = controls.eyepiece.checked
  local pin_info = controls.pin_info
  local layout = self.layout
  local stack = session.stack() or {}
  
  -- search DSO database for object name, if necessary
  local obj = controls.object
  if obj.previous ~= obj.text then
    obj.previous = obj.text
    obj.OBJ, obj.RA, obj.DEC = databases.searchDSO(obj.previous)  
  end

  local w, h = getDimensions(screen)
  layout:reset(w - margin + 10, 10)             -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction

  layout: push (w - 30, 10)
  self:Checkbox(pin_info, {id = "pin_info"}, layout:row(20, 20))
  layout: pop()
  
  self:Input(controls.object, Ioptions, layout:row(margin - 20, 30))
  self:Label("object", Loptions, layout:row(margin, 10))
  self:Label(obj.OBJ or '', Woptions, layout:row(margin, 15))
  
  self:Label("RA", Loptions, layout:row(Wcol, 10))
  self:Label("DEC", Loptions, layout:col(Wcol, 10))
  layout:left()
  self:Label(formatRA(obj.RA or ''),   Woptions, layout:row())
  self:Label(formatDEC(obj.DEC or ''), Woptions, layout:col())
  layout:left()
  
  layout:row()
  
  local image = stack.image
  local temp = stack.temperature
  local caminfo
  if image then
    local w, h = image: getDimensions()
    caminfo = ("[%d x %d]  %s" % {w, h, stack.bayer or "Mono"})
  end
  local camera = stack.camera or image and caminfo  or ''
  local tcam = temp and (" @ %sºC" % temp) or ''
  
  -- telescope and camera 
  
  local telescope = controls.telescope.text
  
  self:Label("date", Loptions, layout:row(margin, 15))
  self:Label(stack.date or '?', Woptions, layout:row(margin, 10))
  
  local scope1 = self:Label("telescope", Loptions, layout:row(margin, 15)) .hit
  local scope2 = self:Label(telescope,   Woptions, layout:row(margin, 15)) .hit 
--  if scope1 or scope2 then
--    GUIobjects.set ("database", "telescopes")
--  end
  
  self:Label("camera" .. tcam, Loptions, layout:row(margin, 15))
  self:Label(camera or '??', Woptions, layout:row(margin, 15))

  -- FOV
  
  local pixel = tonumber(controls.pixelsize.text) or 0
  local focal = tonumber(controls.focal_len.text) or 0
  local angle = degrees(controls.rotate.value or 0)
  if focal > 0 and pixel > 0 then
    local arcsize = 36 * 18 / math.pi * pixel / focal     -- camera pixel size in arc seconds (assume square)
    arcsize = arcsize / controls.zoom.value                -- screen pixel size
    local radius, w, h = Oculus.radius()
    self: Label("fov", Loptions, layout:row(Wcol, 15))
    self: Label("rotation", Loptions, layout:col(Wcol, 15))
    layout: left()
    local fov
    if eyepiece then
      fov = format_angle(arcsize * radius * 2)
    else
      fov = table.concat({format_angle(w * arcsize), format_angle(h * arcsize)}, " x\n")
    end
    self: Label(fov, Woptions, layout:row(Wcol, 15))
    self: Label(angle, Woptions, layout:col(Wcol, 15))
    layout: left()
  end
  
 layout:row()
  
  self:Label("stacked ", Loptions, layout:row(Wcol, 10))
  self:Label("mm:ss", Loptions, layout:col(Wcol, 10))
  layout:left()
  local stacks = "%d/%d" % {stack.Nstack or 0, stack.subs and #stack.subs or 0}
  self:Label(stacks, Woptions, layout:row(Wcol, 15))
  local exp = stack.exposure or 0
  exp = [[%d:%02d]] % {math.floor(exp / 60), exp % 60}
  self:Label(exp, Woptions, layout:col(Wcol, 15))
  layout:left()
  
  -- session and observation notes
  
  local obs_notes = controls.obs_notes.text
  if #obs_notes > 0 then
    self:Label("observing notes", Loptions, layout:row(margin, 15))
    self:Label(obs_notes, Toptions, layout:row(margin - 20, 50))
  end
  
  local ses_notes = controls.ses_notes.text
  if #ses_notes > 0 then
    self:Label("session notes", Loptions, layout:row(margin, 15))
    self:Label(ses_notes, Toptions, layout:row(margin - 20, 50))
  end
  
  -- settings and time
 
  layout:reset(w - margin + 10, h - 125, 10, 10)             -- position the layout origin...
  layout: row(10, 10)
  if self: Button("Settings", layout: row(margin - 20, 30)) .hit then
    GUIobjects.set "settings"
  end
  layout: row(20, 50)
  self: Label(os.date "%a  %H:%M", Moptions, layout: col(80,50))
  
  -- EXIT
  
  if self:Button ("Exit", layout:col(80, 50)) .hit then
    love.event.push "quit"    
  end
 
end


return _M

-----


