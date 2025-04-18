--
-- calibration.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.04.08",
    DESCRIPTION = "Calibration masters database - bias, darks, flats, ...",
  }


-- 2025.02.19  Version 0
-- 2025.04.08  start adding image attributes from file data


local _log = require "logger" (_M)

local fits = require "lib.fits"

local formatSeconds = require "utils" .formatSeconds

local love = _G.love
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
    {"Type", w = 60, align = "center"},
    {"Exposure", w = 100, type = "number", align = "center", format = formatSeconds},
    {"ºC", w = 50, },
    {"Gain", w = 50, },
--    {"Offset", },
    {"Filter", w = 80, },
    {"Date", w = 100, },
    {"Size", w = 100, align = "center", },
    {"Bits", w = 50, align = "center", },
    {"Nsubs", w = 60, },
    {"Camera", w = 250},
  }

_M.col_index = {1,2,3,4,5,6,7,8,9, 11}
  
local Type, Size, Bits, Camera = 2, 8, 9, 11

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
      
      local bitpix, naxis1, naxis2, naxis3 = k.BITPIX, k.NAXIS1, k.NAXIS2
      local ftype = k.IMAGETYP or k.SUBTYPE or k.SUB_TYPE or ''
      local exposure = k.EXPOSURE or k.EXPTIME or 0
      ftype = ftype: match "bias" or ftype: match "dark" or ftype: match "flat" or '?'
      masters[#masters + 1] = {name, ftype, exposure,
        [Size] = "%dx%d" % {naxis1, naxis2},
        [Bits] = math.abs(bitpix),
        [Camera] = k.CAMERA}
      _log("[%d x %d]"  % {naxis1, naxis2}, bitpix, fname)
    end
  end

  return masters
end

function _M.update(self)
  local layout = self.layout
  local function row(...) return layout: row(...) end
  local function col(...) return layout: col(...) end

  -- masters list buttons
  
--  if self: Button("Select compatible", row(120, 30)) .hit then
----    select_all()
--  end
--  col(15, 30)
--  if self: Button("Deselect all", col(120, 30)) .hit then
----    deselect_all()
--  end

  col(50, 30)
--  if self: Button("Add to Watchlist", col(170, 30)) .hit then
--    add_to_observing_list()
--  end
--  col(15, 30)
--  if self: Button("Delete from Watchlist", col(170, 30)) .hit then
--    remove_from_observing_list()
--  end
  
  layout: reset(550,20, 10,10)
  if self: Button("Apply Selected Masters", layout: col(220, 30)) .hit then
--    reloadFolder: push(current)       -- send the whole metadata
--    pager: push "main"                -- switch to main display
  end

  layout: reset(1120, 10, 10,10)
  if self: Button("Match", col(80,50)) .hit then
    
  end
  
--  local h = love.graphics.getHeight()
--  self: Label(name, Loptions, layout: col(250, 30))
--  self: Label(folder, Loptions, 20, h - 40, 550, 30)
end


return _M

-----

