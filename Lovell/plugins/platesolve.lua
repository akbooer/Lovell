--
-- platesolve.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.14",
    AUTHOR = "AK Booer",
    DESCRIPTION = "PLUGIN – ASTAP plate solver (requires local install)",
  }

local _log = require "logger" (_M)

-- 2026.10.11  Version 0


local util = require "utils"
local fits = require "lib.fits"
local vector = require "lib.vector"


local love = _G.love
local lf = love.filesystem
local lg = love.graphics

local save_folder = lf.getSaveDirectory()

local filename = "/platesolve/astap"

local pngfile = filename .. ".png"
local fitsfile = filename .. ".fit"
local filepath = table.concat {save_folder, pngfile}
local fitspath = table.concat {save_folder, fitsfile}

-- default file path
local astap_app = "/Applications/astap.app/Contents/MacOS/astap"    -- Mac OS
local astap_exe = '"C:/Program Files/astap/astap.exe"'              -- Windows

local OS = love.system.getOS()

local ASTAP  = OS == "OS X" and astap_app or astap_exe

-------------------------------
--
-- Calculate unstretched mono image directly from stack
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
-- ASTAP
--

-- Function to execute ASTAP via io.popen and capture stdout logs
local function run_astap(astap_path, info)
  local image_path = info.filepath    

  -- Build the command line
  local ra, dec
  ra  = tonumber(info.RA)  and "%0.3f" % (info.RA / 15) or nil    -- RA in hours
  dec = tonumber(info.DEC) and "%0.3f" % (info.DEC)  or nil       -- DEC in degrees (+-90)

  local options = {
    z = 0,                                                -- auto scaling
    m = 3,                                                -- minimum star size (in arc seconds)
    r = ra and dec and 10 or 181,                        -- search field radius (degrees, or blind search)
    s = 300,                                              -- max number of stars
    fov = info.fov and "%0.2f" % info.fov or nil,
    ra = ra,
    spd = dec and dec + 90 or nil,                       -- south pole distance
--    update = '',                                          -- add solution to FITS file
  }

  local opts = {}
  for flag, opt in pairs(options) do
    opts[#opts+1] = table.concat {'-', flag, ' ', opt, ' '}
  end
  opts = table.concat(opts, ' ')

  local cmd = string.format('"%s" -f "%s" %s', astap_path, image_path, opts)

  -- Open process via popen to capture stdout
  local handle = io.popen(cmd .. " 2>&1") -- 2>&1 merges stderr into stdout if needed
  if not handle then
    _log "Error: Failed to open process pipe"
    return nil
  end

  local log_output = handle:read "*a"
  handle:close()

  if log_output: match "%S" then      -- ie. non-blank
    local line = "------------------------\n"
    _log ("ASTAP options:", opts, "\n\n", line, log_output, line)
  end

  -- Check if it solved successfully by checking the generated .ini or .wcs file
  local ini_path = image_path:gsub("%.%a+$", ".ini")
  local file = io.open(ini_path, "r")
  if not file then
    ini_path = image_path:gsub("%.png$", ".wcs")
    file = io.open(ini_path, "r")
  end

  if not file then
    _log "Error: Solution file not generated."
    return nil
  end
  
--[[
        local name, equals, value, slash, comment = record: match "([A-Z0-9-_]+)%s*(=?)%s*([^/]+)(/?)%s*(.*)"
        local name, equals, value = record: match "([A-Z0-9-_]+)%s*(=?)([^/]+)"
--]]
  
  local solution = {}
  for line in file:lines() do
    local name, _, value = line: match "([A-Z0-9-_]+)%s*(=?)([^/]+)"
    solution[name] = value
  end
  file:close()

  ra, dec = tonumber(solution.CRVAL1), tonumber(solution.CRVAL2)
  if ra and dec then
    local ra_dec = { ra, dec }
    _log ("Solved: (RA,DEC) %0.3f  %0.3f" % ra_dec)
    return ra_dec, solution
  end

end


local plugin = {
    id = "Plate solve",
    solve = {"Solve..."},
}

plugin.documentation = [[
Plate solving using a local installation of ASTAP.

If the object is labelled, with RA and DEC defined from the object database, then the 'Solve...' button will start a search around that point.  

Ideally, the focal length and camera pixel size are specified in the settings so that an accurate FOV can be used. 

If successful, the exact coordinates of the image centre are displayed, along with the rotation angle.  The image is rotated to the correct orientation.

If no coordinates are available, a blind search is done, which may take a few more seconds.  It's certainly possible that this will fail to solve.

]]


-------------------------------
--
-- RUN and DRAW
--

local solution = ''   -- persistent status text 
local degrees = ''

local RUN 

function plugin: run(workflow, controls)
  local image, pixel_size, object
  image = workflow.output
  pixel_size = controls.pixel_size()
  object = controls.object                -- object info including name, RA, DEC, possibly
  
  if RUN and image then
    RUN = false                           -- don't do it until pressed again
    image = mono_image(workflow)          -- getunstretched image from stack
    solution = 'solving...'
    degrees = ''
    _log ("converting image to FITS file:", fitsfile)
    fits.write(image, fitspath)
    
    local fov = pixel_size and pixel_size * image:getHeight() / 3600   -- convert from arcseconds to degrees
    local ra_dec, info = run_astap(ASTAP, {
          filepath = fitspath, 
          fov = fov,
          RA = object and object.RA,
          DEC = object and object.DEC,
        })
    if ra_dec then
      local ra = util.formatRA(ra_dec[1])
      local dec = util.formatDEC(ra_dec[2])
      solution = "(RA, DEC)\n" .. ra ..', ' .. dec 
    else
      solution = "Not solved"
    end
    if info and tonumber(info.CROTA1) and tonumber(info.CROTA2) then
      local angle = (info.CROTA1 + info.CROTA2) / 2  - 90     -- in degrees (North is up)
      degrees = "%0.1fº" % angle
      controls.rotate.value = angle * math.pi / 180       -- rotate screen image to match
    end
  end
end

function plugin: draw(suit)  
  local sl = suit.layout
  if suit: Button(self.solve, sl: row(100, 25)) .hit then
    RUN = true
  end
  suit: Label(solution, sl: row(160, 25)) 
  suit: Label(degrees, sl: row(160, 25)) 
  
end


return plugin

-----

