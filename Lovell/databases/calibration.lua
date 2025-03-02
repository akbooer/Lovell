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

--[[
       return Table(
            size=Window.size,
            data=self.library,
            name='Calibration masters',
            description='Calibration masters',
            cols={
                'name': {'w': 120, 'align': 'left', 'label': 'Name', 'action': self.show_calibration_frame},
                'type': {'w': 60, 'label': 'Type', 'align': 'left'},
                'exposure': {'w': 80, 'label': 'Exposure'},
                'temperature': {'w': 80, 'label': 'Temp. C', 'type': str},
                'gain': {'w': 50, 'label': 'Gain', 'type': int},
                'offset': {'w': 60, 'label': 'Offset', 'type': int},
                'bin': {'w': 45, 'label': 'Bin', 'type': int},
                'calibration_method': {'w': 120, 'label': 'Calib?', 'type': str},
                'filter': {'w': 80, 'label': 'Filter'},
                'created': {'w': 130, 'label': 'Created', 'sort': {'DateFormat': date_time_format}},
                'shape_str': {'w': 110, 'label': 'Size'},
                'age': {'w': 50, 'label': 'Age', 'type': int},
                'nsubs': {'w': 50, 'label': 'Subs', 'type': int},
                'camera': {'w': 1, 'align': 'left', 'label': 'Camera', 'type': str},
                },
            actions={'move to delete dir': self.move_to_delete_folder},
            initial_sort_column='created',
            reverse_initial_sort=True,
            on_hide_method=self.app.table_hiding
            )

--]]


_M.cols = {
    {"Name",   w = 250, },
    {"Type", w = 60, type = "number", align = "center"},
    {"Exposure", w = 100, type = "number", align = "right"},
    {"ºC", w = 50, },
    {"Gain", w = 50, },
--    {"Offset", },
    {"Filter", w = 80, },
    {"Date", w = 100, },
    {"Size", w = 100, align = "center", },
    {"Nsubs", w = 60, },
    {"Camera", w = 250},
  }

_M.col_index = {1,2,3,4,5,6,7,8, 10}
  
local Size, Camera = 8, 10

function _M.load(path)
  local masters = {}
  path = path or "masters/"
  local dir = lf.getDirectoryItems (path)
  for i, fname in ipairs(dir) do
    local name = fname: match "([^%.]+)%.fits?$"
    if name then
      local file = lf.newFile (path .. fname)
      file: open 'r'
      local k = fits.readHeaderUnit(file)
      file: close()
--      print(pretty(k))
      local naxis1, naxis2 = k["NAXIS1"], k["NAXIS2"]
      masters[#masters + 1] = {name, 
        [Size] = "%dx%d" % {naxis1, naxis2},
        [Camera] = k.CAMERA}
--      _log("[%d x %d]"  % {naxis1, naxis2}, fname)
    end
  end

  return masters
end


return _M

-----

