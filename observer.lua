--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

local _log = require "logger" (_M)

local prestack    = require "prestack"
local aligner     = require "aligner"
local poststack   = require "poststack"

local starfinder  = require "shaders.starfinder"
local stacker     = require "shaders.stacker"
local background  = require "shaders.background"


local stack           -- the stacked image
local keystars
local stackframe


-------------------------------
--
-- OBSERVATION, start of whole new one
--

function _M.new()
  stack = nil
  stackframe = nil
  keystars = nil
  _log "------------------------"
  _log "new observation"
end


-------------------------------
--
-- new sub frame - 16-bit image input
--

function _M.newSub(img, controls)

  _log ''
  _log ("newSub #%d %s" % {(stackframe and #stackframe.subs or 0) + 1, img.name})

  local workflow = prestack(img, controls)

  local theta, xshift, yshift

  if not stackframe then
    stack = workflow.saveOutput()
    stackframe = img           -- save info from first image 
    stackframe.image = stack
    stackframe.Nstack = 0
    stackframe.totalExposure = 0
    stackframe.workflow = workflow
    keystars = starfinder(workflow)
    _log ("found %d keystars in frame #1" % #keystars)
    theta, xshift, yshift = 0, 0, 0
  else
    local stars = starfinder(workflow)     -- extracted star positions and intensities
    theta, xshift, yshift = aligner.transform2(stars, keystars, {maxDist = 20})
  end
  
  -- save the alignment information for restacking later ??
  local subs = stackframe.subs or {}
  subs[#subs + 1] = {theta = theta, xshift = xshift, yshift = yshift}
  stackframe.subs = subs
  
  if theta and math.sqrt(xshift * xshift + yshift * yshift) < 25 then

    stackframe.Nstack = stackframe.Nstack + 1
    stackframe.totalExposure = stackframe.totalExposure + (stackframe.exposure or 0)
    local params = {
      filter = img.filter,
      xshift = -xshift, 
      yshift = -yshift, 
      theta  = -theta,
      depth  = stackframe.Nstack,
    }
    stacker.stack (stackframe, params)
    -- pre-compute gradients after stack
    stackframe.gradients = background.solve(stack)
  end

  return stackframe
end

_M.reprocess = poststack

return _M

-----
