--
-- platesolve.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – ASTAP plate solver (requires local install)",
  }

local _log = require "logger" (_M)

-- 2026.10.11  Version 0
-- 2026.10.16  add button to browse Aladin
-- 2026.10.20  add pixel size and focal length input fields


local util = require "utils"
local fits = require "lib.fits"
local vector = require "lib.vector"
local ASTAP = require "lib.astap"
local visier = require "lib.visier"

local Aladin = visier.openAladinSkyView   -- (ra, dec, fov)


local love = _G.love
local lf = love.filesystem
local lg = love.graphics

local formatDegrees = util.formatDegrees

local EMPTY = _G.READONLY {}

-------------------------------
--
-- MONO SHADER - Calculate unstretched mono image directly from stack
--

local mono = lg.newShader[[
#pragma language glsl3

uniform vec4 weights;     // RGBL weights for synthetic lum

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 _) {

  vec4 raw = Texel(tex, tc);
  float L = dot(raw, weights);
  return vec4(vec3(L), 1.0);
  
}

]]


local function mono_image(workflow)
  
  -- calculate synthetic luminance from available channels
  local R, G, B, L, Re, Ge, Be, Le = unpack(workflow.RGBL)  -- get exposure counts AND times
  if Re + Ge + Be + Le > 0 then                     -- use exposure times if available                        
    R, G, B, L = Re, Ge, Be, Le            
  end
  local weights = vector {R, G, B, L} / (R + G + B + L) -- normalize

  -- render current stack as unstretched mono image
  lg.setShader(mono)
  mono: send("weights", weights)
  workflow.temp: renderTo(lg.draw, workflow.wstack.output)
  lg.setShader()
  
  return workflow.temp
end
 
 
-------------------------------
--
-- PLUGIN
--

local save_folder = lf.getSaveDirectory()
local filename = "/platesolve/astap"

local RUN 
local result    -- solution text for draw()

local plugin = {
  
    id = "Plate solve",
    static = true,
    
    -- control Input widgets, using existing controls (from the settings page)
    pixelsize = nil, 
    focal_len = nil,
    fov = nil,
    OBJECT = nil,       -- from information panel
    
    WCS = nil,        -- World Coordinate System of solution
    
  }


function plugin: reset(controls)
  -- initial setup of input widgets
  if controls then
    self.pixelsize = controls.pixelsize
    self.focal_len = controls.focal_len
    self.OBJECT = controls.object
  end
  
  -- clear previous solution
  result = EMPTY
end


plugin.documentation = [[
Plate solving using a local installation of ASTAP.

If the object is labelled, with RA and DEC defined from the object database, then the 'Solve with ASTAP' button will start a search around that point.  

Ideally, the focal length and camera pixel size are specified in the settings so that an accurate FOV can be used. 

If successful, the exact coordinates of the image centre are displayed, along with the rotation angle.  The image is rotated to the correct orientation, and the focal length is updated to the solved value.

The 'View in Aladin' button opens a web page there with the same field of view.

If no coordinates are available, a blind search is done, which may take a few more seconds.  It's certainly possible that this will fail to solve.

]]


-------------------------------
--
-- RUN and DRAW
--

local fitsfile, fitspath do
  fitsfile = filename .. ".fit"
  fitspath = table.concat {save_folder, fitsfile}
end


function plugin: run(workflow, controls)
  local image = workflow.output
  
  if not (RUN and image) then return end     -- nothing to do!
  RUN = false                                 -- don't do it until pressed again
  
  local pixel_size = controls.pixel_size()      -- pixel size in arc seconds (assume square)
  local object = controls.object                -- object info including name, RA, DEC, possibly
  
  _log("getting unstretched mono image from stack [%dx%d]" % {image:getDimensions()})
  image = mono_image(workflow)          -- get unstretched mono image from stack
  _log ("converting image to FITS file:", fitsfile)
  fits.write(image, fitspath)
  
  self.fov = pixel_size and pixel_size * image:getHeight() / 3600 or nil   -- convert from arcseconds to degrees
  local WCS = ASTAP.run {
        filepath = fitspath, 
        FOV = self.fov,
        RA = object and object.RA,
        DEC = object and object.DEC,
      }
      
  self.WCS = WCS
  
  if WCS then           -- World Coordinate System
    
    -- adjust display angle and flips to correctly orient (North up, East left)
    -- using full transformation matrix
    local ra, dec = tonumber(WCS.CRVAL1), tonumber(WCS.CRVAL2)
    local CD11, CD12, CD21, CD22 = WCS.CD1_1, WCS.CD1_2, WCS.CD2_1, WCS.CD2_2
    local det = CD11 * CD22 - CD12 * CD21              -- transformation matrix determinant
    local flipped = det < 0
    local sign = flipped and -1 or 1                    -- parity check for flipped image
    local angle = sign * math.atan2(CD21, sign * CD11)  -- apply flip to angle
  
    angle = angle + math.radians(180)           -- account for display Y axis pointing downwards  
    angle = (angle + math.pi) % (2 * math.pi) - math.pi -- change range to +/- pi
    controls.rotate.value = angle               -- rotate screen image to match
    
    controls.flipLR.checked = flipped
    controls.flipUD.checked = false
    
    local Sx = math.sqrt(CD11^2 + CD21^2)       -- x scale in degrees/pixel
    local Sy = math.sqrt(CD12^2 + CD22^2)       -- y scale in degrees/pixel
    
    local px = tonumber(controls.pixelsize.text) / 1000       -- convert microns to millimetres
    
    local focal_length = math.floor(px / math.radians(0.5*(Sx + Sy)) + 0.5)  -- mm
    self.focal_len.text = tostring(focal_length)
    self.fov = Sx * image: getHeight()
    _log ("actual focal length = %d mm" % focal_length)
    
    -- format output for draw()    
    result = {
        title = "(RA, DEC)",
        solution =  util.formatRA(ra) ..', ' .. util.formatDEC(dec),
        rotation = "rotation:",
        degrees = formatDegrees(angle, 1),
      }
    
  else
    result = {solution = "Not solved"}
  end

end


local Lopt, Copt, Ropt, Wopt    -- label options

function plugin: draw(suit)  
  local W, H = 160, 25
  local sl = suit.layout
  Lopt = Lopt or {align = "left", color = suit.theme.color.bluetext}
  Copt = Copt or {align = "center", color = suit.theme.color.bluetext}
  Ropt = Ropt or {align = "right", color = suit.theme.color.bluetext}
  Wopt = Wopt or {align = "left"}
  
  local W2 = W / 2
  local x,y, w,h = sl: row(W2, 10)
  suit: Label('Px (µm)', Lopt, x,y, W2, 20)
  suit: Label('FL (mm)', Lopt, x + W2 + 10, y, W2, 20)
  
  x,y, w,h = sl: row(W2, H)
  suit: Input(self.pixelsize, x, y, w - 10,h)
  suit: Input(self.focal_len, x + W2 + 10, y, w - 10,h)
  
  RUN = suit: Button("Solve with ASTAP", sl: row(W, H)) .hit 
  
  suit: Label(result.title or '', Copt, sl: row(W, 10))
  suit: Label(result.solution or '', sl: row()) 
  
  x,y, w,h = sl: row(W/2, 30)
  suit: Label(result.rotation or '', Ropt, x,y, w,h)
  suit: Label(result.degrees or '', Wopt, x + W/2 + 2,y, w,h)

  if suit: Button("View in Aladin", sl: row(W, H)) .hit then
    local ra, dec
    local WCS, OBJECT = self.WCS, self.OBJECT
    if WCS then                                     -- platesolved coordinates...
      ra =  "%0.6f" % tonumber(WCS.CRVAL1)
      dec = "%0.6f" % tonumber(WCS.CRVAL2)
    elseif OBJECT then                              -- ...or named object coordinates
      ra = tonumber(OBJECT.RA)
      dec = tonumber(OBJECT.DEC)
    end
    
    if ra then 
      Aladin(ra, dec, self.fov)
    end
  end
  
end


return plugin

-----


