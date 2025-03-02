--
-- snapshot.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "compose and save snapshots",
  }

-- 2024.12,19  Version 0

-- 2025.02.24  Format annotations for landscape and eyepiece snaps


local _log = require "logger" (_M)


local session   = require "session"
local utils     = require "utils"

local formatRA  = utils.formatRA
local formatDEC = utils.formatDEC
local formatDegrees = utils.formatDegrees
local formatAngle = utils.formatAngle
local formatArcMinutes = utils.formatArcMinutes

local Objects = require "guillaume.objects"
local Oculus = Objects.Oculus
local moveXY = Objects.moveXY

local controls = session.controls

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
local Camera, Ctemp
local Telescope, Date
local FOV, Rotation
local Stacks, Exposure, Total
local Ses_notes, Obs_notes
local Signature

local canvas    -- the snapshot image itself
local image     -- the image to draw

-- extract basic info from various places
local function get_annotations()

  local eyepiece = controls.eyepiece.checked
  local stack = session.stack() or {}
    
  local obj = controls.object
  Object = obj.text
  OTcon = obj.OBJ or ''
  RA  = "RA:  " .. formatRA (obj.RA  or '')
  DEC = "DEC: " .. formatDEC(obj.DEC or '')
  Diam = formatArcMinutes(obj.DIA)
  Diam = Diam ~= '' and ("Ø: " .. Diam) or ''
  
  local image = stack.image
  local temp = stack.temperature
  local caminfo
  if image then
    local w, h = image: getDimensions()
    caminfo = ("[%d x %d]  %s" % {w, h, stack.bayer or "Mono"})
  end
  Camera = stack.camera or image and caminfo  or ''
  Ctemp = temp and (" @ %sºC" % temp) or ''
  
  
  Telescope = controls.telescope.text
  Date = stack.date or ''

  -- FOV
  
  local pixel = tonumber(controls.pixelsize.text) or 0
  local focal = tonumber(controls.focal_len.text) or 0
  FOV = ''
  Rotation = formatDegrees(controls.rotate.value or 0)
  if focal > 0 and pixel > 0 then
    local arcsize = 36 * 18 / math.pi * pixel / focal     -- camera pixel size in arc seconds (assume square)
    arcsize = arcsize / controls.zoom.value                -- screen pixel size
    local radius, w, h = Oculus.radius()
    
    FOV = "fov: " .. (eyepiece and formatAngle(arcsize * radius * 2)
            or table.concat({formatAngle(w * arcsize), formatAngle(h * arcsize)}, " x\n") : gsub('\n', ' '))
  end
  
  local T = stack.exposure or 0
  Exposure = T / stack.Nstack     -- average per sub
  Stacks = "stack: %d/%d x %ds" % {stack.Nstack or 0, stack.subs and #stack.subs or 0, Exposure}
  Total = "total exposure: %d:%02d" % {math.floor(T / 60), T % 60}
  
  -- session and observation notes
  
  Obs_notes = controls.obs_notes.text or ''
  Ses_notes = controls.ses_notes.text or ''
 
  Signature = controls.settings.signature.text

end

-------------------------
--
-- PORTRAIT (Eyepiece)
--
  
local function portrait(W, H)
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
      Ltext(FOV, H - 85)
      Ltext(Telescope)
      Ltext(Camera .. Ctemp)
      -- Bottom Right
      Rtext(Stacks, H - 60)
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

local function landscape(W, H)
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
      Ltext(FOV, H - 90)
      Ltext(Telescope)
      Ltext(Camera .. Ctemp)
      -- Right
      Rtext(Signature, top + 10, 1.2)
      Rtext(Stacks, H - 65, 1.4)
      Rtext(Total)
    end)
end

-------------------------
--
-- SNAPSHOT
--

function _M.snap()
  image = session.image()
  if not image then return end
  
  eyepiece = controls.eyepiece.checked
  local name = controls.object.text 
  local sess = session.ID or ''
  local snap = path % {name, sess, os.time()}
  
  lg.setColor(1,1,1,1)
  get_annotations()
  
  do
    (eyepiece and portrait or landscape) (W, H) 
  end
  
  lg.setColor(1,1,1,1)
  canvas: newImageData() : encode ("png", snap)
  canvas: release()
 _log (snap)
    
end


return _M

-----
