--
-- session.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Session manager",
  }

-- 2024.11.21  Version 0
--2024.11.27  load DSO catalogues


local _log = require "logger" (_M)

local CSV = require "lib.csv"
local stacker = require "stacker"
local poststack = require "poststack"
local channelOptions  = require "shaders.colour"  .channelOptions
local gammaOptions    = require "shaders.stretcher" .gammaOptions

local love = _G.love
local lf = love.filesystem

local newFITSfile = love.thread.getChannel "newFITSfile"

-- 2024.11.21  Version 0


local controls = {
    Nstack = 0,
    
    x = 0, y = 0,               -- image translation
    zoom = 0.3,                 -- image scale
    angle = 0,                  -- image rotation    
    
    channel = 1,
    channelOptions = channelOptions,
    background = {value = 0.5},
    brightness = {value = 0.5},
    
    gamma = 5,
    gammaOptions = gammaOptions,
    stretch = {value = 0.3, max = 2},
    gradient = {value = 1, min = -1, max = 3},
    
    saturation = {value = 2.5, min = 0, max = 5},
    red   = {value = 0.5},
  
    anyChanges = function() return true end -- replaced in mainGUI by suit.anyActive()
  }

function controls.reset()
  controls.Nstack = 0
  controls.background.value = 0.5      -- initial guess at black point
  controls.brightness.value = 0.5
  controls.stretch.value = 0.3
  controls.gradient.value = 1
end

_M.controls = controls    -- export the controls, for GUI, processing, etc...

_M.settings = {
    telescope = {text = ''},
    obs_notes = {text = ''},
    ses_notes = {text = ''},
  }

------------------------------

_M.dsos = {}

local function one_dp(x)
  x = tonumber(x) or 0
  return x - x % 0.1
end

-- convert decimal degrees to DDD MM SS
local floor = math.floor
local function deg_to_dms(deg)
  deg = tonumber(deg)
  local sign = 1
  if deg < 0 then
    sign = -1
    deg = -deg
  end
  local d, m, s
  d = floor(deg)
  m = 60 * (deg - d)
  s = floor(60 * (m % 1) + 0.5)
  m = floor(m)
  return sign * d, m, s
end

local function load_dsos()
  local dsos = _M.dsos
  local names = lf.getDirectoryItems "dsos"
  for _, filename in ipairs(names or {}) do
    if filename: match "%.csv$" then
      local catalogue = CSV.read("dsos/" .. filename)
      for i = 2, #catalogue do                           -- skip over title line
        local dso = catalogue[i]
--        _log (i, table.concat(dso, ' '))
        -- Name, RA, Dec, Con, OT, Mag, Diam, Other  
        dso[1] = dso[1]
        dso[2] =  "%02dh %02d %02d" % {deg_to_dms(dso[2] / 15)}    -- RA
        dso[3] = "%+02dº %02d %02d" % {deg_to_dms(dso[3])}         -- DEC
        dso[6] = one_dp(dso[6])                                    -- Mag
        dso[7] = one_dp(dso[7])                                    -- Diam
        dso[8] = dso[8] or ''
        dsos[#dsos+1] = dso
      end
    end
  end
  _log ("# DSOs %d" % #dsos)
end


------------------------------
local stack
local screenImage


-- start a new observation
local function newObservation()
      stack = nil
      screenImage = nil
      stacker.newStack(controls)
end

function _M.load()
  load_dsos()  
end


function _M.update()
  
  local newFile = newFITSfile: pop()
  
  if newFile then
    if newFile.subNumber == 1 then
      newObservation(controls)
    end
    stack = stacker.newSub(newFile, controls)
  end
 
 if newFile or controls.anyChanges() then
    screenImage = poststack(stack, controls)
  end

end

function _M.stack()
  return stack
end

function _M.image()
  return stack and screenImage
end

return _M

-----
