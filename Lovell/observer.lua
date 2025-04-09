--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.02",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

-- 2025.01.01  pass workflow controls to aligner
-- 2025.01.22  add thumbnails to stack frame
-- 2025.03.23  fix nil alignment error (thanks @Songwired, issue #1)
-- 2025.04.01  add RGBL exposures (issue #6)


local _log = require "logger" (_M)

local aligner     = require "aligner"
local poststack   = require "poststack"

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
-- THUMBNAIL
--

local function thumbnail(image)
  local Wthumb = 700        -- thumbnail width, height scales to preserve aspect ratio
  local lg = _G.love.graphics
  local elapsed = require "utils" .newTimer()
  
  local w,h = image:getDimensions()
  local scale = Wthumb / w
  local Hthumb = math.floor(scale * h)
  local thumb = lg.newCanvas(Wthumb, Hthumb, {dpiscale = 1, format = "rgba16f"})
  lg.setColor (1,1,1, 1)
  thumb: renderTo(lg.draw, image, 0,0, 0, scale, scale)
  
  _log(elapsed ("%0.3f ms, [%dx%d] created thumbnail", Wthumb, Hthumb))
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

  local align, paired
  local starspan = workflow.controls.workflow.keystar.value   -- star peak search radius

  -------------------------------
  --
  -- FIRST NEW FRAME in an observation sets up new STACK frame (and Luminance)
  --

  if frame.first then
    -- create/clear new multi-spectral and mono stacks
    workflow: save ("stack_variance", {dpiscale = 1, format = "r32f"})
    workflow: clear ("stack_variance", 1e3,0,0,0)
    workflow: save "luminance"   --, {dpiscale = 1, format = "r16f"})
    workflow: clear "luminance"
    workflow: save "stack"
--    workflow: clear "stack"
    workflow.stack: renderTo(love.graphics.draw, workflow.output)
    workflow. RGBL = nil                      -- clear count of separate R,G,B,L subs and exposures
    
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
    align = aligner.null()
  else
    if not stack then return end
    frame.stars = workflow: starfinder(starspan)      -- EXTRACT star positions and intensities
    local w, h = workflow: getDimensions()
--    theta, xshift, yshift, paired = aligner.transform(frame.stars, stack.keystars, workflow.controls, w/2, h/2)
    align, paired = aligner.transform(stack.keystars, frame.stars, workflow.controls, w/2, h/2)
    frame.matched_pairs = paired
  end
  
  -- remove keywords and headers from subframes
  frame.headers = nil
  frame.keywords = nil
  
  -- calculate & remove gradients from sub
  local gradients = background.calculate(workflow.output)
  workflow: background(gradients) 
  
  -- store thumbnail and alignment info
  frame.thumb = thumbnail (workflow.output)
  frame.align = align
  stack.subs[#stack.subs + 1] = frame
  
--  table.sort(stack, function(a,b) return a.epoch < b.epoch end)   -- sort the stack by time
  
  -------------------------------
  --
  -- STACK, if valid alignment
  --

  if align and not frame.omit_from_stack then
    stack.Nstack = stack.Nstack + 1
    local exposure = frame.exposure or 0
    stack.exposure = stack.exposure + exposure
    
    align.filter = frame.filter               -- stacker needs to know which filter(s)
    align.exposure = exposure                 -- ...and the exposure    
    workflow: stacker (align)
    stack.gradients = background.calculate(workflow.stack)    
  end
  
--    stack.thumbnail = thumbnail(workflow.stack)          -- add overall stack thumbnail too? * * * *

  return stack
end

_M.postprocess = poststack


return _M

-----
