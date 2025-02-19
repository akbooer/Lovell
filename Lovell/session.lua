--
-- session.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Session manager",
  }

-- 2024.11.21  Version 0
-- 2024.11.27  load DSO catalogues
-- 2024.12.02  separate DSO module
-- 2024.12.08  correct object metadata handling

-- 2025.02.18  add lat, long, sun_time


local _log = require "logger" (_M)

local json = require "lib.json"
local utils = require "utils"

local observer        = require "observer"
local channelOptions  = require "shaders.colour"  .channelOptions
local gammaOptions    = require "shaders.stretcher" .gammaOptions
local databases       = require "databases"
local settings        = require "databases.settings"

local focal_length    = databases.telescopes.focal_length

local love = _G.love

local newFITSfile = love.thread.getChannel "newFITSfile"

--_M.dsos = dso.dsos


-------------------------------
--
-- SESSION - Data Model
--

local controls = {    -- most of these are SUIT widgets
    
    -- adjustments panel
    
    channelOptions = channelOptions,
    background = {default = 0.5},
    brightness = {default = 0.5},
    
    gammaOptions = gammaOptions,
    stretch = {default = 0.3, max = 2},
    gradient = {default = 1, min = -1, max = 3},
    
    colourOptions = {"RGB Colour", "Hubble", "Wager"},
    saturation  = {default = 2.5, min = 0, max = 5},
    tint        = {default = 0.5},
  
    enhanceOptions = {"Enhance", "TNR", "Bilateral", "FABADA", "———————", "Unsharp", "APF",  "Decon"},
    denoise = {default = 0.25},
    sharpen = {default = 0},
    
    -- screen appearance
    X = 0,
    Y = 0,
    zoom      = {default = 0.3, value = 0.3, max = 3},
    rotate    = {default = 0, value = 0, min = -360, max = 360},
    flipUD    = {checked = false, text = "flip U/D"},
    flipLR    = {checked = false, text = "flip L/R"},
    eyepiece  = {checked = true},                       -- start in eyepiece mode 
  
    pin_controls = {checked = false, text = nil},
    pin_info = {checked = false, text = nil},
    
    -- info panel
    
    object = {default = ''},
    
    -- settings page
    
    telescope = {default = ''},      -- per observation (could have more than one scope in a session)
    focal_len = {default = ''},
    pixelsize = {default = ''},
    
    ses_notes = {default = ''},
    obs_notes = {default = ''},
    
    -- settings file
    
    settings = {
        signature = {text = "made with Löve(ll)"},
        latitude  = {text = '51.5'},      -- defaults are approximation to Greenwich
        longitude = {text = '0'},
      },
    
    -- workflow
    
    workflow = {
        badpixel  = {checked = true, text = "bad pixel removal"},
        badratio  = {value = 2.0, min = 1, max = 4 },
        
        debayer   = {checked = false, text = "force debayer"},
        bayerpat  = {text = ''},
        
        maxstar   = {value = 100, min = 0,  max = 500},
        keystar   = {value = 20,  min = 5,  max = 50},         -- window to search for star peaks
        offset    = {value = 30,  min = 0,  max = 150},        -- limit to between-frame shifts
        
        smooth    = {value = 15},      -- background smoothness (# gaussian taps)
        sharp1    = {value = 5,  min = 3, max = 7},      -- apf levels
        sharp2    = {value = 17, min = 9, max = 21},
        
        Rweight   = {value = .5},
        Gweight   = {value = .5},
        Bweight   = {value = .5},
      },
    
    anyChanges = function() end -- replaced in mainGUI by suit.anyActive()
  }

-- set a control to a given value, or its default, or its current value
function controls.set(name, value)
  local x = controls[name]
  if x.text or type(x.default) == "string" then        -- label
    x.text = value or x.default or x.text or ''        -- unchanged if no given value or default
  else                                                  -- slider
    x.value = value or x.default or x.value or 0
  end
end

-- reset a control, or a list of controls, to their default
function controls.reset(ctrl)
  -- TOS: reset LRGB, Gamma, etc. to defaults?
  ctrl = ctrl or {"background", "brightness", "stretch", "gradient", 
                  "saturation", "tint", "denoise", "sharpen", "object"}
  if type(ctrl) == "table" then
    for _, name in ipairs(ctrl) do
      controls.set(name)                -- return to default values
    end
  else
    controls.set(ctrl)      -- reset single control value
  end
end

_M.controls = controls    -- export the controls, for GUI, processing, etc...

do -- init settings
  controls.reset()    
  -- initialise other control values
  controls.reset {"telescope", "focal_len", "pixelsize", "ses_notes", "obs_notes"}
end

-------------------------------
--
-- SESSION - specific data
--
local sessionMetaIndex = {session = {ID = ''}}
local sessionMeta = {__index = sessionMetaIndex}    -- session file becomes assigned to __index table during load

------------------------------

local stack
local screenImage

local function sessionID(epoch)
  return os.date("%Y%m%d", epoch)
end

-- reset session info
local function clear_settings()
  controls.reset()
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
  obs.rotate = controls.rotate.value ~= 0 and controls.rotate.value or nil
  obs.telescope = non_blank(controls.telescope.text)
  info.observations[obsID] = obs
  
  -- write file
  json.write(path,  info)
  if _M.ID < sessionID() then    -- clear the settings if NOT the current session
    clear_settings()
  end
end


local function loadSession(stack)

  if not stack then return end

  local obsID, path, info = getInfo(stack)
  info = json.read(path) or info                  -- use metadata file if present
  
  -- uodate controls from metadata
  local obs = info.observations or {}
  local thisObs = obs[obsID] or {}
  obs[obsID]= thisObs
  info.observations = obs
  
--  _log(pretty {loadSessionInfo = info})
  local pix = stack.keywords.XPIXSZ
  if pix then
    local bin = stack.keywords.XBINNING or 1      -- scale pixel size by binning
    pix = pix * bin
  end
  pix = tostring(pix or '')
  
  
  local scope = stack.telescope or thisObs.telescope or ''
  
  controls.focal_len.text = databases.telescopes: focal_length(scope) or controls.focal_len.text

  controls.object.text    = stack.object or thisObs.object or ''
  controls.telescope.text = scope
  controls.pixelsize.text = pix
  controls.ses_notes.text = info.session.notes or ''
  controls.obs_notes.text = thisObs.notes or ''
  controls.flipUD.checked = thisObs.flipUD or false
  controls.flipLR.checked = thisObs.flipLR or false
  controls.rotate.value   = thisObs.rotate or 0
  controls.X, controls.Y = 0, 0
  sessionMeta.__index = info
  
end

-------------------------------

-- start a new observation, by saving metadata from the old one
local function newObservation()
  saveSession(stack)
  controls.reset()        -- start with new default values for processing options
  stack = nil
  screenImage = nil
  observer.new()          -- reset the observer
end


function _M.update()
  
  local frame = newFITSfile: pop()
  if frame then
    
    if frame.first then newObservation() end

    stack = observer.newSub(frame, controls)

    if frame.first then 
      loadSession(stack)          -- load relevant session info
      local zoom = math.max(utils.calcScreenRatios(stack.image))     -- full screen image
      controls.zoom.value = math.min(1, zoom)     -- limit initial showing to 1:1 with screen resolution
    end
  end

  if frame or (controls.anyChanges() and not controls.rotate.changed) then
    screenImage = observer.reprocess(stack)
  end

end

function _M.init()
  settings.load(controls)
end

function _M.close()
  saveSession(stack)
  settings.save(controls)
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
