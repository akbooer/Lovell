--
-- databaseGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.01.21"
  _M.DESCRIPTION = "database GÜI"

local _log = require "logger" (_M)

-- 2024.11.23  Version 0
-- 2025.01.21  use external spreadsheet widget


local love = _G.love
local lg = love.graphics

local suit = require "suit"
local mergesort = require "lib.mergesort"

local databases   = require "databases"
local spreadsheet = require "guillaume.spreadsheet"


local self = suit.new()     -- make a new SUIT instance for ourselves

local Loptions = {align = "left"}

local formatRA  = databases.formatRA
local formatDEC = databases.formatDEC
    
    
-------------------------
--
-- SORTERS
--

local sorterType = {}

function sorterType.text(data, col, dir)
  local compare = dir 
          and function(a,b)
                a, b = a[col], b[col]
                return a < b
              end
          or  function(a,b) 
                a, b = a[col], b[col]
                return a > b
              end
  mergesort(data, compare)
end

function sorterType.number(data, col, dir)
  local compare = dir 
          and function(a,b) 
                a, b = tonumber(a[col]) or 0, tonumber(b[col]) or 0
                return a < b
              end
          or  function(a,b) 
                a, b = tonumber(a[col]) or 0, tonumber(b[col]) or 0
                return a > b 
              end
  mergesort(data, compare)
end

-- generate an array of filters/sorters for the columns
-- these return Input box text field and filter function
local function sorters(sorts)
  local sorters = {}
  local n = select('#', unpack(sorts))    -- may contain some nil entries
  for col = 1, n do
    local s = sorterType[sorts[col]]
    if s then
      sorters[col] = {sorter = s, reverse = false} 
    end
  end
  return sorters
end

-------------------------
--
-- FILTERS
--

local filterType = {}

function filterType.text(data, col, text)
  if #text == 0 then return data end      -- nothing to do
  text = text:lower() : gsub('*','.*')    -- change wildcard to Lua string version
  local new = {}
  for i = 1, #data do
    local row = data[i]
    new[#new+1] = row[col]: lower(): match(text) and row or nil
  end
--  _log("test", text, "matches: ",  #new)
  return new
end

-- search text can be >n <n 
function filterType.number(data, col, text)
  local inequality, value = text: match "([<>])%s*([%+%-]?%d+%.?%d*)"
  _log("filter", inequality, value)
  value = tonumber(value)
  if not value then return data end      -- nothing to do
  local new = {}
  if inequality == '<' then
    for i = 1, #data do
      local row = data[i]
      new[#new+1] = tonumber(row[col]) < value and row or nil
    end
  elseif inequality == '>' then
    for i = 1, #data do
      local row = data[i]
      new[#new+1] = tonumber(row[col]) > value and row or nil
    end
  else
    for i = 1, #data do
      local row = data[i]
      new[#new+1] = tonumber(row[col]) == value and row or nil
    end
  end
  return new
end

-- generate an array of filters for the columns
-- these return Input box text field and filter function
local function filters(filts)
  local filters = {}
  local n = select('#', unpack(filts))    -- may contain some nil entries
  for col = 1, n do
    local f = filterType[filts[col]]
    if f then
      filters[col] = {text = '', filter = f}
    end
  end
  return filters
end


-------------------------
--
-- UPDATE / DRAW
--

local DBnames = {"DSO", "Observations", "Watch list", "Calibration", "Telescopes"}

local function trim(x) return (x or '') : lower() : gsub(' ','') end

local lookup = {}
for i,n in ipairs(DBnames) do 
  lookup[trim(n)] = i
end

local catalog = {   -- databases
  
    { -- DSO
      source = databases.dsos,
      col_width = {250, 100, 100, 60, 60, 60, 60, 300},     -- column widths 
      col_format = {nil, formatRA, formatDEC},              -- optional formatting
      filter = filters {"text", "number", "number", "text", "text", "number", "number"},
      sorter = sorters {"text", "number", "number", "text", "text", "number", "number"},
    },
    
    { -- Observations 
      source = databases.observations,
      col_width = {200, 100, 200, 400},
      filter = filters {"text", "text", "text"},
      sorter = sorters {"text", "text", "text"},
    },
   
    { -- Watch list
      db = {},
      col_width = {200, 100, 100, 80, 80, 80, 80, 300}},

    { -- Calibration 
      db = {},
      },
      
    { -- Telescopes 
      source = databases.telescopes,
      col_width = {200, 100, 200}},
    
  }


function _M.update()
  local w, h = lg.getDimensions()
  local layout = self.layout
  layout:reset(10, 20)            -- position the layout origin...
  layout:padding(10,10)           -- ...and put extra pixels between cells in each direction
  
  -- select catalogue from specified subpage
  local main, subpage = _M.get()
  subpage = lookup[trim(subpage)]
  if main == "database" and subpage then 
    DBnames.selected = subpage 
    _M.set "database"
  end
  layout:col(190, 30)             -- leave space for CLOSE button
  self: Dropdown(DBnames, layout:col(150, 30))
  local i = DBnames.selected or 1
  local cat = catalog[i]
  
  -- ensure database is loaded and row index set
  cat.db = cat.db or cat.source.DB
  local db = cat.db

  spreadsheet(self, cat, 10, 70, w,h)  
  
  local grid = cat.grid

  -- add buttons at bottom of DSO table
  
  if i == 1 then        
    local sel = cat.highlight or {}
    cat.highlight = sel
    
    if self: Button("Select all", layout: row(120, 30)) .hit then
      for i = 1, #grid.data do sel[i] = true end
      sel.anchor = 1
    end
    layout: col(30, 30)
    if self: Button("Deselect all", layout: col(120, 30)) .hit then
      for i = 1, #grid.data do sel[i] = nil end
      sel.anchor = 1
    end
    
    layout: col(80, 30)
    self: Button("Add to Watchlist", layout: col(200, 30))
    layout: col(30, 30)
    self: Button("Delete from Watchlist", layout: col(200, 30))
  end


  layout: reset(10,20, 10,10)     -- go back and insert DB stats
  layout: col(350, 30)            -- leave space for CLOSE button and DB selector
  self: Label("%d of %d " % {#cat.grid.data, #db}, Loptions, layout:col(200, 30))
  
end


function _M.draw()
  self: draw()
end

 
-------------------------
--
-- MOUSE (for scrolling the spreadsheet)
--

function _M.wheelmoved(...)
  spreadsheet.wheelmoved(...)
end

-------------------------
--
-- KEYBOARD
--

function _M.textinput(t)
  self: textinput(t)
end

function _M.keypressed(key)
  self: keypressed(key)
end

return _M

-----
