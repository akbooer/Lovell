--
--  reloader.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.03.27",
  AUTHOR = "AK Booer",
  DESCRIPTION = "THREAD reloads a previous observation",
}

--[[

  The difference between this thread and watcher is that here the folder directory
  is static, and only read once, and no Jocular/Canisp metadata files are read
  since the required information should already be in the session database.
  
--]]

local love = _G.love

--[[
      NB: When a Thread is started, it only loads love.data, love.filesystem, and love.thread module. 
      Every other module has to be loaded with require. 
--]]

local le = require "love.event"
local lt = require "love.timer"

local reloadFolder    = love.thread.getChannel "reloadFolder"   -- receive a new folder to reload
local newFITSfile     = love.thread.getChannel "newFITSfile"    -- send individual FITS files for processing

--- 2025.03.02 Version 0, derived from watcher


local _log = require "logger" (_M)

local iframe  = require "iframe"        -- Lövell image frame

local sep = package.config:sub(1,1)                             -- OS-dependent path separator

local get = {['/']  = "ls '%s'", ['\\'] = 'dir "%s" /b'}        -- wrap in quotes to allow spaces in folder path

local IDLE = 1 / 10   -- limit idle cycles to ten per second

local function waitFor(channel)
  while channel: getCount() ~= 0 do                             -- wait for previous to be processed
    lt.sleep(IDLE)
  end
end

local function getfiles(folder)
  local dir = {}
  local f = io.popen (get[sep] % folder)                        -- read folder directory
  for item in f: lines() do
    item = item: gsub("\\",'/')                                 -- ensure consistent path separators
    dir[#dir+1] = item: match "%.fits?$" and item or nil        -- only consider FITS files
  end
  f: close()
  if #dir == 0 then _log "no files found" end
  return dir
end

------------------------
--
--  MAIN LOOP
--

repeat
    
  local info = reloadFolder: demand()                         -- wait for reload message  
  if info == "EXIT" then break end

  local folder = info[12]
  _log("FOLDER", folder)
  
  le.push("directorydropped", "settings")   -- stop watcher with dummy place that will never have a FITS file
  lt.sleep(IDLE)
    
  local first = true
  for _, filename in ipairs(getfiles(folder)) do                -- read each file
      
    local frame = iframe.read(folder, filename)      
    waitFor(newFITSfile)                                        -- wait for any previous to be processed    
    frame.first = first                                         -- flag start of new stack sequence
    first = false
    
    -- add extra metadata
    frame.telescope = info[10]
    frame.object = info[1]
    
    newFITSfile: push(frame)                                    -- insert into processing pipeline
      
  end

until false

-----
