--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.05",
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


local _log = require "logger" (_M)

local background = require "shaders.background"

local utils = require "utils"
local newTimer = utils.newTimer

local love = _G.love
local lg = love.graphics


local function prestack(workflow, img)
  local controls = workflow.controls
  local input, output = workflow()
  
  local imageData = img.imageData     -- this is in R16 format
  _log "creating R16 format image"
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = false})  
  
  local w = controls.workflow
  local bayerpat = w.debayer.checked and w.bayerpat.text or img.bayer

  -------------------------------
  --
  -- PRESTACK
  --
  
  workflow: newInput(rawImage, {format = "rgba16f", dpiscale = 1})
  workflow: calibrate()
  workflow: badpixel(bayerpat)      -- hot pixel removal different if there's a Bayer matrix  
  workflow: debayer(bayerpat)       -- debayer or or replicate to R,G,B channels
  
  local elapsed = newTimer()
  local offset = background.offset(workflow.output)  -- calculate & remove background offset from sub
  workflow: background(offset) 
  _log(elapsed "%.3f ms, background")
  
  rawImage:  release()
  imageData: release()
  
end


return prestack

-----


