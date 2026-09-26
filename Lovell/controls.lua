--
-- controls.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.09.25",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Control settings: model, view, control (MVC)",
  }

local _log = require "logger" (_M)

-- 2024.11.21  Version 0

-- 2025.02.18  add lat, long, sun_time
-- 2025.02.21  initialise on load, remove load() function
-- 2025.05.08  add default stacking option to settings
-- 2025.07.13  add Astrometry API key for plate solving

-- 2026.05.11  add Auto to Bayer pattern options
-- 2026.05.15  add SCNR checkbox, and split from Session module
-- 2026.05.24  add id field to sliders, and number formatting to sliders
-- 2026.05.26  move reset() methods to here from Session module
-- 2026.06.12  add load() and save() 
-- 2026.06.17  add synthetic luminance control group
-- 2026.06.27  add plugin module
-- 2026.09.25  add settings.process_sequence for plugin display and processing


local json = require "lib.json"

json.float ="%0.3"

local suitable = require "guillaume.suitable"     -- for access to reset flag
local plugins  = require "plugins"                -- load all the plugins

local gammaOptions    = require "shaders.stretcher" .gammaOptions
local stackOptions    = require "shaders.stacker"   .stackOptions
local BayerOptions    = require "shaders.debayer"   .BayerOptions
    
local paletteOptions  = {"RGB", "Hubble", '-––––––––––', "-SHO", "-HOO", "-HSO", 
                          id = "Palette: ", selected = 1, default = 1, size = {100, 20}}

local pager = love.thread.getChannel "pager"   -- a way for non-GUI components to change display page


local hrule = ('–'): rep(25)    -- for menu dividers

-------------------------------
--
-- UTILITIES
--

-- add get() method to option sliders (returns lower-case name of selected option)
do
  local function get(self) return self[self.selected]: lower() end
  gammaOptions.get    = get
  stackOptions.get    = get
  BayerOptions.get    = get
  paletteOptions.get  = get
end

-- reset() method for SUITABLE widgets and control clusters
local function reset (self)
  suitable.reset = true               -- flag the change
  for name in pairs(self) do
    local x = self[name]
    if type(x) == "table" then
      local dtype = type(x.default)
      if dtype == "string" then                           -- label
        x.text = x.default or x.text or ''
      elseif x.selected then                              -- option list
        x.selected = x.default or x.selected or 1
      elseif dtype == "number" then                       -- slider
        x.value = x.default or x.value or 0
      elseif dtype == "boolean" then                      -- checkbox
        x.checked = x.default or x.value or false
      end
    end
  end
end

local function control_cluster(spec)    -- factory method for groups of controls (with reset function)
  spec.reset = reset
  return spec
end


-------------------------------
--
-- SESSION CONTROLS - Data Model
--

local controls      -- most of these are SUIT widgets, or PLUGINS (containing SUIT widgets)

controls = {
    
    page = "main",    -- display page 
      
    gammaOptions = gammaOptions,
    
    palette = paletteOptions, 
     
    stackOptions = stackOptions,
    
    reject = {},      -- list of rejected frame filenames (TODO: move to frame?)
    
    -- DISPLAY, screen appearance
    
    X = 0,    -- these offsets are in the image coordinate system (not the screen)
    Y = 0,
    
    zoom      = {default = 0.3, value = 0.3, max = 3},
    rotate    = {default = 0, value = 0, min = -360, max = 360},
    flipUD    = {checked = false, text = "flip U/D"},
    flipLR    = {checked = false, text = "flip L/R"},
    eyepiece  = {checked = true},                       -- start in eyepiece mode 
  
    pin_controls = {checked = false},
    pin_info = {checked = false},
    
    -- info panel
    
    object = {default = ''},
    
    -- settings page
    
    other = {"telescope", "focal_len", "reducer", "pixelsize", "ses_notes", "obs_notes"},
    
    telescope = {text = '', default = '', cursor = 1},      -- per observation (could have more than one scope in a session)
    focal_len = {text = '', default = '', cursor = 1},
    reducer   = {text = '', default = '', cursor = 1},
    pixelsize = {text = '', default = '', cursor = 1},
    
    ses_notes = {text = '', default = '', cursor = 1},
    obs_notes = {text = '', default = '', cursor = 1},
    
    -- settings file
    
    settings =  {
        retainControls =  false,
        signature = {text = "made with Lövell"},
        stacking  = 1,                    -- default stacking option
        latitude  = {text = '51.5'},      -- defaults are approximation to Greenwich...
        longitude = {text = '0'},         -- it's actually on the O2 arena
        apikey    = {text = ''},
      
      },
        
    -- PRESTACK
  
    prestack = control_cluster {
      id = "Prestack",
      bayopt = {size = {100, 20}},
      do_dark   = {checked = true, default = true, text = "dark calibration"},
      do_flat   = {checked = true, default = true, text = "flat calibration"},
      badpixel  = {checked = true, default = true, text = "bad pixel removal"},
      badratio  = {id = "ratio", value = 2.5, default = 2.5, min = 1, max = 5, format = "%.1f", style = "inline" },
      bayer_opt = BayerOptions,
      
      draw = function (self, suit)  
        local sl = suit.layout
        local Hb = 25
        if suit: Button("View Masters...", sl:row(200, Hb)) .hit then 
          pager: push "database, calibration" 
        end 
        suit: Choosable(self.bayer_opt, self.bayopt, sl:row(200, Hb))   -- narrow menu because short option names
        
        suit: Checkbox(self.do_dark, sl:row (200, 20))
        suit: Checkbox(self.do_flat, sl:row ())
        
        suit: Checkbox(self.badpixel, sl:row())
        suit: Slideable(self.badratio, sl:row (200, 15))
      end,

    },
      
    -- STACKING
    
    stacking = control_cluster {
      id = "Stack",
      align = {align = "left"},
      stack_opt = stackOptions,
      
      -- max # stars to find, peak search radius, limit to between-frame shifts
      maxstar = {id = "#stars", value =  50, default =   50, min = 10, max = 100, format = "%3d", style = "inline"},
      radius  = {id = "radius", value =  50, default =   50, min = 10, max = 100, format = "%3d", style = "inline"},
      offset  = {id = "offset", value = 150, default =  150, min = 30, max = 300, format = "%3d", style = "inline"},
      
      draw = function(self, suit)
        local sl = suit.layout
        local Hb = 25
        local W = 200
        
        if suit: Button("View Stack...", sl:row(W, Hb)) .hit then 
          pager: push "stack" 
        end 
        suit: Choosable(self.stack_opt, sl:row())  
        
        suit: Label("Alignment limits", self.align, sl:row(W, 20))
        suit: Slideable(self.maxstar, sl:row(W, 10))
        suit: Slideable(self.radius, sl:row())
        suit: Slideable(self.offset, sl:row())
       end,
    },
  
  }


-------------------------------
--
-- METHODS
--

--function controls.other: reset() 
--  for _, name in ipairs(self) do
--    local ctrl = controls[name]
--    ctrl.text = ctrl.default      -- these are all text values
--  end
--end

function controls: reset()
  -- TODO: reset LRGB, Gamma, etc. to defaults??
  if not self.settings.retainControls then
    plugins: reset()
  end
  self.object.text = ''    -- forget the last object
end

function controls: load()
  local f, err = json.read "settings.json" or controls.settings
  controls.settings.process_sequence = plugins.process_sequence    -- may be changed in settings file below
  if f then
    for n,v in pairs(f) do controls.settings[n] = v end
  end
  plugins.process_sequence: set(controls.settings.process_sequence)
  stackOptions.selected = controls.settings.stacking or 1
  _log (f and "settings loaded" or "failed to load: ", err)
  
  for name, plugin in pairs(plugins) do
    controls[name] = control_cluster (plugin)
  end
  
end

function controls: save()
  controls.settings.process_sequence = plugins.process_sequence   -- save the latest workflow
  local ok, err = json.write("settings.json", controls.settings)
  _log (ok and "settings saved" or "failed to save: ", err)
end

return controls

-----

