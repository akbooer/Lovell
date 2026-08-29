--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.04.28",
    AUTHOR = "AK Booer",
    DESCRIPTION = "prestack processing (bad pixel, debayer, ...)",
  }

-- 2024.11.06  Version 0
-- 2024.11.11  return metadata, including clone() method, along with image
-- 2024.11.17  release image when finished with it
-- 2024.12.16  use workflow() buffers

-- 2025.01.29  integrate into workflow
-- 2025.03.10  pass Bayer pattern (possibly overridden) to badpixel()
-- 2025.05.05  move background offet subtraction to here from observer module
-- 2025.05.25  don't remove background offset if image is already calbrated

-- 2026.03.29  change canvas precision from rgba16f to rgba16
-- 2026.04.10  make thumbnail creation and star detection part of prestack processing
-- 2026.04.28  calculate thumbnail statistics as proxy for full image


local _log = require "logger" (_M)

local controls  = require "controls"
local newTimer  = require "utils" .newTimer

local love = _G.love
local lg = love.graphics


local function prestack(workflows, frame)
  _log ''
  _log "PRESTACK"
  local elapsed = newTimer()
  local workflow = workflows.main
  
  local imageData = frame.imageData
  _log ("creating image %s[%sx%s]" % {imageData:getFormat(), imageData: getDimensions()})
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = true})  
  
  -- prestack control cluster
  local p = controls.prestack
  local do_dark, do_flat = p.do_dark.checked, p.do_flat.checked
  local option = p.bayer_opt
  local selected = option[option.selected]

  -- stacking control cluster
  local s = controls.stacking
  local radius = s.radius.value   -- star peak search radius
  local maxstar = s.maxstar.value
  
  local bayerpat = selected ~= "Auto" and selected or frame.bayer
  frame.bayer = bayerpat
  
  local ratio = p.badpixel.checked and p.badratio.value or 1e6   -- turn it on/off

  -------------------------------
  --
  -- PRESTACK
  --
  
  workflow: newInput(rawImage)
  
  workflow: calibrate(frame, do_dark, do_flat)
  workflow: badpixel(bayerpat, ratio)           -- hot pixel removal is different if there's a Bayer matrix  
  workflow: debayer(bayerpat)                   -- debayer or replicate to R,G,B, and A channels

  frame.thumb = workflow: thumbnail()                         -- store thumbnail
  frame.stars = workflow: starfinder(radius, maxstar)         -- extract star positions and flux
   
  rawImage: release()
  imageData: release()
  frame.imageData = nil
  
  lg.reset()
  
  _log(elapsed "%.3f ms, PRESTACK total")
  
end


return prestack

-----


