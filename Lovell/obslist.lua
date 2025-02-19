--
--  observinglist.lua
--
--  translated directly from Jocular's calcs.py
--

local _M = {
    NAME = ...,
    VERSION = "2025.02.15",
    AUTHOR = "AK Booer",
    DESCRIPTION = "translated directly from Jocular's observinglist.py",

  }

local _log = require "logger" (_M)


-- 2025.02.15  translated directly from Jocular's observinglist.py

-- Handles DSO table and observing list management, including alt-az/transit computations.

local dsos  = require "databases.dso"
local util  = require "utils"

local newTimer = require "utils" .newTimer
local calcs = require "lib.calcs"
local local_sidereal_time = calcs.local_sidereal_time

local sun_altitude = calcs.sun_altitude
_M.sun_altitude = sun_altitude    -- function()
local sun_time  = {value = 0, min = 0, max = 24}      -- slider for sun position

local math = math
      math.nan = math.abs(0/0)
      math.isnan = function(x) return x ~= x end

local int= math.floor

local np = math
      np.arcsin = math.asin
      np.arctan2 = math.atan2

local Loptions = {align = "left"}

local formatRA    = util.formatRA
local formatDEC   = util.formatDEC
local formatMag = function(x) return x == 0 and '' or x end


-------------------------
--
-- UTILITIES
--

local function ToHM(x)
  if x == '' then
    return ''
  end
  local h, m
  h = int(x)
  m = (x - h) * 60
  return "%2d:%02d" % {h, m}
end

local function fmt_diam(d)
  if d == 0 then return '' end
  if d < 1 then
    return '%4.1f"' % (d * 60)
  elseif d < 100 then
    return "%4.1f'" % d
  else
    return "%.1fº" % (d / 60)
  end
end

local qmap = {'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'}

local function quadrant(x)
  -- terrestrial direction
  local quad = int((x + 22.5) / 45) % 8 + 1   -- @akb, +1 since Lua is not zero-based indexing
  return qmap[quad]
end

--[[
class ObservingList(Component, JSettings):

    tab_name = 'Observatory'

    latitude = NumericProperty(42)
    longitude = NumericProperty(-2)


    def __init__(self):
        super().__init__()
        self.app = App.get_running_app()

        # time zone offset
        ts = time.time()
        self.utc_offset = (
            datetime.fromtimestamp(ts) - datetime.utcfromtimestamp(ts)
        ).total_seconds() / 3600.0

        Clock.schedule_once(self.load, 0)

--]]

--  dsos.DB = dsos.loader "dsos/"
--  _M.DB = dsos.DB
--  _M.objects = dsos.DB

--function _M.loader()
--  return dsos.DB
--end

      
--[[
    function loader(dt)
        self.objects = Component.get('Catalogues').get_basic_dsos()

        # return a COPY of the basic dsos to prevent unwanted side effects??
        # self.objects = {k: v.copy() 
        #     for k, v in Component.get('Catalogues').get_basic_dsos().items()}

        # load observing list (maps names to date added)
        try:
            with open(self.app.get_path('observing_list.json'), 'r') as f:
                observing_list = json.load(f)
        except:
            observing_list = {}
        logger.info(f'{len(observing_list)} on observing list')

        # load observing notes
        try:
            with open(self.app.get_path('observing_notes.json'), 'r') as f:
                observing_notes = json.load(f)
        except:
            observing_notes = {}
        logger.info(f'{len(observing_notes)} observing notes')

        # load previous observations if necc and count previous
        try:
            obs = Component.get('Observations').get_observations()
            previous = dict(Counter([v['Name'].lower() for v in obs.values() if 'Name' in v]))
        except Exception as e:
            logger.warning(f'problem loading previous DSOs ({e})')
            previous = {}
        logger.info(f'{len(previous)} unique previous observations found')
--]
        -- augment/combine DSO info
        for v in self.objects.values() do
            name = v['Name']
            v['Obs'] = previous.get(name.lower(), 0)
            v['Added'] = observing_list.get(name, '')
            v['List'] = 'Y' if name in observing_list else ''
            v['Notes'] = observing_notes.get(name, '')
            v['Other'] = v.get('Other', '')
        end
--]]

--[=[        try:
            self.compute_transits()
        except Exception as e:
            logger.exception(f'problem computing transits {e}')


    def on_close(self):
        self.save_observing_list()
        self.save_notes()


    def save_observing_list(self, *args):
        try:
            ''' bug? if self.objects is changed (with new objects) then
                it won't have Added field. Temporary fix but needs migration
                to Catalogues
            '''
            ol = {}
            for v in self.objects.values():
                if v.get('Added', ''):
                    ol[v['Name']] = v['Added']
            with open(self.app.get_path('observing_list.json'), 'w') as f:
                json.dump(ol, f, indent=1)
        except Exception as e:
            logger.exception(f'problem saving ({e})')
            toast('problem saving observing list')


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

--[[
    self = {
      longitude = x
      latitude = y,
      utc_offset = t,
      objects = database,
    }
--]]

local function compute_altaz(self, current_hours_offset)
  local RA, Dec = 2, 3
  local Quadrant, Az, Alt = 9, 10 ,11
  
  current_hours_offset = current_hours_offset or 0

  local t, rads
  t = os.time() + 3600 * current_hours_offset
  rads = math.pi / 180

  if self.last_time_changed then
    if t - self.last_time_changed < 5 then
      return
    end
  end
  self.last_time_changed = t

  local lst, lat

  local datetime = os.date("!*t",t)
  lst = local_sidereal_time(datetime, self.longitude)
  
  lat = self.latitude * rads
  local sinlat, coslat = np.sin(lat), np.cos(lat)
  
  local objs = self.objects
  for i = 1, #objs do
    local v = objs[i]
    local ra, dec
    ra = v[RA]
    dec = v[Dec] * rads

    local H = (-self.utc_offset * 15 + lst - ra) * rads
    local sinH, cosH = np.sin(H), np.cos(H)
    local az, alt
    az = 180 + (np.arctan2(sinH, cosH * sinlat - np.tan(dec) * coslat) / rads)
    alt = np.arcsin(sinlat * np.sin(dec) + coslat * np.cos(dec) * cosH) / rads

    v[Az] = math.isnan(az) and math.nan or int(az)
    v[Alt] = math.isnan(alt) and math.nan or int(alt)
    v[Quadrant] = math.isnan(az) and '' or quadrant(az)
  end
end

local function compute_transits(self)
  --from ch 15 of Meeus
  
  local RA, Dec = 2, 3
  local MaxAlt, Transit = 12, 13
  local elapsed = newTimer()
  
  --  apparent sidereal time at Greenwich at 0hUT
  local datetime, gst_0
  datetime = os.date "!*t"
  datetime.hour, datetime.min, datetime.sec = 0, 0, 0
  gst_0 = local_sidereal_time(datetime, 0)
    
  local objs = self.objects
  for i = 1, #objs do
    local v = objs[i]
    local ra, dec
    ra = v[RA]
    dec = v[Dec]

    local max_alt
    max_alt = 90 - self.latitude + dec
    max_alt = max_alt > 90 and 180 - max_alt or max_alt

    -- transit time: slight diff from Meeus since longitude negative from W here
    local transiting, m0
    transiting = np.abs(dec) < (90 - self.latitude)
    m0 = (ra - self.longitude - gst_0 + self.utc_offset * 15) / 15
    m0 = m0 % 24

    -- 10 ms or so
    v[MaxAlt] = int(max_alt)
    v[Transit] = transiting and ToHM(m0) or ''
  end
  _log (elapsed ('%.3f ms, computed transits for %d objects', #objs))
end



-------------------------
--
-- UPDATE GUI
--

local done

function _M: update(controls, watchlist)
  local cat = _M
  cat.objects = cat.objects or dsos.DB
  local layout = self.layout
  local function row(...) return layout: row(...) end
  local function col(...) return layout: col(...) end
  
  if not done then
    done = true
    local elapsed = newTimer()
    local settings = controls.settings
    local objects = {
--      objects = _M.dsos,
      objects = _M.DB,
      utc_offset = calcs.utc_offset,
      longitude = tonumber(settings.longitude.text) or 0,
      latitude = tonumber(settings.latitude.text) or 51.5}         -- defaults are approximation to Greenwich

    compute_altaz(objects)    
    _log(elapsed "%0.3f ms, ALT / AZ calculations")
    
    compute_transits(objects)
  end
  
  local ridx = cat.row_index 
  local sel = cat.highlight or {}
  cat.highlight = sel

  if self: Button("Select all", row(120, 30)) .hit then
    for i = 1, ridx.n do sel[ridx[i]] = true end
    sel.anchor = 1
  end
  col(15, 30)
  if self: Button("Deselect all", col(120, 30)) .hit then
    for i = 1, #_M.dsos do sel[i] = nil end
    sel.anchor = 1
  end

  col(50, 30)
  if self: Button("Add to Watchlist", col(170, 30)) .hit then
    watchlist:add(cat)
  end
  col(15, 30)
  if self: Button("Delete from Watchlist", col(170, 30)) .hit then
    watchlist:remove(cat)
  end

  -- sun position
  col(50, 30)
  local now = os.time()
  local hour_offset = sun_time.value
  local when = now + 3600 * hour_offset
  local settings = controls.settings
  local sun_elev = sun_altitude(os.date ("!*t", when), settings.latitude.text, settings.longitude.text)
  self: Label("sun: %.0fº" % sun_elev, col(100, 30))
  
  local x,y,w,h = col(220, 30)    -- position for slider
  self: Label(os.date("%d %b %H:%M", when), col(150, 30))
  if self: Slider(sun_time, x,y+10, w,14) .hovered then
    self: Label(math.floor(hour_offset), Loptions, x - 5 + w * hour_offset /24, y - 13, h)
  end
  
  local current = controls.object
  layout: reset(550,20, 10,10)     -- go back to top and insert button to set current object
  if self: Button("Set Current Object", col(150, 30)) .hit then
    current.text = (cat.DB[ridx[sel.anchor]] or {})[1] or ''
  end
  self: Label(current.text, Loptions, col(250, 30))

end


_M.cols = {  -- reflects the actual order of the source database
        {"Name", w = 210, },
        {"RA",   w = 75, format = formatRA, align = "right",  scale = 15, type = "number", },  -- scale, HH to DEG
        {"DEC",  w = 85, format = formatDEC, align = "right", type = "number", },
        {"Con",  w = 40, },
        {"OT ",  w = 40, },
        {"Mag",  w = 50, format = formatMag, type = "number", align = "center", },
        {"Diam", w = 50, format = fmt_diam, type = "number", align = "center", },
        {"Other",w = 240, },
        
        -- the following columns added later and computed dynamically
        {"Loc",     w = 40, align = "center", },    -- quadrant
        {"Az",      w = 40, align = "right",  },
        {"Alt",     w = 40, align = "right",  },
        
        -- these values are static and computed once after loading
        {"Max",     w = 40, align = "center", },    -- max altitude
        {"Transit", w = 60, align = "center", },
        
        -- the following added from the observing watch list
        {"Obs", w = 50, },
        {"List", w = 65, },
        }

_M.col_index = {1,5,4,2,3, 9,10,11,12,13, 6,7, 14,15, 8}


--[[
    def build(self):

        if not hasattr(self, 'objects'):
            self.load()

        cols = {
            'Name': {'w': 180, 'align': 'left', 'sort': {'catalog': ''}, 'action': self.new_from_list},
            'OT': {'w': 45},
            'Con': {'w': 45},
            'RA': {
                'w': 80,
                'align': 'right', 
                'type': float, 
                'val_fn': lambda x: x * 15, 
                'display_fn': lambda x: str(RA(x))
                },
            'Dec': {
                'w': 85, 
                'align': 'right', 
                'type': float, 
                'display_fn': lambda x: str(Dec(x))},
            'Quadrant': {'w': 40, 'align': 'center', 'label': 'Loc'},
            'Az': {'w': 40, 'align': 'center', 'type': float},
            'Alt': {'w': 40, 'align': 'center', 'type': float},
            'MaxAlt': {'w': 40, 'align': 'center', 'type': float, 'label': 'Max'},
            'Transit': {'w': 60, 'align': 'right', 'type': float, 'display_fn': ToHM},
            'Mag': {'w': 50, 'align': 'right', 'type': float},
            'Diam': {'w': 50, 'align': 'right', 'type': float, 'display_fn': fmt_diam},
            'Obs': {'w': 40, 'type': int},
            'List': {'w': 35},
            'Added': {'w': 65, 'sort': {'DateFormat': '%d %b'}},
            'Usr': {'w': 35, 'align': 'center'},
            'Notes': {'w': 100, 'input': True},
            'Other': {'w': 1, 'align': 'left'},
        }

        # time control widget
        ctrl = BoxLayout(orientation='horizontal', size_hint=(1, 1))

        # observing list buttons
        ctrl.add_widget(
            CButton(
                text='add to list', width=dp(100), on_press=self.add_to_observing_list
            )
        )
        ctrl.add_widget(
            CButton(
                text='del from list',
                width=dp(100),
                on_press=self.remove_from_observing_list,
            )
        )

        ctrl.add_widget(
            CButton(
                text='del from cat',
                width=dp(100),
                on_press=self.remove_from_catalogue,
            )
        )

        ctrl.add_widget(Label(size_hint_x=None, width=dp(40)))

        self.sun_time = TableLabel(text='', markup=True, size_hint_x=None, width=dp(80))

        ctrl.add_widget(self.sun_time)
        self.slider = MDSlider(
            orientation='horizontal',
            min=0,
            max=24,
            value=0,
            size_hint_x=None,
            width=dp(250),
        )
        self.slider.bind(value=self.time_changed)
        self.time_field = TableLabel(
            text=datetime.now().strftime('%d %b %H:%M'), size_hint_x=None, width=dp(160)
        )
        ctrl.add_widget(self.slider)
        ctrl.add_widget(self.time_field)
        self.time_changed(self.time_field, 0)

        logger.info('built')

        return Table(
            size=Window.size,
            data=self.objects,
            name='DSOs',
            cols=cols,
            update_on_show=False,
            controls=ctrl,
            on_hide_method=self.app.table_hiding,
            initial_sort_column='Name'
        )


    def time_changed(self, widgy, value):
        # user moves time slider
        if hasattr(self, 'update_event'):
            self.update_event.cancel()
        t0 = datetime.now() + timedelta(seconds=3600 * value)
        self.time_field.text = t0.strftime('%d %b %H:%M')

        sun_alt = sun_altitude(t0, self.latitude, self.longitude)
        self.sun_time.text = f'sun: {sun_alt:3.0f}\u00b0'
        try:
            self.compute_altaz(current_hours_offset=self.slider.value)
        except Exception as e:
            logger.exception(f'problem computing altaz {e}')

        if hasattr(self, 'table'):
            # update display since this is fast, but update table (reapply filters) when slider stops
            self.table.update_display()
            self.update_event = Clock.schedule_once(self.table.update, 0.5)


    @logger.catch()
    def show(self, *args):
        '''Called from menu to browse DSOs; open on first use'''
        if not hasattr(self, 'table'):
            self.table = self.build()
        self.app.showing = 'observing list'

        # redraw on demand when required
        if self.table not in self.app.gui.children:
            self.app.gui.add_widget(self.table, index=0)

        self.table.show()
        self.time_changed(self.time_field, 0)


    def new_from_list(self, row, *args):
        # User selects a row in the observing list table
        name = row.fields['Name'].text + '/' + row.fields['OT'].text
        self.table.hide()
        res = Component.get('Catalogues').lookup(name)
        if res is None:
            toast(f'Cannot find {name} in database')
        else:
            Component.get('DSO').new_DSO_name(res)


    def add_to_observing_list(self, *args):
        dn = datetime.now().strftime('%d %b')
        for s in self.table.selected:
            self.objects[s]['Added'] = dn
            self.objects[s]['List'] = 'Y'
        logger.info(f'added {len(self.table.selected)} objects')
        self.update_list()


    def remove_from_observing_list(self, *args):
        for s in self.table.selected:
            self.objects[s]['Added'] = ''
            self.objects[s]['List'] = ''
        logger.info(f'removed {len(self.table.selected)} objects')
        self.update_list()


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


    def update_list(self):
        self.save_observing_list()
        self.table.update()
        self.table.deselect_all()
--]]

return setmetatable(_M, {__index = 
    function(self, n) 
      if n == "DB" then
        local db = dsos.DB
        self.DB = db 
        self.objects = db
        return db
      end
    end})

-----

