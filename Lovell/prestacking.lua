--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.11.08",
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
-- 2026.10.24  control.zoom calculation moved to here from loadSession()
-- 2026.11.06  move workflow processing to prestack plugin
-- 2026.11.08  move screen zoom calculation to loadSession()



local _log = require "logger" (_M)

local controls  = require "controls"
local utils  = require "utils"

local love = _G.love
local lg = love.graphics


local function prestack(workflows, frame)
  _log ''
  _log "PRESTACK"
  local elapsed = utils.newTimer()
  local workflow = workflows.main
  
  local imageData = frame.imageData
  -- TODO: consider using replacePixels() rather than creating new rawImage
  _log ("creating image %s[%sx%s]" % {imageData:getFormat(), imageData: getDimensions()})
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = true})  

  -- stacking control cluster
  local s = controls.stacking
  local maxstar = s.maxstar.value  
 
  -------------------------------
  
  workflow: newInput(rawImage)
  workflow: plugin("prestack", frame, controls.BAYER)

  frame.thumb = workflow: thumbnail()           -- store thumbnail
  frame.stars = workflow: starfinder(maxstar)   -- extract star positions and flux
   
  rawImage: release()
  imageData: release()
  frame.imageData = nil
  
  lg.reset()
  
  _log(elapsed "%.3f ms, PRESTACK total")
  
end


return prestack

-----


