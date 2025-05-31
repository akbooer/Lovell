--
-- databaseGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.05.21"
  _M.DESCRIPTION = "database GUI"

local _log = require "logger" (_M)

-- 2024.11.23  Version 0

-- 2025.01.21  use external spreadsheet widget
-- 2025.02.05  add "Set Current Object" from selection
-- 2025.02.10  refactor spreadsheet parameters
-- 2025.05.21  rename calibration database to masters


local love = _G.love
local lg = love.graphics

local suit = require "suit"

local obslist     = require "observinglist"
local databases   = require "databases"
local spreadsheet = require "guillaume.spreadsheet"



local self = suit.new()     -- make a new SUIT instance for ourselves
local layout = self.layout

local Loptions = {align = "left"}
    

-------------------------
--
-- UPDATE / DRAW
--

local DBnames = {"DSO", "Observations", "Calibration", "Telescopes"}

local function trim(x) return (x or '') : lower() : gsub(' ','') end

local lookup = {}
for i,n in ipairs(DBnames) do 
  lookup[trim(n)] = i
end

local catalog = {   -- databases
  
    obslist,                  -- DSOs / observing list
    databases.observations,   -- previous observations
    databases.masters,        -- Masters
    databases.telescopes,     -- Telescopes 
  }


function _M.update()
  local w, h = lg.getDimensions()
  layout:reset(10, 20, 10,10)           -- position layout with padding
  
--  local function row(...) return layout: row(...) end
  local function col(...) return layout: col(...) end
  
  -- select catalogue from specified subpage
  local main, subpage = _M.get()
  subpage = lookup[trim(subpage)]
  if main == "database" and subpage then 
    DBnames.selected = subpage 
    _M.set "database"
  end
  col(200, 30)                            -- leave space for CLOSE button
  self: Dropdown(DBnames, col(150, 30))
  local i = DBnames.selected or 1
  
  local cat = catalog[i]
  
  cat.DB = cat.DB or cat.load()          -- ensure database is loaded

  self: Label("%d of %d " % {cat.row_index and cat.row_index.n or 0, #cat.DB}, Loptions, col(155, 30))
 
  spreadsheet(self, cat, 10, 70, w,h)  
 
  if cat.update then cat.update(self) end
  
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
