--
-- workflow.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.21",
    AUTHOR = "AK Booer",
    DESCRIPTION = "workflow utilities",
  }

-- 2024.10.29  Version 0
-- 2024.12.16  move workflow() utility to here

-- 2025.01.23  refactor workflow methods
-- 2025.01.24  newWorkflow() method, remove external buffer() method
-- 2025.01.28  separate module from util
-- 2025.01.20  add saveInput()
-- 2025.02.06  add renderTo()
-- 2025.03.08  added stats()
-- 2025.03.12  use class methods, shared betwen instances
-- 2025.03.13  added clear()
-- 2025.03.16  added save()
-- 2025.03.21  added buffer(), to get names workflow buffer (or not)


local _log = require "logger" (_M)

local prestack    = require "prestack"

local badpixel    = require "shaders.badpixel"
local debayer     = require "shaders.debayer"
local starfinder  = require "shaders.starfinder"
local stacker     = require "shaders.stacker"
local background  = require "shaders.background"
local colour      = require "shaders.colour"
local filter      = require "shaders.filter"
local stats       = require "shaders.stats"
local stretcher   = require "shaders.stretcher"


local love = _G.love
local lg = love.graphics


-------------------------
--
-- IMAGE BUFFER
--

local function getImageInfo(image)
  local width, height = image:getDimensions()
  local dpiscale= image: getDPIScale()
  local imageFormat = image:getFormat()
  return width, height, imageFormat, dpiscale
end
  
-- ensure buffer, if it exists, is the right size for image
-- otherwise create and return one that matches
-- settings, if present, overrides selected image settings
local function buffer(image, buffer, settings, comment)
  local w1, h1, f1, d1 = getImageInfo(image)
  settings = setmetatable(settings or {}, {__index = {format = f1, dpiscale = d1}})
  if buffer then
    local w2, h2 = getImageInfo(buffer)
    if w2 ~= w1 or h2 ~= h1 then
      buffer: release()
      buffer = nil
    end
  end
  if not buffer then _log ("new buffer [%dx%d %s] %s" % {w1,h1, settings.format, comment or ''}) end
  return buffer or lg.newCanvas(w1, h1, settings)
end


-------------------------
--
-- WORKFLOW - toggle between two buffers
--            inspired by the code in Moonshine
--

-- swap buffers to undo previous operation (having used buffer only once)
local function undo(self)
  self.input, self.output = self.output, self.input       -- toggle buffer input/output
end
 
-- make a new copy of a workflow buffer
local function copy(self, source, dest, settings) 
  assert(type(source) == "string")
  assert(type(dest) == "string")
  local saved = buffer(self[source], self[dest], settings, "%s.copy %s to %s" % {self.name, source, dest})
  self[dest] = saved
  lg.setBlendMode("replace", "premultiplied")
  saved: renderTo(lg.draw, self[source])
  lg.setBlendMode "alpha"
  return saved
end

-- save current output to "dest"
local function save(self, dest)
  copy(self, "output", dest)
end

-- getDimensions()
local function getDimensions(self)
  return self.input: getDimensions()
end
  
-- stats()
local function mystats(self, ...)
  return stats.stats(self.output, ...)
end
 
-- stats()
local function statsTexel(self, ...)
  return stats.statsTexel(self.output, ...)
end
 
-- toggle input/output workflow between two buffers,
-- matched and initialised to input canvas type
local function work(self, controls)
  self.input, self.output = self.output, self.input       -- toggle buffer input/output
  local input = self.canvas or self.input                      -- ... and use input canvas as first input
  self.canvas = nil                                            -- ... but only once, unless newInput() called
  return input, self.output, controls or self.controls    -- use existing controls if not otherwise specified
end

-- renderTo()
local function renderTo(self, fct, ...)
  local input, output = work(self)
  output: renderTo(fct, input, ...)
end

-- set new input for workflow
local function newInput(self, input, settings, controls)
  input = (type(input) == "string") and self[input] or input
  self.input = buffer(input, self.input, settings, self.name .. " input")
  self.output = buffer(input, self.output, settings, self.name .. " output")
  self.canvas = input
  self.controls = controls or self.controls
end

-- clear buffer
local function clear(self, name, r, g, b, a)
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  self[name]: renderTo(lg.clear, r,g,b,a)
end

-- get buffer by name, creating if necessary, or return supplied canvas
local function byName(self, buf)
  if type(buf) == "string" then
    buf = buffer(self.output, self[buf])   -- ensure that it exists
  end
  return buf
end

function _M.new(ctrl, name)
  local W = {
    name = name or "workflow",
    input = nil,        -- the two working buffers...
    output = nil,       -- .. yet to be initialised
    canvas = nil,       -- temporary input
    
    controls = ctrl,    -- saved default control settings
    
    badpixel    = badpixel,
    debayer     = debayer,
    prestack    = prestack,
    starfinder  = starfinder,
    stacker     = stacker,
    stretch     = stretcher.stretch,
    
    normalise   = stats.normalise,
    statsTexel  = statsTexel,
    stats       = mystats,
    
    background  = background.remove,
    
    clear       = clear,
    buffer      = name,
    scnr        = colour.scnr,
    synthL      = colour.synthL,
    balance     = colour.balance,
    rgb2hsl     = colour.rgb2hsl,
    hsl2rgb     = colour.hsl2rgb,
    satboost    = colour.satboost,
    tint        = colour.balance_R_GB,
    selector    = colour.selector,
    lrgb        = colour.lrgb,
    invert      = colour.invert,
    
    boxblur     = filter.boxblur,
    gaussian    = filter.gaussian,
    fastgaussian = filter.fastgaussian,
    tnr         = filter.tnr,         -- 'Tony's Noise Reduction'   (smoothing)
    apf         = filter.apf,         -- 'Absolute Point of Focus'  (sharpening)
    
    -- local methods
    
    undo = undo,
    copy = copy,
    save = save,
    buffer = byName,
    renderTo = renderTo,
    newInput = newInput,
    getDimensions = getDimensions,
    
  }

  return setmetatable (W, {__call = work})

end


return _M

-----
