--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.25",
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


local _log = require "logger" (_M)

local background = require "shaders.background"

local utils = require "utils"
local newTimer = utils.newTimer

local love = _G.love
local lg = love.graphics


local function prestack(workflow, frame)
  local controls = workflow.controls
--  local input, output = workflow()
  
  local imageData = frame.imageData     -- this is in R16 format
  _log ("creating R16 format image [%sx%s]" % {imageData: getDimensions()})
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = true})  
  
  local w = controls.workflow
  local forced = w.debayer.checked
  local option = w.bayer_opt
  local bayerpat = forced and (option[option.selected] or "RGGB") or frame.bayer
  frame.bayer = bayerpat
  
  -------------------------------
  --
  -- PRESTACK
  --
  
  workflow: newInput(rawImage, {format = "rgba16f", dpiscale = 1})
  workflow: calibrate(frame)
  workflow: badpixel(bayerpat)            -- hot pixel removal is different if there's a Bayer matrix  
  workflow: debayer(bayerpat)             -- debayer or or replicate to R,G,B, and A channels
  
--  if not frame.dark_calibration then      -- calculate & remove background offset from sub
    local elapsed = newTimer()
    local offset = background.offset(workflow.output)
    workflow: background(offset) 
    _log(elapsed "%.3f ms, background")
--  end
  
  rawImage:  release()
  imageData: release()
  
end


return prestack

-----


