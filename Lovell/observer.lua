--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.22",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

-- 2025.01.01  pass workflow controls to aligner
-- 2025.01.22  add thumbnails to stack frame


local _log = require "logger" (_M)

local aligner     = require "aligner"
local poststack   = require "poststack"

local background  = require "shaders.background"

local workflow    = require "workflow" .new()

local stack


-------------------------------
--
-- OBSERVATION, start of whole new one
--

function _M.new()
  stack = nil
  _log "------------------------"
  _log "new observation"
end


-------------------------------
--
-- THUMBNAIL
--

local function thumbnail(image)
  local Wthumb = 700        -- thumbnail width, height scales to preserve aspect ratio
  local lg = _G.love.graphics
  local elapsed = require "utils" .newTimer ()
  
  local w,h = image:getDimensions()
  local scale = Wthumb / w
  local thumb = lg.newCanvas(Wthumb, math.floor(scale * h), {dpiscale = 1, format = "rgba16f"})
  lg.setColor (1,1,1, 1)
  thumb: renderTo(lg.draw, image, 0,0, 0, scale, scale)
  
  _log(elapsed "%0.3f ms, created thumbnail")
  return thumb
end

-------------------------------
--
-- new sub frame - 16-bit image input
--

function _M.newSub(frame, controls)

  _log ''
  _log ("newSub #%d %s" % {(stack and #stack.subs or 0) + 1, frame.name})
  
  workflow.controls = controls
  
  workflow: prestack(frame)       -- PRESTACK processing

  local theta, xshift, yshift
  local starspan = workflow.controls.workflow.keystar.value   -- star peak search radius

  -------------------------------
  --
  -- FIRST NEW FRAME in an observation sets up new STACK frame
  --

  if frame.first then
    -- save info from first image into new stack frame
    workflow: saveOutput "stack"
    stack = {}           
    for n,v in pairs(frame) do 
      stack[n] = v 
    end
    
    stack.image = workflow.stack
    stack.Nstack = 0
    stack.exposure = 0
    stack.subs = {}
    stack.workflow = workflow
    local keystars = workflow: starfinder(starspan)   -- EXTRACT keystars
    frame.stars = keystars
    stack.keystars = keystars     -- possible to choose a different stack for keystars subsequently
    _log ("found %d keystars in frame #1" % #keystars)
    theta, xshift, yshift = 0, 0, 0
  else
    frame.stars = workflow: starfinder(starspan)     -- EXTRACT star positions and intensities
    theta, xshift, yshift, frame.matched_pairs = aligner.transform(frame.stars, stack.keystars, workflow.controls)
  end
  
  -- remove keywords and headers from subframes
  frame.headers = nil
  frame.keywords = nil
  
  -- store thumbnail and alignment info
  frame.thumb = thumbnail (workflow.output)
  local align = {theta = theta, xshift = xshift, yshift = yshift}             -- for rotation (radians) ...
  if theta then
     align[1], align[2], align[3] = xshift, yshift, theta * 180 / math.pi     -- ... for display (degrees)
  end
  frame.align = align
  
  -- save the alignment information (for restacking later ?)
  stack.subs[#stack.subs + 1] = frame
  table.sort(stack, function(a,b) return a.epoch < b.epoch end)   -- sort the stack by time
  
  -------------------------------
  --
  -- STACK, if valid alignment
  --
  
  if theta and (xshift * xshift + yshift * yshift) < controls.workflow.offset.value ^ 2 then

    stack.Nstack = stack.Nstack + 1
--    stack.totalExposure = stack.totalExposure + (stack.exposure or 0)
    stack.exposure = stack.exposure + (frame.exposure or 0)
    
    -- STACK the latest frame
    workflow: stacker {
      filter = frame.filter,
      xshift = -xshift, 
      yshift = -yshift, 
      theta  = -theta,
      depth  = stack.Nstack,
    }
    
    -- pre-compute gradients after stack
    stack.gradients = background.solve(workflow.stack)
    
--    stack.thumbnail = thumbnail(workflow.stack)          -- add overall stack thumbnail too? * * * *
    
  end

  return stack
end

_M.reprocess = poststack

return _M

-----
