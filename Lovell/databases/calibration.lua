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

local json = require "lib.json"

local iframe = require "iframe"
local newTimer = require "utils" .newTimer

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
    {"Type", w = 60, align = "center", },
    {"Exposure", w = 90, type = "number", align = "center", format = formatSeconds, },
    {"ºC", w = 50, format = function(t) return t and t .. 'º' or '' end, align = "center", type = "number", },
    {"Gain", w = 50, format = function(g) return g and 'x' .. g or '' end, align = "center", type = "number", },
    {"Offset", w = 60, format = function(o) return o and "%+d" % o or '' end, align = "center", type = "number", },
    {"Filter", w = 60, align = "center", },
    {"Date", w = 100, type = "number", format = function(t) return t and os.date("%Y%m%d", t) or '' end},
    {"Size", w = 100, align = "center", },
    {"Bits", w = 50, align = "center", },
    {"Nsubs", w = 60, align = "right", type = "number", },
    {"Camera", w = 200},
    {"Filename", },
  }

_M.col_index = {1,2,3,4,5,6,7,8,9, 10,11, 12}

local FILENAME = #_M.cols         -- full filename is last column
local PATH = "masters/"

local library = {}

local file_pattern = "([^%.]+)%.fits?$"

-------------------------------
--
-- UTILITIES
--

local function FITS_files(path)
  local files = {}
  local dir = lf.getDirectoryItems (path)
  for _, fname in ipairs(dir) do
    if fname: match (file_pattern) then
      files[#files+1] = fname
    end
  end
  return files
end

-- index a list using optional function
local function index(list, fct)
  local idx = {}
  fct = fct or function(x) return x end
  for i, x in ipairs(list) do
    idx[fct(x)] = i
  end
  return idx
end

local function readfile(fname)
  local skip_data = true
  local f = iframe.read(nil, fname, PATH, skip_data)
  
  local k = f.keywords
  local subtype = (f.subtype or ''): match "[bdf][ial][ar][skt]"
  local filter = subtype == "flat" and f.filter: upper() or nil
  local nsubs = k.STACKCNT or k.NSUBS or nil
  local bitpix, naxis1, naxis2 = k.BITPIX, k.NAXIS1, k.NAXIS2

  return {
      f.name: match(file_pattern), subtype, f.exposure,
      f.temperature, f.gain, f.offset,
      filter, f.epoch,
      "%dx%d" % {naxis1, naxis2}, math.abs(bitpix),
      nsubs, f.camera,
      fname,              -- full filename is last column
    }
end

-------------------------------
--
-- LOAD
--

function _M.load()
  
  local elapsed = newTimer()
  
  -- read the index file and the directory of FITS files
  local catalogue = json.read (PATH .. "index.json") or  {}
  local files = FITS_files (PATH)
  local index = index(files)
  
  -- go through the catalogue, removing any missing files
  local added, removed = 0
  local newcat = {}
  for _, item in ipairs(catalogue) do
    local filename = item[FILENAME]
    if index[filename] then
      newcat[#newcat + 1] = item    -- add to new catalogue
      index[filename] = nil         -- remove from file index
    end
  end
  removed = #catalogue - #newcat

  -- add any remaining files to the new catalogue
  for filename, n in pairs(index) do
    newcat[#newcat + 1] = readfile(filename)
    added = added + 1
  end
  
  json.write (PATH .. "index.json", newcat)

  _log(elapsed ("%.3f ms, loaded database, total: %d, added: %d, removed: %d", #newcat, added, removed))
  return newcat
end

-------------------------------
--
-- RELOAD, called when new master dropped
--

function _M.reload()
  -- TO DO
end

-------------------------------
--
-- UPDATE
--

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

