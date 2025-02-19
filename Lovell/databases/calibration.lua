--
-- calibration.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.19",
    DESCRIPTION = "Calibration masters database - bias, darks, flats, ...",
  }


-- 2025.02.19  Version 0


local _log = require "logger" (_M)

local fits = require "lib.fits"

local love = love
local lf = love.filesystem


-------------------------------
--
-- CALIBRATION database
--


_M.cols = {
    {"Name",   w = 250, },
    {"Diameter", w = 120, type = "number", align = "center"},
    {"Focal length (mm)", w = 200, type = "number", align = "right"},
  }

function _M.loader(path)
  local dir = lf.getDirectoryItems (path)
  for i, fname in ipairs(dir) do
    if fname: match "%.fits?$" then
      local file = lf.newFile (path .. fname)
      file: open 'r'
      local k = fits.readHeaderUnit(file)
      file: close()
      local naxis1, naxis2 = k["NAXIS1"], k["NAXIS2"]
--      _log("[%d x %d]"  % {naxis1, naxis2}, fname)
    end
  end

  return {}
end


return _M

-----

