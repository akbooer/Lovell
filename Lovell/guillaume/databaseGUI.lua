--
-- databaseGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2026.06.06"
  _M.DESCRIPTION = "GUI - databases"

local _log = require "logger" (_M)

-- 2024.11.23  Version 0

-- 2025.01.21  use external spreadsheet widget
-- 2025.02.05  add "Set Current Object" from selection
-- 2025.02.10  refactor spreadsheet parameters
-- 2025.05.21  rename calibration database to masters

-- 2026.06.06  add FITS header database


local love = _G.love
local lg = love.graphics

local suit = require "suit" .new()     -- make a new SUIT instance for ourselves

local spreadsheet = require "guillaume.spreadsheet"

local dso_obslist   = require "databases.observinglist"
local observations  = require "databases.obsessions"
local masters       = require "databases.masters"
local telescopes    = require "databases.telescopes"
local headers       = require "databases.fitsheaders"
local controls      = require "controls"

local layout = suit.layout

--  local function row(...) return layout: row(...) end
local function col(...) return layout: col(...) end

local Loptions = {align = "left"}
    

-------------------------
--
-- INIT
--

local DBnames = {"DSO", "Observations", "Calibration", "Telescopes", "FITS Headers", id = "DB: ", selected = 1}

controls.DBnames = DBnames      -- make external for database change commands

local lookup = {}             -- add index of names
for i,n in ipairs(DBnames) do 
  lookup[n: lower()] = i
end
DBnames.lookup = lookup   -- save the index

local catalog = {   -- databases
    dso_obslist,    -- DSOs / observing list
    observations,   -- previous observations
    masters,        -- Masters
    telescopes,     -- Telescopes 
    headers,        -- FITS headers
  }

-------------------------
--
-- UPDATE / DRAW
--

local cat

function _M.update()
  local W, H = lg.getDimensions()
  layout:reset(10, 20, 10,10)
  col(200, 30)                                    -- leave space for CLOSE button
  
  suit: Choosable(DBnames, col(150, 30))          -- select database
  cat = catalog[DBnames.selected or 1]
  local db = cat.load()                           -- ensure database is loaded
  
  suit: Label("%d of %d " % {db.row_index and db.row_index.n or 0, #db.data}, Loptions, col(155, 30))
 
  spreadsheet(suit, db, 10, 70, W,H)  
 
  if cat.update then cat.update(suit) end         -- apply any database updates
  
end


function _M.draw()
  suit: draw()
end

 
-------------------------
--
-- MOUSE (for scrolling the spreadsheet)
--

function _M.wheelmoved(...)
  spreadsheet.wheelmoved(...)
end

function _M.mousereleased(...) -- x, y, button, istouch, presses )
  if cat.mousereleased then
    cat.mousereleased(...)    -- for double click to load data
  end
end
  
-------------------------
--
-- KEYBOARD
--

function _M.textinput(t)
  suit: textinput(t)
end

function _M.keypressed(key)
  suit: keypressed(key)
end

return _M

-----
