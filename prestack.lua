--
-- prestack.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.11",
    AUTHOR = "AK Booer",
    DESCRIPTION = "prestack processing (bad pixel, debayer, ...)",
  }

-- 2024.11.06  Version 0
-- 2024.11.11  return metadata, including clone() method, along with image
-- 2024.11.17  release image when finished with it


local _log = require "logger" (_M)

local love = _G.love
local lg = love.graphics

local badpixel  = require "shaders.badpixel"
local debayer   = require "shaders.debayer"
local buffer    = require "utils" .buffer

local r16         -- raw camera data buffer
local rgba16f      -- general rgb buffer

local rgba16fSettings = {format = "rgba16f", dpiscale = 1}

-- clone everything except image
local function clone(self)
  local new = {}
  for n,v in pairs(self) do
    new[n] = v
  end
  new.image = nil
  return new
end

local function thumbnail(image)
  local w,h = image:getDimensions()
  local scale = 500 / w
  local thumb = lg.newCanvas(500, math.floor(scale * h))
  thumb: renderTo(lg.draw, image, 0,0, 0, scale, scale)
  return thumb
  end


local function prestack(img)
   
  local imageData = img.imageData     -- this is in R16 format
  local rawImage = lg.newImage(imageData, {dpiscale=1, linear = true})  

  r16 = buffer(rawImage, r16)
  rgba16f = buffer(rawImage, rgba16f, rgba16fSettings)
  
  badpixel(rawImage, r16)
  
  debayer(r16, rgba16f, {bayer = img.bayer})   -- 16-bit mono -> floating point RGB
  
  imageData: release()
  rawImage:  release()
 
  img.image = rgba16f
  img.clone = clone
  
  return img
end


return prestack

-----


