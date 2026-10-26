--
-- snapshot.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.25",
    AUTHOR = "AK Booer",
    DESCRIPTION = "compose and save snapshots",
  }

-- 2024.12,19  Version 0

-- 2025.02.24  Format annotations for landscape and eyepiece snaps
-- 2025.03.10  add HiRes option (when in landscape and info panel not pinned)
-- 2025.03.14  add count of individual filter subs
-- 2025.04.08  correct FOV label in landscape mode
-- 2025.05.01  add stacking type label "average / sigma / min var"
-- 2025.05.23  added reducer to focal length calculation

-- 2026.06.14  remove dependency on session module
-- 2026.10.14  use controls.pixel_size(), add OPTION-click for full-size PNG
-- 2026.10.18  use controls.option to detect option key(s)
-- 2026.10.25  use controls.subs rather than access to stack


local _log = require "logger" (_M)


local controls  = require "controls"
local utils     = require "utils"

local formatRA          = utils.formatRA
local formatDEC         = utils.formatDEC
local formatAngle       = utils.formatAngle
local formatDegrees     = utils.formatDegrees
local formatArcMinutes  = utils.formatArcMinutes

local Objects = require "guillaume.objects"
local Oculus = Objects.Oculus
local moveXY = Objects.moveXY

local love = _G.love
local lg = love.graphics

local path = "snapshots/%s_%s_%x.png"   -- target, session, current epoch in hexadecimal

local eyepiece                            -- true if in eyepiece mode

local W, H = 1280, 1024                   -- set snapshot size (H x H for eyepiece mode)

-------------------------
--
-- UTILITIES
--

local Xtext do
  local Y, S = 0, 1.4
  Xtext = function (align, text, y, scale)
    W = eyepiece and H or W
    Y = y or Y + 25
    local s = scale or S
    lg.printf(text, 10, Y, math.floor(W / s) - 15, align, 0, s )
  end
end

local function Ltext(...) Xtext("left",   ...) end
local function Rtext(...) Xtext("right",  ...) end
local function Ctext(...) Xtext("center", ...) end

-------------------------
--
-- ANNOTATIONS
--

local Object, OTcon, RA, DEC, Diam
local Camera, Ctemp, Gain
local Telescope, Date
local FOV, Rotation
local Stacks, Exposure, Total, Filters
local Ses_notes, Obs_notes
local Signature

local canvas    -- the snapshot image itself

-- extract basic info from various places
local function get_annotations(image)

  local eyepiece = controls.eyepiece.checked
  local frame = controls.subs and controls.subs[1] or {}
    
  local obj = controls.object
  Object = obj.text
  OTcon = obj.OBJ or ''
  RA  = "RA:  " .. formatRA (obj.RA  or '')
  DEC = "DEC: " .. formatDEC(obj.DEC or '')
  Diam = formatArcMinutes(obj.DIA)
  Diam = Diam ~= '' and ("Ø: " .. Diam) or ''
  
  local caminfo
  if image then
    local w, h = image: getDimensions()
    caminfo = ("[%d x %d]  %s" % {w, h, controls.BAYER or "Mono"})
  end
  Camera = frame.camera or image and caminfo  or ''
  local temp = tonumber(frame.temperature)
  Ctemp = temp and (" @ %dºC" % temp) or ''
  Gain = tonumber(frame.gain) and ("gain: %d" % frame.gain) or ''
  
  Telescope = controls.telescope.text
  Date = frame.date or ''

  -- FOV
  
  FOV = ''
  Rotation = "rot: " .. formatDegrees(controls.rotate.value or 0, 1)    -- 1 decimal place
  local arcsize = controls.pixel_size()
  if arcsize then
    local radius = Oculus.radius()
    if eyepiece then
      FOV = "fov: " .. formatAngle(arcsize * radius * 2 / controls.zoom.value)
    else
      local w, h = image:getDimensions()
      FOV = "fov: " .. table.concat({formatAngle(w * arcsize), formatAngle(h * arcsize)}, " x\n") : gsub('\n', ' ')
    end
  end
  
  local RGBL = controls.RGBL 
--  local T = stack.exposure or 0
  local T = RGBL and RGBL: dot {0,0,0,0, 1,1,1,1} or 0            -- sum the exposures
--  local Nstack = RGBL and RGBL: dot {1,1,1,1, 0,0,0,0} or 1e-6
  local Nstack = controls.info.Nstack
  Exposure = T / Nstack     -- average per sub
  local so = controls.stackOptions
  local stackname = so.displayname[so.selected]   -- get stacking type
  
  Stacks = "%s: %d/%d x %ds" % {stackname, frame.Nstack or 0, frame.subs and #frame.subs or 0, Exposure}
  Total = "total exposure: %d:%02d" % {math.floor(T / 60), T % 60}
  
  Filters = controls.BAYER or RGBL and "%dR %dG %dB %dL" % RGBL or nil
  
  -- session and observation notes
  
  Obs_notes = controls.obs_notes.text or ''
  Ses_notes = controls.ses_notes.text or ''
 
  Signature = controls.settings.signature.text

end

-------------------------
--
-- PORTRAIT (Eyepiece)
--
  
local function portrait(image, W, H)
  local radius = H / 2 - 10
  local ratio = radius / Oculus.radius()    -- scale screen oculus to image
  W = H
  
  canvas = lg.newCanvas(W, H, {format = "normal", dpiscale = 1})
  
  lg.setCanvas {canvas, stencil = true}     -- can't use renderTo() because of stencil parameter
    do
      -- draw the eyepiece
      local clear = 0.09
      lg.clear(clear,clear,clear,1)
      
      local function stencil()
        local c = 0.09            -- background within the oculus
        lg.setColor(c,c,c,1)
        lg.setColorMask(true, true, true, true)
        lg.circle("fill", W/2, H/2, radius)
        lg.setColor(1,1,1,1)
      end

      lg.stencil(stencil, "replace", 1)
      lg.setStencilTest("greater", 0)
      
      -- annotate
      local top = H
      local c = 0.4
      lg.setColor(c,c,c, 1)
      lg.setLineWidth(1)
      lg.line(0, top, W, top)
      
      lg.setColor(1,1,1, 1)
      lg.draw(image, W/2, H/2, moveXY(image, nil, nil, ratio))  
      lg.setStencilTest()  
      
      lg.setLineWidth(2)
      c = 0.3
      lg.setColor(c,c,c, 1)
      lg.circle("line", W/2, H/2, H/2 - 10)
      lg.setBlendMode "alpha"
      
      c = 0.6
      lg.setColor(c,c,c, 1)
      -- Top Left
      Ltext(Object, 10, 2.5)
      Ltext(OTcon, 60)
      Ltext(RA)
      Ltext(DEC)
      Ltext(Diam)
      -- Bottom Left
      Ltext(Rotation, H - 110)
      Ltext(FOV, H - 85)
      Ltext(Telescope)
      Ltext(Camera .. Ctemp)
      -- Bottom Right
      Rtext(Gain, H - (Filters and 110 or 85))
      Rtext(Stacks)
      if Filters then Rtext(Filters) end
      Rtext(Total)
      -- Top Right
      Rtext(Date, 10, 1.4)
      Rtext(Signature, 35, 1.2)
    end  
  lg.setCanvas()
end

-------------------------
--
-- LANDSCAPE
--

local function landscape(image, W, H)
  local w,h = image:getDimensions()
  local footer = 150
  local ratio = W / w
  H = h * ratio + footer           -- now add space below for annotation
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
  
  canvas = lg.newCanvas(W, H, {format = "normal", dpiscale = 1})
    
  canvas: renderTo(function()
      local c = 0.09          -- dark grey background
      lg.clear(c,c,c, 1)
      lg.draw(image, flipx < 1 and W or 0, flipy < 0 and H - footer or 0, 0, ratio * flipx, ratio * flipy)
      -- annotate
      local top = H - footer
      c = 0.4
      lg.setColor(c,c,c, 1)
      lg.setLineWidth(1)
      lg.line(0, top, W, top)
      
      c = 0.6
      lg.setColor(c,c,c, 1)
      -- Centre
      Ctext(Object, top + 10, 2.5)
      Ctext(OTcon, top + 60)
      Ctext(RA)
      Ctext(DEC)
--      Ctext(Diam)
      -- Left
      Ltext(Date, top + 10)
      Ltext(FOV, H - 85)
      Ltext(Telescope)
      Ltext(Camera .. Ctemp)
      -- Right
      Rtext(Signature, top + 10, 1.2)
      Rtext(Gain, H - (Filters and 110 or 85))
      Rtext(Stacks)
      if Filters then Rtext(Filters) end
      Rtext(Total)
    end)
end

-------------------------
--
-- FULL RESOLUTION, no annotation
--
-- TODO: FITS output
--

local function hiRes(image, snap)
  local idata = image: newImageData() 
  idata: encode ("png", snap)
  idata: release()
end

-------------------------
--
-- SNAPSHOT
--
local click = love.audio.newSource ("resources/camera-shutter-click-01.wav", "static")

function _M.snap(image)
  if not image then return end
  
  eyepiece = controls.eyepiece.checked
  local name = controls.object.text 
--  local sess = session.ID or ''   -- TODO: get session ID from elsewhere
  local sess = ''   -- TODO: get session ID from elsewhere
  local snap = path % {name, sess, os.time()}
  
  lg.setColor(1,1,1,1)
  _log (snap)
  
  -- addio effect
  _G.SHUTTER = 1    -- start camera shutter animation
  love.audio.play(click)
  
  -- full-size PNG (no flip, no annotation)
  
  if controls.option then
    hiRes(image, snap)
    return
  end
  
  -- annotated image
  get_annotations(image)
    
  if eyepiece then
    portrait(image, W, H)
  else
    landscape(image, W, H) 
  end
  
  lg.setColor(1,1,1,1)
  local idata = canvas: newImageData()
  idata: encode ("png", snap)
  idata: release()
  canvas: release()
  
end


return _M

-----
