--
-- observer.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.01",
    AUTHOR = "AK Booer",
    DESCRIPTION = "coordinates observation workflow",
  }

-- 2024.10.21  Version 0

-- 2025.01.01  pass workflow controls to aligner
-- 2025.01.22  add thumbnails to stack frame
-- 2025.03.23  fix nil alignment error (thanks @Songwired, issue #1)
-- 2025.04.01  add RGBLexposure for (issue #6)


local _log = require "logger" (_M)

local aligner     = require "aligner"
local poststack   = require "poststack"

local background  = require "shaders.background"

local workflow    = require "workflow" .new()    -- RGB or colour filter workflow

local stack

local deg = 180 / math.pi

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

  local theta, xshift, yshift, paired
  local starspan = workflow.controls.workflow.keystar.value   -- star peak search radius

  -------------------------------
  --
  -- FIRST NEW FRAME in an observation sets up new STACK frame (and Luminance)
  --

  if frame.first then
    -- create/clear new multi-spectral and mono stacks
    workflow: save ("variance")     -- NEEDS SEPARATE RGB ?? AND L ???, {dpiscale = 1, format = "r16f"})
    workflow: clear ("variance", 1,1,1,1)
    workflow: save "luminance"   --, {dpiscale = 1, format = "r16f"})
    workflow: clear "luminance"
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
    stack.subs = {}
    stack.workflow = workflow
    local keystars = workflow: starfinder(starspan)   -- EXTRACT keystars
    frame.stars = keystars
    stack.keystars = keystars     -- possible to choose a different stack for keystars subsequently
    _log ("found %d keystars in frame #1" % #keystars)
    theta, xshift, yshift = 0, 0, 0
  else
    if not stack then return end
    frame.stars = workflow: starfinder(starspan)      -- EXTRACT star positions and intensities
    local w, h = workflow: getDimensions()
    theta, xshift, yshift, paired = aligner.transform(frame.stars, stack.keystars, workflow.controls, w/2, h/2)
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
  local align
  if theta then
    align = {
        xshift, yshift, theta * deg,                                                -- for display (degrees) ...
        theta = -theta, xshift = -xshift, yshift = -yshift, filter = frame.filter,  -- ...for stack (radians)
      }
  end
    
  frame.align = align
  stack.subs[#stack.subs + 1] = frame
  
--  table.sort(stack, function(a,b) return a.epoch < b.epoch end)   -- sort the stack by time
  
  -------------------------------
  --
  -- STACK, if valid alignment
  --

  if align 
    and (xshift * xshift + yshift * yshift) < controls.workflow.offset.value ^ 2 
    and not frame.omit_from_stack then
    stack.Nstack = stack.Nstack + 1
    local exposure = frame.exposure or 0
    stack.exposure = stack.exposure + exposure
    
    align.exposure = exposure
--    align.minVar = true   -- * * * * * use minimum variance stacker * * * * *
    
    workflow: stacker (align)
    stack.gradients = background.calculate(workflow.stack)
    
  end

  -- pre-compute luminance gradients after stack
--  local R, G, B, L = unpack(workflow.RGBL)
--  controls.workflow.RGBL = workflow.RGBL                  -- so that GUI infopanel has access
--  local ratio = (R + G + B) / (3 * L + 1e-6)             --  is there a Luminance filter? (avoid zero division)

--  workflow: newInput(stack.image)
--  workflow: synthL({1,1,1}, workflow.luminance, ratio)    -- synthetic lum, or could be {.7,.2,.1}, etc.
--  workflow: synthL({1,1,1})
  
--    stack.thumbnail = thumbnail(workflow.stack)          -- add overall stack thumbnail too? * * * *

  return stack
end

_M.postprocess = poststack

return _M

-----
