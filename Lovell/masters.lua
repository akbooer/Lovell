--
-- masters.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.17",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Master calibration file handling",
  }

-- 2024.12.08  Version 0

-- 2025.05.17  call calibration database reload() after adding new master

local _log = require "logger" (_M)

local calibration = require "databases.calibration"

local love = _G.love
local lf = love.filesystem

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
  local f = lf.newFile(path, 'w')
  f: write(data)
  f: close()
  f: release()
  _log("wrote " .. path)
  
  -- now index the calibration file metadata
  calibration.reload()

end


return _M

-----


