--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.23",
    AUTHOR = "AK Booer",
    DESCRIPTION = "prestack processing (bad pixel, debayer, ...)",
  }

-- 2024.11.06  Version 0
-- 2024.11.11  return metadata, including clone() method, along with image
-- 2024.11.17  release image when finished with it
-- 2024.12.16  use workflow() buffers

-- 2025.01.29  integrate into workflow


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

local badpixel  = require "shaders.badpixel"
local debayer   = require "shaders.debayer"
local utils     = require "utils"


local function prestack(workflow, img)
  local controls = workflow.controls
   
  local imageData = img.imageData     -- this is in R16 format
  _log "creating R16 format image"
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = true})  
  
  -- decide whether workflow chain is monochrome or RGB
  local w = controls.workflow
  local bayerpat = w.debayer.checked and w.bayerpat.text or img.bayer
--  local bufferFormat = bayerpat and "rgba16f" or "r16"
  local bufferFormat = "rgba16f" 
  
  workflow: newInput(rawImage, {format = bufferFormat, dpiscale = 1})
  workflow: badpixel()
  workflow: debayer(bayerpat)   -- 16-bit mono -> floating point RGB, possibly
  
  rawImage:  release()
  imageData: release()
    
  return workflow
end


return prestack

-----


