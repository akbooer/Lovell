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

local fits require "lib.fits"


local love = _G.love
local lg = love.graphics



-------------------------------
--
-- NEW MASTER dropped
--

function _M.new(file)
  local name = file:getFilename()
  local data, size = file: read()
  file: close()
  _log ("size %.3f Mbyte" % (size or 0))

end


return _M

-----


