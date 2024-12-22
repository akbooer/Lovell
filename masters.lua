--
-- masters.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.08",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Master calibration file handling",
  }

-- 2024.12.08  Version 0


local _log = require "logger" (_M)

local fits = require "lib.fits"


local love = _G.love
local lg = love.graphics


-------------------------------
--
-- NEW MASTER dropped
--

function _M.new(file)
  local pathname = file:getFilename()
  local filename = pathname: match "[^/]*master[^/]*%.fit"
  if not filename then
    _log "not a master calibration FITS file"
    return
  end
  
  local data, size = file: read()  
  _log ("file size %.3f Mbyte" % ((size or 0) * 1e-6))
  file: close()
  
  -- copy the file to masters folder
  
  local path = "masters/%x_%s" % {os.time(), filename}
  local f = love.filesystem.newFile(path, 'w')
  f: write(data)
 
  -- finish up
  f: close()
  f: release()
  _log("wrote " .. path)
  
  -- now index the calibration file metadata
  local f2 = love.filesystem.newFile(path, 'r')
  local keys = fits.readHeaderUnit(f2) 
  f2: close()
  
  local info = {
      camera = keys.CAMERA,
      subtype = keys.SUBTYPE or keys.SUB_TYPE or keys.IMAGTYP,
      exposure = keys.EXPOSURE or keys.EXPTIME,
      size = {keys.NAXIS1, keys.NAXIS2},
    }
  _log(pretty (info))

end


return _M

-----


