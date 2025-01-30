--
-- workflow.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.28",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry utilities",
  }

-- 2024.10.29  Version 0
-- 2024.12.16  move workflow() utility to here

-- 2025.01.23  refactor workflow methods
-- 2025.01.24  newWorkflow() method, remove external buffer() method
-- 2025.01.28  separate module from util


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

function _M.getImageInfo(image)
  local width, height = image:getDimensions()
  local dpiscale= image: getDPIScale()
  local imageFormat = image:getFormat()
  return width, height, imageFormat, dpiscale
end
  
-- ensure buffer, if it exists, is the right size for image
-- otherwise create and return one that matches
-- settings, if present, overrides selected image settings
local function buffer(image, buffer, settings, comment)
  local w1, h1, f1, d1 = _M.getImageInfo(image)
  settings = setmetatable(settings or {}, {__index = {format = f1, dpiscale = d1}})
  if buffer then
    local w2, h2 = _M.getImageInfo(buffer)
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

function _M.new(ctrl)
  local W = {
    input = nil,       -- the two working buffers...
    output = nil,      -- .. yet to be initialised
    
    controls = ctrl,   -- saved default control settings
    
    badpixel    = badpixel,
    debayer     = debayer,
    prestack    = prestack,
    starfinder  = starfinder,
    stacker     = stacker,
    stretch     = stretcher.stretch,
    
    normalise   = stats.normalise,
    background  = background.remove,
    
    scnr        = colour.scnr,
    synthL      = colour.synthL,
    rgb2hsl     = colour.rgb2hsl,
    hsl2rgb     = colour.hsl2rgb,
    tint        = colour.balance_R_GB,
    selector    = colour.selector,
    lrgb        = colour.lrgb,
    
    gaussian    = filter.gaussian,
    tnr         = filter.tnr,         -- 'Tony's Noise Reduction'   (smoothing)
    apf         = filter.apf,         -- 'Absolute Point of Focus'  )sharpening)
  }
  
  local canvas

  -- swap buffers to undo previous operation (having used buffer only once)
  function W:undo()
    self.input, self.output = self.output, self.input       -- toggle buffer input/output
  end
   
  -- toggle input/output workflow between two buffers,
  -- matched and initialised to input canvas type
  local function work(self, controls)
    self.input, self.output = self.output, self.input       -- toggle buffer input/output
    local input = canvas or self.input                      -- ... and use input canvas as first input
    canvas = nil                                            -- ... but only once, unless newInput() called
    return input, self.output, controls or self.controls    -- use existing controls if not otherwise specified
  end
 
   -- set new input for workflow
  function W:newInput(input, settings, controls)
    self.input = buffer(input, self.input, settings, "workflow 1")
    self.output = buffer(input, self.output, settings, "workflow 2")
    canvas = input
    self.controls = controls or self.controls
  end
 
  -- make a new copy of the latest workflow output buffer
  function W:saveOutput(name, settings) 
    assert(type(name) == "string")
    local saved = buffer(self.output, self[name], settings, "workflow.saveOutput: " .. name)
    self[name] = saved
    lg.setBlendMode("replace", "premultiplied")
    saved:renderTo(lg.draw, self.output)
    lg.setBlendMode "alpha"
    return saved
  end

  if canvas then W:newInput(canvas) end
  return setmetatable (W, {__call = work})

end


return _M

-----
