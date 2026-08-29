--
-- session.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.07.24",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Session manager",
  }

-- 2024.11.21  Version 0
-- 2024.12.02  separate DSO module

-- 2025.02.21  initialise on load, remove load() function

-- 2026.05.11  add Auto to Bayer pattern options
-- 2026.05.15  split controls into separate module
-- 2026.05.26  move controls.reset() to controls module
-- 2026.06.11  integrate functionality from old observer module
-- 2026.06.14  add GUI update/draw (previously in main module)
-- 2026.07.24  create multiple workflows for pre-, stack, and post-processing


local _log = require "logger" (_M)

local controls    = require "controls"

local stacking    = require "stacking"
local prestack    = require "prestack"
local poststack   = require "poststack"

local obsessions  = require "databases.obsessions"
local saveSession = obsessions.saveSession
local loadSession = obsessions.loadSession

local GUI = require "guillaume"

local workflow = require "workflow" 

local workflows = {
    main   = workflow.new {name = "workflow", format = "rgba16"},             -- the main workflow 
    wstack = workflow.new {name = "wstack",   format = "rgba32f"}             -- the stack workflow
  }

local love = _G.love

local newFITSfile = love.thread.getChannel "newFITSfile"


-------------------------------
--
-- SESSION
--

do -- initialise
  controls: reset()   
  controls: load()      -- inititalise from saved settings
end


-- start a new observation, by saving metadata from the old one
function _M.new()
  saveSession()  
  controls: reset()
  stacking: clear()
  workflows.main: clear "output"
end


-- shut down the session on application close
function _M.close()
  saveSession()
  controls: save()
  _log "closed"
end

-------------------------------
--
-- UPDATE / DRAW
--

function _M.update(dt)
  
  GUI.update(dt, workflows.main.output)
  
  local frame = newFITSfile: pop()
    
  if frame then  -- process new frame

    prestack(workflows, frame)                         -- PRESTACK processing
    
    stacking.new(workflows, frame)                     -- STACKING

    if frame.first then loadSession() end             -- load relevant session info
  
  end

  -- if new frame, or we're looking at the main display
  -- and things have changed, then apply latest processing
  
  local update = frame or controls.page == "main" and (controls.anyChanges() and not controls.rotate.changed)
  
  if update then poststack(workflows) end                      -- POSTSTACK processing

end


function _M.draw()
  GUI.draw(workflows.main.output)
end


return _M

-----
