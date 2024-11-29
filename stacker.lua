--
-- stacker.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.06",
    AUTHOR = "AK Booer",
    DESCRIPTION = "stacks individual subs",
  }

-- 2024.10.21  Version 0

local _log = require "logger" (_M)

local prestack    = require "prestack"
local starfinder  = require "shaders.starfinder"
local aligner     = require "aligner"

local love = _G.love
local lg = love.graphics

local buffer  = require "utils" .buffer

local stack           -- the stacked image
local keystars
local stackframe

-- clear the stack
function _M.newStack(controls)
  controls:reset()        -- start with new default values for processing options
  stack = nil
  stackframe = nil
  keystars = nil
  _log "------------------------"
  _log "new stack"
end

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
   else
    local stars = starfinder(subimage, span)     -- extracted star positions and intensities
    theta, xshift, yshift = aligner.transform(stars, keystars)
  end

local rgb_filter = {R = {3,0,0,1}, G = {0,3,0,1}, B = {0,0,3,1}}

  do -- STACK
    
--    lg.setColor(1,1,1,1)
    
    local mono_filter = rgb_filter[img.filter: upper()] 
    if mono_filter then
      lg.setColor(unpack(mono_filter))
    end

--    lg.setBlendMode("add")
    lg.setBlendMode("add", "premultiplied")
    
--    theta = 0 -- * * * * * * * * * * 
    stack:setFilter "linear"
    stack: renderTo(lg.draw, subimage, xshift, yshift, theta)
    lg.setBlendMode "alpha"
    lg.setColor(1,1,1,1)
  
  end

  stackframe.Nstack = Nstack
  return stackframe
end


return _M

-----


