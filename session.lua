--
-- session.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.08",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Session manager",
  }

-- 2024.11.21  Version 0
-- 2024.11.27  load DSO catalogues
-- 2024.12.02  separate DSO module
-- 2024.12.08  correct object metadata handling


local _log = require "logger" (_M)

local dso = require "lib.dso"
local json = require "lib.json"

local observer        = require "observer"
local channelOptions  = require "shaders.colour"  .channelOptions
local gammaOptions    = require "shaders.stretcher" .gammaOptions

local love = _G.love
local lf = love.filesystem

local newFITSfile = love.thread.getChannel "newFITSfile"

local empty = _G.READONLY {}

_M.dsos = dso.dsos


-------------------------------
--
-- SESSION - Data Model
--

local controls = {    -- most of these are SUIT widgets
    Nstack = 0,
    
    -- hidden (no displayed control)
    zoom = {value = 1},
    
    -- adjustments panel
    
    channel = 1,
    channelOptions = channelOptions,
    background = {value = 0.5},
    brightness = {value = 0.5},
    
    gamma = 5,
    gammaOptions = gammaOptions,
    stretch = {value = 0.3, max = 2},
    gradient = {value = 1, min = -1, max = 3},
    
    saturation  = {value = 2.5, min = 0, max = 5},
    tint        = {value = 0.5},
  
    denoise = {value = 0.25},
    sharpen = {value = 0},
  
    -- info panel
    
    object = {text = ''},
    flipUD = {checked = false, text = "flip U/D"},
    flipLR = {checked = false, text = "flip L/R"},
    
    -- settings page
    
    telescope = {text = ''},      -- per observation (could have more than one scope in a session)
    ses_notes = {text = ''},
    obs_notes = {text = ''},
    
    anyChanges = function() end -- replaced in mainGUI by suit.anyActive()
  }

function controls.reset()
  controls.Nstack = 0
  controls.background.value = 0.5      -- initial guess at black point
  controls.brightness.value = 0.5
  controls.stretch.value = 0.3
  controls.gradient.value = 1
end

_M.controls = controls    -- export the controls, for GUI, processing, etc...

-------------------------------
--
-- SESSION - specific data
--
local sessionMetaIndex = {session = {ID = ''}}
local sessionMeta = {__index = sessionMetaIndex}    -- session file becomes assigned to __index table during load
local settings = setmetatable ({}, sessionMeta)

------------------------------

local stack
local screenImage

local function sessionID(epoch)
  return os.date("%Y%m%d", epoch)
end

-- reset session info
local function clear_settings()
  controls.object.text = ''
  controls.ses_notes.text =  ''
  controls.obs_notes.text = ''
  sessionMetaIndex.session.ID = ''
  sessionMetaIndex.observations = nil
  sessionMeta.__index = sessionMetaIndex
  _M.ID = ''
end

local sess_path = "sessions/%s.json"    -- format for session metadata filename

-- construct session and observation IDs and info
local function getInfo(stack)
  local sesID = sessionID(stack.epoch)            -- use observation date as session ID
  local obsID = stack.folder                      -- use observation folder as observation ID
  _M.ID = sesID                                   -- update session ID in module
  local path = sess_path % sesID                  -- create path for meta file
  local info = sessionMeta.__index                -- make it the current session
  info.session.ID = sesID                         -- ensure session ID exists
  return obsID, path, info
end

local function non_blank(text)
  return #text > 0 and text or nil
end

-------------------------------
--
-- SAVE/LOAD SESSION 
--

local function saveSession(stack)
  if not stack then return end
  local obsID, path, info = getInfo(stack)
  
  -- unpdate metadata from controls
  info.session.notes = non_blank(controls.ses_notes.text)
  local obs = info.observations[obsID or '']
  obs.object = non_blank(controls.object.text)
  controls.object.cursor = 1                  -- put the cursor at the start (looks better)
  obs.notes = non_blank(controls.obs_notes.text)
  obs.flipUD = controls.flipUD.checked or nil
  obs.flipLR = controls.flipLR.checked or nil
  obs.telescope = non_blank(controls.telescope.text)
  info.observations[obsID] = obs
  
  -- write file
  local f = lf.newFile(path, 'w')
  _log ("saving " .. path)  
  info = json.encode(info)
  f: write(info)
  f: close()
  if _M.ID < sessionID() then    -- clear the settings if NOT the current session
    clear_settings()
  end
end


local function loadSession(stack)
  if not stack then return end
  local obsID, path, info = getInfo(stack)
  
  -- reaed file
  local f = lf.newFile(path, 'r')
  if f then 
    _log ("loading " .. path)  
    local Jinfo = f: read()
    f: close()
    info = json.decode(Jinfo)
  end
  
  -- uodate controls from metadata
  local obs = info.observations or {}
  local thisObs = obs[obsID] or {}
  obs[obsID]= thisObs
  info.observations = obs
  
--  _log(pretty {loadSessionInfo = info})
  controls.object.text    = stack.object or thisObs.object or ''
  controls.telescope.text = stack.telescope or thisObs.telescope or ''
  controls.ses_notes.text = info.session.notes or ''
  controls.obs_notes.text = thisObs.notes or ''
  controls.flipUD.checked = thisObs.flipUD or false
  controls.flipLR.checked = thisObs.flipLR or false
  sessionMeta.__index = info
  
end

-------------------------------

-- start a new observation, by saving the old one
local function newObservation()
  saveSession(stack)
  stack = nil
  screenImage = nil
  observer.new(controls)      -- reset the observer
end

function _M.load()
  dso.load()  
end


function _M.update()
  
  local newFile = newFITSfile: pop()
  
  if newFile then
    local first_frame = newFile.subNumber == 1
    if first_frame then newObservation(controls) end
    
    stack = observer.newSub(newFile, controls)
    
    if first_frame then 
      loadSession(stack) 
     
     do  -- set zoom to fit screen  TODO: move this elsewhere
      local w,h = love.graphics.getDimensions()
      local iw,ih = stack.image:getDimensions()
      controls.zoom.value = math.min(h / ih, w / iw)    -- fit to screen
     end
    
    end         -- load relevant session info
  end
 
 if newFile or controls.anyChanges() then
    screenImage = observer.reprocess(stack, controls)
  end

end

function _M.close()
  saveSession(stack)
  _log "closed"
end

function _M.stack()
  return stack
end

function _M.image()
  return stack and screenImage
end


return _M

-----
