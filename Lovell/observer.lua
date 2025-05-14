--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.11",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

-- 2025.01.01  pass workflow controls to aligner
-- 2025.01.22  add thumbnails to stack frame
-- 2025.03.23  fix nil alignment error (thanks @Songwired, issue #1)
-- 2025.04.01  add RGBL exposures (issue #6)
-- 2025.05.10  use 1.0e5 for starting stack variance (large number in half float precision)


local _log = require "logger" (_M)

local aligner     = require "aligner"
local poststack   = require "poststack"
local calibration = require "databases.calibration"

local background  = require "shaders.background"

local workflow    = require "workflow" .new()    -- RGB or colour filter workflow

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
-- SUBS
--

local subs = {}

function subs: reject_list()
  local x = {}
  for _, s in ipairs(self) do
    x[#x+1] = s.rejected and s.name or nil
  end
  return #x > 0 and x or nil
end

function subs.new()
  return setmetatable({}, subs)
end


-------------------------------
--
-- new sub frame - 16-bit image input
--

function _M.newSub(frame, controls)
  _log ''
  _log ("newSub #%d %s" % {(stack and #stack.subs or 0) + 1, frame.name})
  
  workflow.controls = controls
  local align, paired
  local starspan = controls.workflow.keystar.value   -- star peak search radius
 
  -------------------------------
  --
  -- FIRST NEW FRAME in an observation sets up new STACK frame (and Luminance)
  --
  
  workflow: prestack(frame)       -- PRESTACK processing
  
  if frame.first then
    
    -- create/clear new multi-spectral and mono stacks
    workflow: save "stack_variance"
    workflow: clear ("stack_variance", 1e5,1e5,1e5,1e5)   -- start with huge variance
    workflow: save "stack"
    workflow: clear "stack"
    workflow. RGBL = nil                      -- clear count of separate R,G,B,L subs and exposures
    
    stack = {}           
    for n,v in pairs(frame) do 
      stack[n] = v 
    end
    
    stack.image = workflow.stack
    stack.Nstack = 0
    stack.exposure = 0
    stack.subs = subs.new ()
    stack.workflow = workflow
    local keystars = workflow: starfinder(starspan)   -- EXTRACT keystars
    frame.stars = keystars
    stack.keystars = keystars     -- possible to choose a different stack for keystars subsequently
    _log ("found %d keystars in frame #1" % #keystars)
    align = aligner.null()
    
  else
    if not stack then return end
    frame.stars = workflow: starfinder(starspan)      -- EXTRACT star positions and intensities
    local w, h = workflow: getDimensions()
    align, paired = aligner.transform(stack.keystars, frame.stars, workflow.controls, w/2, h/2)
    frame.matched_pairs = paired
  end
  
  -- remove keywords and headers from subframes
  frame.headers = nil
  frame.keywords = nil
   
  -- store thumbnail and alignment info
  frame.thumb = workflow: thumbnail()
  frame.align = align
  stack.subs[#stack.subs + 1] = frame
  
--  table.sort(stack, function(a,b) return a.epoch < b.epoch end)   -- sort the stack by time
  
  -------------------------------
  --
  -- STACK, if valid alignment
  --

  if align and not frame.rejected then
    stack.Nstack = stack.Nstack + 1
    local exposure = frame.exposure or 0
    stack.exposure = stack.exposure + exposure
    
    align.filter = frame.filter               -- stacker needs to know which filter(s)
    align.exposure = exposure                 -- ...and the exposure    
    workflow: stacker (align)
    stack.gradients = background.gradients(workflow.stack)    
  end
  
--    stack.thumbnail = thumbnail(workflow.stack)          -- add overall stack thumbnail too? * * * *

  return stack
end

_M.postprocess = poststack


return _M

-----
