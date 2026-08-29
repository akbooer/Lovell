--
-- stacking.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.15",
    AUTHOR = "AK Booer",
    DESCRIPTION = "The stack",
  }


-- 2026.05.06  extracted from observer and stacker code
-- 2026.07.15  include RGBL in stacker call for scaling


local _log = require "logger" (_M)


local controls  = require "controls"
local aligner   = require "aligner"
local stacker   = require "shaders.stacker"
local vector    = require "lib.vector"
local newTimer  = require "utils" .newTimer

local stack           -- the stack frame, full of useful info


function _M.get()
  return stack
end

function _M.clear()
  stack = nil
end

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
        
        
local function stacking(workflow, wstack, filter, bayer, exposure)
  local elapsed = newTimer()
  
  filter = filter:upper()
  _log("filter type: ", filter)
  local filterChans = bayer and rgb_filter.RGB or rgb_filter[filter] or {f,f,f,t}
  local countChans  = bayer and rgb_count.RGB or rgb_count[filter] or {0,0,0,0}
    
  local RGBL = workflow.RGBL or vector {0,0,0,0,  0,0,0,0}      -- initalise stack counts, and exposures
  
  countChans = vector(countChans)
  
  RGBL = RGBL + (countChans .. (countChans * exposure))
  workflow.RGBL = RGBL
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

function _M.new(workflows, frame)
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

  if frame.first then
    
     -- create/clear new stack
    
    workflow: save "stack_sigma"
    workflow: clear ("stack_sigma", 1,1,1,1)    -- maximum variance in all channels  TODO: could do better?
    
    wstack: clear "input"
    wstack: clear "output"
    wstack: newInput(workflow.output)
    
    workflow.RGBL = nil                       -- clear count of separate R,G,B,L subs and exposures
    
    stack = {}
    
    for n,v in pairs(frame) do stack[n] = v end    
    stack.image = wstack
    stack.Nstack = 0
    stack.exposure = 0
    stack.subs = {}
    
    stack.keystars = frame.stars     -- possible to choose a different stack for keystars subsequently?
    alignment = aligner.null()
    
  else
    if not stack then return end
    local w, h = workflow: getDimensions()
    local maxDist = controls.stacking.offset.value

    alignment, paired = aligner.transform(stack.keystars, frame.stars, maxDist, w/2, h/2)
    frame.matched_pairs = paired
  end
  
  -- remove keywords and headers from subframes
  frame.headers = nil
  frame.keywords = nil
   
  -- store alignment info
  frame.align = alignment
  stack.subs[#stack.subs + 1] = frame
  
  -------------------------------
  --
  -- ALIGN and STACK, if valid alignment
  --

  if alignment and not controls.reject[frame.name] then
    stacker.align (workflow, alignment)  -- image must be aligned BEFORE stack
    
    local filter, bayer, exposure
    filter = frame.filter                         -- stacker needs to know which filter(s)
    bayer = frame.bayer
    exposure = frame.exposure or 0                -- ...and the exposure 
    stack.exposure = stack.exposure + exposure
    
    stack.Nstack = stack.Nstack + 1
    
    stacking (workflow, wstack, filter, bayer, exposure)
    stack.background = workflow: background(wstack.output)   
 
  end
  
  _log(elapsed "%.3f ms, STACK total")

end


return _M

-----
