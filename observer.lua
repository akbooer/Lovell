--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.06",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

local _log = require "logger" (_M)

local prestack    = require "prestack"
local starfinder  = require "shaders.starfinder"
local stacker     = require "shaders.stacker"
local aligner     = require "aligner"
local poststack   = require "poststack"


local buffer  = require "utils" .buffer

local stack           -- the stacked image
local keystars
local stackframe


-------------------------------
--
-- OBSERVATION - specific data
--

_M.settings = nil

local function clear_settings()
--  _M.settings = {
--    target = nil,
--    notes = nil,
--    telescope = nil,
--    observation = nil,
--  }
end

clear_settings()

-------------------------------
--
-- start of whole new observation
--

function _M.new(controls)
  clear_settings()
  controls:reset()        -- start with new default values for processing options
  stack = nil
  stackframe = nil
  keystars = nil
  _log "------------------------"
  _log "new observation"
end


-------------------------------
--
-- new sub frame
--

function _M.newSub(img, controls)
  
  controls.Nstack = img.subNumber
  local Nstack = controls.Nstack
  
  _log ''
  _log ("newSub #%d %s" % {Nstack, img.name})
 
  local subframe = prestack(img)
  local subimage = subframe.image
  
  local span = 50
  local theta, xshift, yshift = 0, 0, 0
  
   if Nstack == 1 then
     
     stack = buffer(subimage, stack)
     stackframe = subframe: clone()           -- copy relevant info from first image
     stackframe.image = stack
     keystars = starfinder(subimage, span, stack.channel)
    _log ("found %d keystars in frame #1" % #keystars)
    theta, xshift, yshift = 0, 0, 0
   else
    local stars = starfinder(subimage, span)     -- extracted star positions and intensities
    theta, xshift, yshift = aligner.transform(stars, keystars, {maxDist = 10})
  end

  local params = {
      filter = img.filter,
      xshift = xshift, 
      yshift = yshift, 
      theta  = theta,
      depth  = Nstack,
    }
    
  if theta and math.sqrt(xshift^2 + yshift^2) < 10 then
    stacker.stack (subimage, stack, params)
  end
  
  stackframe.Nstack = Nstack
  return stackframe
end

_M.reprocess = poststack

return _M

-----


