--
-- utils.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.10.29",
    AUTHOR = "AK Booer",
    DESCRIPTION = "sundry utilities",
  }

-- 2024.10.29  Version 0
-- 2024.12.16  move workflow() utility to here


local _log = require "logger" (_M)

local lt = require "love.timer"
local lg = require "love.graphics"

-- newTimer, returns a function which gives time (in ms) since its creation
-- returned function can be called multiple times, for cumulative timings
--
-- local elapsed = timer()
-- do something end
-- local t = elapsed()
--
-- optional formatting parameter for string return
-- optional parameters for formatting AFTER the time
function _M.newTimer()
  local gt = lt.getTime
  local t = gt()
  return function(fmt, ...) 
    local dt = 1000 * (gt() - t) 
    return fmt and fmt % {dt, ...} or dt
  end
end

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
function _M.buffer(image, buffer, settings, comment)
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

_M.workflow = {
  input = nil,            -- the two working buffers...
  output = nil,           -- .. yet to be initialised
  controls = nil          -- saved default control settings
  }

local W = _M.workflow

-- toggle input/output workflow between two buffers,
-- matched and initialised to input canvas type
function W:new(canvas, ctrl, settings)
  local special
  if type(canvas) == "table" then
    special = canvas                  -- one-off override of controls
  elseif canvas then                  -- create buffers first time around,,,
    W.input  = _M.buffer(canvas, W.input, settings, "workflow")
    W.output  = _M.buffer(canvas, W.output, settings, "workflow")
    W.controls = ctrl or W.controls       -- use existing controls if not otherwise specified
    return canvas, W.output, W.controls   -- ... and use input canvas as first input
  end
  W.input, W.output = W.output, W.input  -- toggle buffer input/output
  return W.input, W.output, special or W.controls
end

-- make a new copy of the latest workflow output buffer
function W.saveOutput(saved) 
  saved = _M.buffer(W.output, saved, nil, "workflow.saveOutput")    -- create new canvas, like the output buffer, if none given
  lg.setBlendMode("replace", "premultiplied")
  saved:renderTo(lg.draw, W.output)
  lg.setBlendMode "alpha"
  return saved
end

setmetatable (W, {__call = W.new})


-------------------------
--
-- SCREEN 
--

-- get dimensions of screen or canvas
function _M.getDimensions(screen)
  if screen then 
    return screen:getDimensions()
  else
    return lg.getDimensions()
  end
end

-- calculate vertical and horizontal ratios of image and screen dimensions
function _M.calcScreenRatios(image, screen)
  if not image then return 1, 1 end
  local w,h = _M.getDimensions(screen)
  local iw,ih = image:getDimensions()
  return h / ih, w / iw
end


-- Oculus draw the eyepiece on the screen
_M.Oculus = {}

local Oculus = _M.Oculus

function Oculus.radius()
  local margin = 30  -- default footer size
  local w, h = _M.getDimensions()             -- screen size
  return math.min(w, h) / 2 - margin - 10, w, h
end

function Oculus.stencil()
  local c = 0.09            -- background within the oculus
  lg.setColor(c,c,c,1)
  lg.setColorMask(true, true, true, true)
  local radius, w, h = Oculus.radius()
  lg.circle("fill", w/2, h/2, radius)
  lg.setColor(1,1,1,1)
end

function Oculus.draw()
  lg.stencil(Oculus.stencil, "replace", 1)
  lg.setStencilTest("greater", 0)
end


return _M

-----
