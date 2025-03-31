--
-- session.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.22",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Session manager",
  }

-- 2024.11.21  Version 0
-- 2024.11.27  load DSO catalogues
-- 2024.12.02  separate DSO module
-- 2024.12.08  correct object metadata handling

-- 2025.02.18  add lat, long, sun_time
-- 2025.02.21  initialise on load, remove load() function


local _log = require "logger" (_M)

local json = require "lib.json"
local utils = require "utils"

local observer        = require "observer"
local channelOptions  = require "shaders.colour"  .channelOptions
local gammaOptions    = require "shaders.stretcher" .gammaOptions
local obsessions    = require "databases.obsessions"

local saveSession = obsessions.saveSession
local loadSession = obsessions.loadSession

local telescopes       = require "databases" .telescopes

local love = _G.love

local newFITSfile = love.thread.getChannel "newFITSfile"

local pager = love.thread.getChannel "pager"   -- a way for non-GUI components to change display page

--_M.dsos = dso.dsos


-------------------------------
--
-- SESSION CONTROLS - Data Model
--

local controls = {    -- most of these are SUIT widgets
    
    -- display page modes
    page = "main",
    subpage = '',
    
    -- adjustments panel
    
    channelOptions = channelOptions,
    background = {default = 0.5},
    brightness = {default = 0.5},
    
    gammaOptions = gammaOptions,
    stretch = {default = 1, max = 2},
    gradient = {default = 1, min = -1, max = 3},
    
    colourOptions = {"RGB Colour", "Hubble", "Wager"},
    saturation  = {default = 0.5},
    tint        = {default = 0.5},
  
    enhanceOptions = {"Enhance", "TNR", "Bilateral", "FABADA", "———————", "Unsharp", "APF",  "Decon"},
    denoise = {default = 0},
    sharpen = {default = 0},
    
    -- screen appearance
    X = 0,    -- these offsets are in the image coordinate system (not the screen)
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
        signature = {text = "made with Lövell"},
        latitude  = {text = '51.5'},      -- defaults are approximation to Greenwich...
        longitude = {text = '0'},         -- it's actually on the O2 arena
      },
    
    -- workflow
    
    workflow = {
        badpixel  = {checked = true, text = "bad pixel removal"},
        badratio  = {value = 2.5, min = 1, max = 5 },
        
        debayer   = {checked = false, text = "force debayer"},
        bayerpat  = {text = ''},
        
        maxstar   = {value = 100, min = 0,  max = 200},
        keystar   = {value =  50,  min = 5, max = 100},         -- window to search for star peaks
        offset    = {value = 150,  min = 0, max = 300},         -- limit to between-frame shifts
        
        smooth    = {value = 15},      -- background smoothness (# gaussian taps)
        sharp1    = {value = 5,  min = 3, max = 7},      -- apf levels
        sharp2    = {value = 17, min = 9, max = 21},
        
        Rweight   = {value = 1, min = .5, max = 1.5},       -- pre-weights for colour channels
        Gweight   = {value = 1, min = .5, max = 1.5},
        Bweight   = {value = 1, min = .5, max = 1.5},
      },
    
    anyChanges = function() end -- replaced in mainGUI by suit.anyActive()
  }


-------------------------------
--
-- INIT / RESET
--

do -- inititalise from saved settings
  local s = controls.settings
  local f = (json.read "settings.json") or controls.settings   -- use defaults if file read fails
  for n,v in pairs(f) do s[n] = v end
  _log "settings loaded"
end

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

local stack
local screenImage


local function newObservation()
  saveSession(stack, controls)
  controls.reset()        -- start with new default values for processing options
  stack = nil
  screenImage = nil
  observer.new()          -- reset the observer
end

-- start a new observation, by saving metadata from the old one
function _M.new()
end


function _M.update()
  
  local newpage = pager: pop()
  if newpage then 
    controls.page, controls.subpage = newpage: match"(%w+)%W*(%w*)"
  end
  
  local frame = newFITSfile: pop()
  
  -- if a new frame arrives, then stack it
  
  if frame then
    
    if frame.first then newObservation() end

    stack = observer.newSub(frame, controls)

    if frame.first then 
      local info = loadSession(stack, controls)          -- load relevant session info
--      _M.ID = info.session.ID
      controls.focal_len.text = telescopes: focal_length(controls.telescope.text) or controls.focal_len.text

      local zoom = math.max(utils.calcScreenRatios(stack.image))     -- full screen image
      controls.zoom.value = math.min(1, zoom)     -- limit initial showing to 1:1 with screen dimensions
    end
  end

  -- if new frame, or we're looking at the main display and things have changed, then apply latest processing
  
  if frame 
    or controls.page == "main" and (controls.anyChanges() and not controls.rotate.changed) then
      screenImage = observer.postprocess(stack)   -- poststack processing
  end

end


function _M.close()
  saveSession(stack, controls)
  json.write("settings.json", controls.settings)
  _log "settings saved"
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
