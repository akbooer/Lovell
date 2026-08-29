--
-- workflow.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.08.03",
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
-- 2025.03.08  add stats()
-- 2025.03.12  use class methods, shared between instances
-- 2025.03.13  add clear()
-- 2025.03.16  add save()
-- 2025.03.21  add buffer(), to get names workflow buffer (or not)
-- 2025.04.04  restore blend mode after changing it in copy()
-- 2025.04.09  remove controls parameter and returns
-- 2025.04.14  add calibrate()
-- 2025.05.02  add dump() to snapshot current output to settings/ folder
-- 2025.05.05  add thumbnail()
-- 2025.05.07  change clear() alpha channel default to zero (for RGBL canvases)
-- 2025.05.08  add logistic function
-- 2025.05.11  add bw_points()

-- 2026.04.30  move thumbnail() here from colour module
-- 2026.05.01  add histogram() 
-- 2026.05.29  add combined temp_tint() for colour temperature and tint adjustment
-- 2026.06.02  remove old stats module
-- 2026.06.11  add prestack(), stack(), poststack()
-- 2026.06.27  add plugin module, replacing some filtering functions
-- 2026.07.02  add swap() to exchange buffers, remove workflow._call() returning buffers (use work() instead)
-- 2026.07.04  add shadeWith() to avoid Graphics Driver Pipeline Hazard (Write-After-Read Cached State Bug).
-- 2026.07.12  add renderToMipLevel() and getMipmapChain()
-- 2026.07.14  remove prestack() and poststack() (only used in one place)
-- 2026.07.16  replace stats package with (much) faster version
-- 2026.08.01  add get_balanced_chroma()
-- 2026.08.03  require .new {name = name, format = fmt}


local _log = require "logger" (_M)

local badpixel    = require "shaders.badpixel"
local debayer     = require "shaders.debayer"
local starfinder  = require "shaders.starfinder"
local background  = require "shaders.background"
local colour      = require "shaders.colour"
local kovesi      = require "shaders.kovesi"
local mipblur     = require "shaders.mipblur"
local stretcher   = require "shaders.stretcher"
local calibrator  = require "shaders.calibrator"

local plugins     = require "plugins"

local love = _G.love
local lg = love.graphics

local EMPTY = _G.READONLY {}
  
-------------------------
--
-- IMAGE BUFFER
--

local function getImageInfo(image)
  local width, height = image:getDimensions()
  local imageFormat = image:getFormat()
  local mipmapMode = image:typeOf "Canvas" and image:getMipmapMode() or "none"
  return width, height, imageFormat, mipmapMode
end
  
-- ensure buffer, if it exists, is the right size for image
-- otherwise create and return one that matches
-- settings, if present, overrides selected image settings of formnat and mipmaps only
local function buffer(image, buffer, settings, comment)
  local w1, h1, f1, m1 = getImageInfo(image)
  settings = settings or EMPTY
  local new_settings = {
      format = settings.format or f1, 
      dpiscale = 1, 
      mipmaps = settings.mipmaps or m1,
    }
  if buffer then
    local w2, h2 = getImageInfo(buffer)
    if w2 ~= w1 or h2 ~= h1 then
      buffer: release()
      buffer = nil
    end
  end
  if not buffer then 
    buffer = lg.newCanvas(w1, h1, new_settings)
    buffer: setWrap("clamp", "clamp")
    buffer: setFilter("linear", "linear")
--    buffer: setFilter("nearest", "nearest")
    local mode = buffer: getMipmapMode()
    local mip = mode ~= "none" and '(' .. mode ..')' or ''
    _log ("new buffer %s[%dx%d] %s %s" % {new_settings.format, w1,h1, mip, comment or ''})
  end 
  return buffer
end


-------------------------------
--
-- THUMBNAIL
--

local function thumbnail(workflow, image)
  image = image or workflow.output
  local fmt = "rgba16"
  local Wthumb = 700        -- thumbnail width, height scales to preserve aspect ratio
  local w,h = image:getDimensions()
  local scale = Wthumb / w
  local Hthumb = math.floor(scale * h)
  local thumb = lg.newCanvas(Wthumb, Hthumb, {dpiscale = 1, format = fmt})
  lg.setColor (1,1,1, 1)
  lg.setBlendMode ("replace", "premultiplied")
  thumb: renderTo(lg.clear, 0,0,0, 1)               -- set the alpha channel to unity...
  lg.setColorMask(true, true, true, false)          -- ...and don't overwrite that channel
  thumb: renderTo(lg.draw, image, 0,0, 0, scale, scale)
  lg.reset()
  _log("created thumbnail %s[%dx%d] from %s[%dx%d]" % {fmt, Wthumb, Hthumb, image:getFormat(), w,h})
  return thumb
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
  local saved = buffer(self[source], self[dest], settings, "%s.copy %s to %s" % {self.info.name, source, dest})
  self[dest] = saved
  local mode, alphamode = lg.getBlendMode()
  lg.setBlendMode("replace", "premultiplied")
  saved: renderTo(lg.draw, self[source])
  lg.setBlendMode(mode, alphamode)            -- restore blend mode
  return saved
end

-- save current output to "dest"
local function save(self, ...)
  copy(self, "output", ...)
end

local function swap(self, a, b)
  self[a], self[b] = self[b], self[a]
end

-- getDimensions()
local function getDimensions(self)
  return self.input: getDimensions()
end

-- get # channels
local function getChannelCount(self)
  local fmt = self.input: getFormat()
  local rgba = fmt: match"^%a+"
  return #rgba
end

-- dump an image to Lovell folder
local function dump(self, name)
  self: save "_dump"
  self._dump: renderTo(lg.draw, self.output)
  self._dump: newImageData() : encode ("png", (name or "dump") .. ".png")
  self._dump: release()
  self._dump = nil
end
  
-- set new input for workflow
local function newInput(self, input)
  input = (type(input) == "string") and self[input] or input
  local settings = {format = self.info.format}
  self.input = buffer(input, self.input, settings, self.info.name .. " input")
  self.output = buffer(input, self.output, settings, self.info.name .. " output")
  self.canvas = input
end

-- toggle input/output workflow between two buffers,
-- matched and initialised to input canvas type
local function work(self)
  self.input, self.output = self.output, self.input       -- toggle buffer input/output
  local input = self.canvas or self.input                      -- ... and use input canvas as first input
  self.canvas = nil                                            -- ... but only once, unless newInput() called
  return input, self.output
end

-- renderTo()
local function renderTo(self, fct, ...)
  local input, output = work(self)
  output: renderTo(fct or lg.draw, input, ...)
end

-- renderToMipmap()
-- copy input to Mipmap canvas, creating it if necessary, and generating the levels
-- leaves the workflow unchanged
local function renderToMipmap(self, input, filter)
  filter = filter or "linear"
  input = input or "output"
  self: copy(input, "mipmap", {format = "rgba16", mipmaps = "manual"})
  self.mipmap: setFilter (filter, filter)
  self.mipmap: setMipmapFilter(filter)
  self.mipmap: generateMipmaps()     
end

-- renderToMipLevel, mimics renderTo() but allows targeting a specific mipmap level
--local function renderToMipLevel(self, level, fct, ...)
--  lg.setCanvas {self.mipmap, mipmap = level}
--  local input, output = work(self)                              -- don't need or want output buffer
--  self.mipmap: renderTo(fct or lg.draw, output, ...)     -- always render to mipmap buffer
--  swap(self, "input", "output")                               -- leave buffers unchanged
--  lg.setCanvas()
--end

--- Calculates mipmap levels and their respective dimensions for a workflow 'mipmap' canvas.
-- @param self The workflow 
-- @return table An array of levels, where #result gives the total number of levels.
local function getMipmapChain(self)
  local w, h = self.mipmap: getDimensions()
  local chain = {}
  
  repeat
    w = math.max(1, math.floor(w / 2))
    h = math.max(1, math.floor(h / 2))
    chain[#chain+1] = {w, h}
  until w == 1 and h == 1

  return chain
end

--- finds level in chain with, at least, {W, H} dimensions
local function getMipmapLevel(self, W, H)
  local chain = self: getMipmapChain()
  local level = 1
  while chain[level][1] >= W and chain[level][2] >= H do
    level = level + 1
    if level > #chain then return 0 end   -- never big enough
  end
  return level - 1, chain[level - 1]
end

-- setShader()
local function setShader(self, shader, uniforms)
  
  if uniforms then
    for name, value in pairs(uniforms) do
      if shader:hasUniform(name) then
        shader: send(name, value)
      else
        error("shader has no such uniform name: " .. name, 3)
      end
    end
  end
  
  lg.setShader(shader)
end

-- shadeWith()
--[[
    WORKAROUND: LÖVE SpriteBatch / OpenGL State Optimization Bug
    When ping-ponging canvases, LÖVE's CPU-side batching tries to combine
    sequential draw calls under a single active shader state. Because the 
    shader never "changes", the OpenGL driver's texture unit cache isn't 
    told that the underlying Canvas pixels have changed between draws.
    Calling love.graphics.setShader(shader) right before each draw forces 
    LÖVE to break the batch and issue a hard OpenGL state re-bind.
--]]
local function shadeWith(self, shader, uniforms)
  local input, output = work(self)
  setShader(self, shader, uniforms)
  output: renderTo(lg.draw, input)
  lg.setShader()
end

-- clear buffer, default to output
local function clear(self, name, r, g, b, a)
  r, g, b, a = r or 0, g or 0, b or 0, a or 0
  if not name then error("clear requires buffer name", 2) end
  if self[name] then
    self[name]: renderTo(lg.clear, r,g,b,a)
  end
end

-- get buffer by name, creating if necessary, or return supplied canvas
local function byName(self, buf)
  if type(buf) == "string" then
    buf = buffer(self.output, self[buf])   -- ensure that it exists
  end
  return buf
end

local function tostring(self)
  local t = {}
  for n,v in pairs(self) do
    local tv = type(v)
    if tv ~= "function" then
      if tv == "userdata" then  -- it's a canvas
        t[n] = v:getFormat()
      else
        t[n] = v
      end
    end
  end
  
  return pretty(t)
end

-- info = {name = "...", format = "...", ...}
function _M.new(info)
  local W = {
    info = info,
    
    input = nil,        -- the two working buffers...
    output = nil,       -- .. yet to be initialised
    canvas = nil,       -- temporary input
    
    badpixel    = badpixel,
    debayer     = debayer.demosaic,
    
    starfinder  = starfinder,
    
    thumbnail   = thumbnail,
    stretch     = stretcher.stretch,
    bw_points   = stretcher.bw_points,
     
    background  = background,
    calibrate   = calibrator.calibrate,
    
    scnr        = colour.scnr,
    synthL      = colour.synthL,
    balance     = colour.balance,
    satboost    = colour.oksat,
    temp_tint   = colour.temp_tint,
    lrgb        = colour.lrgb,
    
    plugin      = plugins,    -- special calling syntax   workflow: plugin ("NAME", ...)
    
    gaussian  = kovesi,
    mipblur   = mipblur,
    
    -- local methods
    
    dump = dump,
    undo = undo,
    copy = copy,
    swap = swap,
    save = save,
    clear = clear,
    buffer = byName,
    renderTo = renderTo,
    shadeWith = shadeWith,
    setShader = setShader,
    
    renderToMipmap = renderToMipmap,
    renderToMipLevel = renderToMipLevel,
    getMipmapChain = getMipmapChain,
    getMipmapLevel = getMipmapLevel,
    
    newInput = newInput,
    getDimensions = getDimensions,
    getChannelCount = getChannelCount,
    
    new = _M.new
  }
  
  -- Create a static screen-space quad
  local vertices = {
      -- {x, y, u, v}
      {0, 0, 0, 0},
      {1, 0, 1, 0},
      {1, 1, 1, 1},
      {0, 1, 0, 1},
  }

  -- Create a static mesh (VBO stored on GPU VRAM permanently)
  W.dummyMesh = love.graphics.newMesh(vertices, "fan", "static")

  return setmetatable (W, {__tostring = tostring})

end



return _M

-----
