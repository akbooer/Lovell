--
-- stacking.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "The stack",
  }


-- 2026.05.06  extracted from observer and stacker code
-- 2026.07.15  include RGBL in stacker call for scaling
-- 2026.09.09  retain FITS headers in each frame
-- 2026.10.14  use workflow.wstack for the stack workflow
-- 2026.10.24  remove unused star alignment parameters


local _log = require "logger" (_M)


local controls  = require "controls"
local aligner   = require "aligner"
local stacker   = require "shaders.stacker"
local vector    = require "lib.vector"
local newTimer  = require "utils" .newTimer


-------------------------------
--
-- RGBL calculations to track number of exposures of each filter
--

local t, f = true, false

local rgb_filter = {
          R   = {t,f,f,f}, 
          G   = {f,t,f,f}, 
          B   = {f,f,t,f}, 
          H   = {t,f,f,f}, 
          S   = {f,t,f,f}, 
          O   = {f,f,t,f}, 
          L   = {f,f,f,t},    -- Luminance is stored in alpha channel
          RGB = {t,t,t,f},
        }

local rgb_count = {
          R   = {1,0,0,0}, 
          G   = {0,1,0,0}, 
          B   = {0,0,1,0}, 
          H   = {1,0,0,0}, 
          S   = {0,1,0,0}, 
          O   = {0,0,1,0}, 
          L   = {0,0,0,1}, 
          RGB = {1,1,1,0},
        }
        
        
local function stacking(workflow, filter, bayer, exposure)
  local elapsed = newTimer()
  local wstack = workflow.wstack
  
  filter = filter:upper()
  _log("filter type: ", filter)
  local filterChans = bayer and rgb_filter.RGB or rgb_filter[filter] or {f,f,f,t}
  local countChans  = bayer and rgb_count.RGB or rgb_count[filter] or {0,0,0,0}
  countChans = vector(countChans)
    
  local RGBL = controls.RGBL or 
          vector {0,0,0,0,  0,0,0,0}      -- initalise stack counts, and exposures
  
  RGBL = RGBL + (countChans .. (countChans * exposure))
  
  controls.RGBL = RGBL
  workflow.sequence = workflow.sequence and (workflow.sequence + 1) or 1    -- track stack updates

  stacker.stack(wstack, workflow, filterChans, RGBL)
 
  local sopt = stacker.stackOptions
  local sel = sopt.selected
  local rgbl = "%dR %dG %dB %dL" % RGBL
  _log("RGBL exposures (#, s):", unpack(RGBL))
  _log(elapsed ("%.3f ms, %s %s stack", rgbl, sopt[sel]))
end


-------------------------------
--
-- ADD new frame to stack
--

local function stack(workflows, frame)
  _log ''
  _log "STACK"
  local elapsed = newTimer()
  local workflow = workflows.main
  local wstack = workflows.wstack
  
  -------------------------------
  --
  -- FIRST NEW FRAME in an observation sets up new STACK frame
  --

  local alignment, paired

  local info = controls.info
  if frame.first then
    
     -- create/clear new stack
    
    workflow: save "stack_sigma"
    workflow: clear ("stack_sigma", 1,1,1,1)    -- maximum variance in all channels  TODO: could do better?
    
    wstack: clear "input"
    wstack: clear "output"
    wstack: newInput(workflow.output)
    
    controls.RGBL = nil                       -- clear count of separate R,G,B,L subs and exposures
    
    for n,v in pairs(frame) do info[n] = v end    
    info.image = wstack
    info.Nstack = 0
    info.exposure = 0
    info.subs = {}
    
    info.keystars = frame.stars     -- possible to choose a different stack for keystars subsequently?
    alignment = aligner.null()
    
  else
--    if not stack then return end
    if not info.subs then return end
    local w, h = workflow: getDimensions()

    alignment, paired = aligner.transform(info.keystars, frame.stars, w/2, h/2)
    frame.matched_pairs = paired
  end
  
  -- remove keywords from subframes but retain headers for FITS header database
--  frame.headers = nil
  frame.keywords = nil
   
  -- store alignment info
  frame.align = alignment
  info.subs[#info.subs + 1] = frame
  controls.subs = info.subs
  
  
  -------------------------------
  --
  -- ALIGN and STACK, if valid alignment
  --

  if alignment and not controls.reject[frame.name] then
    stacker.align (workflow, alignment)  -- image must be aligned BEFORE stack
    
    local filter, bayer, exposure
    filter = frame.filter                         -- stacker needs to know which filter(s)
    bayer = controls.BAYER
    exposure = frame.exposure or 0                -- ...and the exposure 
    info.exposure = info.exposure + exposure
    
    info.Nstack = info.Nstack + 1
    
    stacking (workflow, filter, bayer, exposure)
    info.background = workflow: background(wstack.output)  
 
  end
  
  _log(elapsed "%.3f ms, STACK total")

end


return stack

-----
