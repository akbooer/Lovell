--
-- astap.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.22",
    AUTHOR = "AK Booer",
    DESCRIPTION = "ASTAP - plate solving",
  }

local _log = require "logger" (_M)


-- 2026.10.16  version 0
-- 2026.10.22  return complete .wcs structure (World Coordinate System) as solution


local love = _G.love
local ls = love.system

-------------------------------
--
-- ASTAP
--

local astap_path do  -- find default file path to application

  local astap_app = "/Applications/astap.app/Contents/MacOS/astap"    -- Mac OS
  local astap_exe = '"C:/Program Files/astap/astap.exe"'              -- Windows

  astap_path  = (ls.getOS() == "OS X") and astap_app or astap_exe
end


-- Function to execute ASTAP via io.popen and capture stdout logs
-- input:
--    filepath, FITS or PNG files, full path including filename and extension
--    RA, DEC, in degrees, blind search if missing
--    FOV, field of view in degrees, possibly missing
--
function _M.run(info)
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
    fov = info.FOV and "%0.2f" % info.FOV or nil,
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
    ini_path = image_path:gsub("%.%a+$", ".wcs")
    file = io.open(ini_path, "r")
  end

  if not file then
    _log "Error: Solution file not generated."
    return nil
  end
  
--[[

  --TODO: use proper FITS header routine?
        local name, equals, value, slash, comment = record: match "([A-Z0-9-_]+)%s*(=?)%s*([^/]+)(/?)%s*(.*)"
        local name, equals, value = record: match "([A-Z0-9-_]+)%s*(=?)([^/]+)"
--]]
  
  local WCS = {}        
  for line in file:lines() do
    local name, _, value = line: match "([A-Z0-9-_]+)%s*(=?)([^/]+)"
    WCS[name] = value
  end
  file:close()

  ra, dec = tonumber(WCS.CRVAL1), tonumber(WCS.CRVAL2)
  if ra and dec then
    _log ("Solved: (RA,DEC) %0.3f  %0.3f" % { ra, dec })
    return WCS
  end

end


return _M

-----

