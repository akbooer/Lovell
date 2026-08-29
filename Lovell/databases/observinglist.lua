--
--  observinglist.lua
--
--  translated nearly directly from Jocular's observinglist.py
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.10",
    AUTHOR = "AK Booer",
    DESCRIPTION = "DSO table and observing list manager",

  }

local _log = require "logger" (_M)


-- 2025.02.15  translated directly from Jocular's observinglist.py

-- 2026.05.25  change time slider format to hh:mm
-- 2026.06.10  allow right-click to reset time offset slider

-- Handles DSO table and observing list management, including alt-az/transit computations.

local dsos  = require "databases.dso"
local obsess   = require "databases.obsessions"

local controls = require "controls"

local utils  = require "utils"
local json  = require "lib.json"

local newTimer = require "utils" .newTimer
local calcs     = require "lib.calcs"
local local_sidereal_time = calcs.local_sidereal_time
local utc_offset = calcs.utc_offset

local filter = require "guillaume.spreadsheet" .filter    -- for special RA filter

local rightClick = require "guillaume.suitable" .rightClick   -- for resetting time offset slider

local love = _G.love
local lt = love.timer

local sun_altitude = calcs.sun_altitude

local sun_time  = {value = 0, min = 0, max = 24}      -- slider for sun position

local math = math
      math.nan = math.abs(0/0)
      math.isnan = function(x) return x ~= x end

local int  = math.floor
local rads = math.pi / 180

local np = math                     -- for source compatibility with Python
      np.arcsin = math.asin
      np.arctan2 = math.atan2

local settings = controls.settings

local Loptions = {align = "left"}

local formatHM          = utils.formatHM
local formatRA          = utils.formatRA
local formatDEC         = utils.formatDEC
local formatArcMinutes  = utils.formatArcMinutes

local formatMag = function(x) return x == 0 and '' or x end

-- CLASS variables and functions

_M.latitude  = 0    -- updated in load() to values from settings
_M.longitude = 0
_M.sinlat = 0
_M.coslat = 1
_M.local_sidereal_time = 0

_M.sun_altitude = sun_altitude    -- function()

local REFRESH = 5   -- 5 second update interval for Alt/Az/Loc
local last_time_changed

local alt_az_quad       -- forward reference

local function formatAltAzQuad(v, r)
  alt_az_quad(_M.objects[r])          -- update the three columns on this row
  return v                            -- return this one
end

-- stored in degrees, but formatted in HH:MM for display, so scale inequality test accordingly
local function filterRA(x, inequality, reference)  -- scale, HH to DEG
  reference = 15 * (reference or 0)
  return filter.number(x, inequality, reference)
end

-------------------------
--
-- DATA
--
 
local cols = {  -- reflects the actual order of the source database
        {"Name", w = 210, sort = utils.alphanumeric_sort, },   -- to get things like Messier 51 into correct order
        {"RA",   w = 75, format = formatRA, align = "right",  type = "number", filter = filterRA},  -- scale, HH to DEG
        {"DEC",  w = 85, format = formatDEC, align = "right", type = "number", },
        {"Con",  w = 40, },
        {"OT ",  w = 40, },
        {"Mag",  w = 50, format = formatMag, type = "number", align = "center", },
        {"Diam", w = 50, format = formatArcMinutes, type = "number", align = "center", },
        {"Other",w = 240, },
        
        -- the following columns computed dynamically in update()
        {"Loc",     w = 40, align = "center", format = formatAltAzQuad, },
        {"Az",      w = 40, align = "right",  type = "number", },
        {"Alt",     w = 40, align = "right",  type = "number", },
        
        -- these values are static and computed once after loading
        {"Max",     w = 40, align = "center", label = "Max"},    -- max altitude
        {"Transit", w = 60, align = "center", format = formatHM, type = "number"},
        
        -- the following added from the observing watch list
        {"#Obs", w = 50, align = "center", type = "number", },
        {"List", w = 55, },
        }

local col_index = {1,5,4,2,3, 9,10,11, 12,13, 6,7, 14,15, 8}    -- displayed order of columns


local Name, Obs, Added = 1, 14, 15
local RA, Dec = 2, 3
local Quadrant, Az, Alt = 9, 10 ,11

local widget = {cols = cols, col_index = col_index, data = {}}    -- SUIT-able Table widget

local function select_all()
  local ridx = widget.row_index 
  local sel = widget.highlight or {}
  for i = 1, ridx.n do sel[ridx[i]] = true end
  sel.anchor = 1
end

local function deselect_all()
  local sel = widget.highlight or {}
  for i = 1, #widget.data do sel[i] = nil end
  sel.anchor = 1
end

-------------------------
--
-- OBSERVING LIST
--


local observing_list

--[=[


    def new_from_list(self, row, *args):
        # User selects a row in the observing list table
        name = row.fields['Name'].text + '/' + row.fields['OT'].text
        self.table.hide()
        res = Component.get('Catalogues').lookup(name)
        if res is None:
            toast(f'Cannot find {name} in database')
        else:
            Component.get('DSO').new_DSO_name(res)
--]=]


local function save_observing_list()
  json.write("observing_list.json", observing_list)
end

local function update_list()
  save_observing_list()
  deselect_all()
end

local function add_to_observing_list()
  local sel = widget.highlight
  local data = widget.data
  local date = os.date "%d %b"  -- day month
  local n = 0
  for i in pairs(sel) do
    local object = data[i]
    if object then
      n = n + 1
      object[Added] = date
      observing_list[object[Name]] = date
    end
  end
  update_list()
  _log("added %d objects" % n)
end

local function remove_from_observing_list()
  local sel = widget.highlight
  local data = widget.data
  local n = 0
  for i in pairs(sel) do
    local object = data[i]
    if object then
      n = n + 1
      object[Added] = ''
      observing_list[object[Name]] = nil
    end
  end
  update_list()
  _log("removed %d objects" % n)
end

--[=[


    def remove_from_catalogue(self, *args):
        ''' Remove current DSO from user objects list
        '''
        catas = Component.get('Catalogues')
        for name in self.table.selected:
            obj = self.objects[name]
            # only delete if a user defined object
            if obj['Usr'] == 'Y':
                catas.delete_user_object(name)
        self.update_list()


    def new_observation(self):
        OT = Component.get('Metadata').get('OT', '')
        Name = Component.get('Metadata').get('Name', None)
        logger.info(f'{Name}/{OT}')
        #  update observed count if DSO is known
        if Name is not None:
            name = f'{Name}/{OT}'
            if name in self.objects:
                self.objects[name]['Obs'] = self.objects[name].get('Obs', 0) + 1
            if hasattr(self, 'table'):
                self.table.update()



    def save_notes(self, *args):
        try:
            ol = {}
            for v in self.objects.values():
                if v.get('Notes', '').strip():
                    ol[v['Name']] = v['Notes']
            with open(self.app.get_path('observing_notes.json'), 'w') as f:
                json.dump(ol, f, indent=1)
        except Exception as e:
            logger.exception(f'problem saving ({e})')
            toast('problem saving observing notes')

--]=]


-------------------------
--
-- UTILITIES
--


local qmap = {'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'}

local function quadrant(x)
  -- terrestrial direction
  local quad = int((x + 22.5) / 45) % 8 + 1   -- @akb, +1 since Lua is not zero-based indexing
  return qmap[quad]
end

-- update Alt, Az, Loc for a single object
function alt_az_quad(v)
    local ra, dec = v[RA], v[Dec] * rads
    local sinlat, coslat = _M.sinlat, _M.coslat
    
    local H = (-utc_offset  * 15 + _M.local_sidereal_time - ra) * rads
    local sinH, cosH = np.sin(H), np.cos(H)
    local az, alt
    az = 180 + (np.arctan2(sinH, cosH * sinlat - np.tan(dec) * coslat) / rads)
    alt = np.arcsin(sinlat * np.sin(dec) + coslat * np.cos(dec) * cosH) / rads

    v[Az] = math.isnan(az) and math.nan or int(az)
    v[Alt] = math.isnan(alt) and math.nan or int(alt)
    v[Quadrant] = math.isnan(az) and '' or quadrant(az)
end

-- periodic update (every REFRESH seconds) of object locations
local function compute_altaz()
  widget.filter = false         -- don't force a new filtering pass
  local t = lt.getTime()
  if  last_time_changed then
    if t -  last_time_changed < REFRESH then
      return
    end
  end
   last_time_changed = t
  widget.filter = true          -- force re-application of all filters
  
  local objs = _M.objects
  for i = 1, #objs do
    alt_az_quad(objs[i])
  end
end

local function compute_transits()
  --from ch 15 of Meeus
  
  local RA, Dec = 2, 3
  local MaxAlt, Transit = 12, 13
  local elapsed = newTimer()
  
  --  apparent sidereal time at Greenwich at 0hUT
  local datetime, gst_0
  datetime = os.date "!*t"
  datetime.hour, datetime.min, datetime.sec = 0, 0, 0
  gst_0 = local_sidereal_time(datetime, 0)
    
  local objs = _M.objects
  local lat, long = _M.latitude, _M.longitude
  for i = 1, #objs do
    local v = objs[i]
    local ra, dec
    ra = v[RA]
    dec = v[Dec]

    local max_alt
    max_alt = 90 - lat + dec
    max_alt = max_alt > 90 and 180 - max_alt or max_alt

    -- transit time: slight diff from Meeus since longitude negative from W here
    local transiting, m0
    transiting = np.abs(dec) < (90 - lat)
    m0 = (ra - long - gst_0 + utc_offset  * 15) / 15
    m0 = m0 % 24

    -- 10 ms or so
    v[MaxAlt] = int(max_alt)
    v[Transit] = transiting and m0 or ''
  end
  _log (elapsed ('%.3f ms, computed transits for %d objects', #objs))
end

-------------------------
--
-- LOAD DATABASE
--

function _M.load()
  
  if #widget.data > 0 then return widget end     -- only load data once
  
  local data = dsos.load()       -- get the basic DSOs
  _M.objects = data     -- TODO: WHO USES _M.objects?

  -- initialise Lat and Long NOTE: that these don't get update during a session if changed on settings page
  _M.longitude = tonumber(settings.longitude.text) or 0
  _M.latitude  = tonumber(settings.latitude.text) or 51.5      -- defaults are approximation to Greenwich
        
  local lat = _M.latitude * rads
  _M.sinlat, _M.coslat = np.sin(lat), np.cos(lat)

  -- load observing list (maps names to date added)
  observing_list = json.read "observing_list.json" or {}
  _log "observing list loaded"
  
--[[

        # load observing notes
        try:
            with open(self.app.get_path('observing_notes.json'), 'r') as f:
                observing_notes = json.load(f)
        except:
            observing_notes = {}
        logger.info(f'{len(observing_notes)} observing notes')
--]]

  -- load previous observations if necc and count previous
      
  local prevobs = obsess.load()
  local previous = prevobs.tally
  _log ("%d unique previous observations found" % previous.n)


  -- augment/combine DSO info
  for i = 1, #data do
    local v = data[i]
    local name = v[Name]
    v[Obs] = previous[name]
    v[Added] = observing_list[name] or ''
--    v['Notes'] = observing_notes.get(name, '')
--    v['Other'] = v.get('Other', '')
  end


  local elapsed = newTimer()
  compute_altaz()    
  _log(elapsed "%0.3f ms, ALT / AZ calculations")
  compute_transits()
  
  widget = {cols = cols, col_index = col_index, data = data}
  return widget
end


-------------------------
--
-- UPDATE GUI
--

function _M: update()
  
  if #widget.data == 0 then return end
  
  local layout = self.layout
  local function row(...) return layout: row(...) end
  local function col(...) return layout: col(...) end
   
  local ridx = widget.row_index 
  local sel = widget.highlight or {}
  widget.highlight = sel

  compute_altaz(_M)    

  -- observing list buttons
  
  if self: Button("Select all", row(120, 30)) .hit then
    select_all()
  end
  col(15, 30)
  if self: Button("Deselect all", col(120, 30)) .hit then
    deselect_all()
  end

  col(50, 30)
  if self: Button("Add to Watchlist", col(170, 30)) .hit then
    add_to_observing_list()
  end
  col(15, 30)
  if self: Button("Delete from Watchlist", col(170, 30)) .hit then
    remove_from_observing_list()
  end

  -- time control widget
  col(50, 30)
  local now = os.time()
  local hour_offset = sun_time.value
  local offset = 3600 * hour_offset
  local when = now + offset
  local datetime = os.date("!*t", when)
  _M.local_sidereal_time = local_sidereal_time(datetime, _M.longitude)
  local sun_elev = sun_altitude(datetime, _M.latitude, _M.longitude)
  self: Label("sun: %.0fº" % sun_elev, col(100, 30))
  
  local x,y,w,h = col(220, 30)    -- position for slider
  self: Label(os.date("%d %b %H:%M", when), col(150, 30))
  -- user moves time slider
  local time_slider = self: Slider(sun_time, x,y+10, w,14) 
  local t = lt.getTime()
  
  if rightClick(time_slider) then  
    sun_time.value = 0
  end
  
  if time_slider.hovered then
    self: Label('+' .. utils.formatHM(hour_offset), Loptions, x - 17 + w * hour_offset /24, y - 15, 50, h)
     last_time_changed = t - REFRESH + 0.1  -- update soon after leaving
  
  end
  if time_slider.hit then
     last_time_changed = 0  -- update immediately
  end
  
  local current = controls.object
  layout: reset(550,20, 10,10)     -- go back to top and insert button to set current object
  if self: Button("Set Current Object", col(150, 30)) .hit then
    current.text = (widget.data[widget.row_index[sel.anchor]] or {})[1] or ''
  end
  self: Label(current.text, Loptions, col(250, 30))

end


return _M

-----
