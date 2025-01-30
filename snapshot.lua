--
-- snapshot.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.19",
    AUTHOR = "AK Booer",
    DESCRIPTION = "compose and save snapshots",
  }

-- 2024.12,19  Version 0

local _log = require "logger" (_M)


local session = require "session"
local utils   = require "utils"

local suit = require "suit"
local self = suit.new()     -- make a new SUIT instance for ourselves

local Oculus = utils.Oculus


local love = _G.love
local lg = love.graphics


local path = "snapshots/%s_%s_%x.png"   -- target, session, epoch in hexadecimal


function _M.snap(panels)
  local image = session.image()
  if not image then return end
  local w,h = image:getDimensions()
  
  local controls = session.controls
  local eyepiece = controls.eyepiece.checked
  local name = controls.object.text 
  local sess = session.ID or ''
  local snap = path % {name, sess, os.time()}
  
  local W, H = 1280, 1024
  local ratio = H / h
--  if eyepiece then    -- square image, plus annotation
--    W = H + annotations.width
--  else                -- retain full frame aspect ratio, possibly plus annotation (if pinned)
    W = w * ratio + panels.width
--  end
    
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
  
  local canvas = lg.newCanvas(W, H, {format = "normal", dpiscale = 1})
  
  lg.setColor(1,1,1,1)
  panels.update(self, canvas)
--  lg.setCanvas{canvas, stencil=true}
  canvas: renderTo(function()
      lg.clear(0,0,0)
--      if eyepiece then Oculus.draw() end
      lg.draw(image, flipx < 1 and (W - panels.width) or 0, flipy < 0 and H or 0, 0, ratio * flipx, ratio * flipy)
--      lg.draw(image, 0,0, 0, ratio)
      self: draw()
    end)
  canvas: newImageData() : encode ("png", snap)
  canvas: release()
  _log (snap)
  
end


return _M

-----
