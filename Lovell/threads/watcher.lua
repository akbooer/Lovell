--
--  watcher.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.05.31",
  AUTHOR = "AK Booer",
  DESCRIPTION = "THREAD watches a folder for new FITS files",
}

local love = _G.love

local newWatchFolder  = love.thread.getChannel "newWatchFolder"
local newFITSfile     = love.thread.getChannel "newFITSfile"

-- 2024.10.23  use love.filesystem open/close, rather than Lua's io library
-- 2024.10.31  catch read errors and re-try
-- 2024.11.18  improve error checking
-- 2024.11.25  fix operation on missing EXPOINUS field
-- 2024.11.26  parse filename to provide filter and subtype information
-- 2024.12.03  return epoch, for session id
-- 2024.12.04  add additional delay after failed read, to allow write (presumably) to finish
-- 2024.12.05  add metadata from other capture software
-- 2024.12.08  move readImageData() to fits.lua
-- 2024.12.31  fix error in os.date() string which crashed LÖVE on Windows
-- 2024.12.31  allow .fits files as well as .fit (thanks @Steve in Boulder)

-- 2025.01.05  limit idle cycles (dramatically reduce CPU usage for this thread)
-- 2025.01.26  remove sub numbering, use 'newfolder' flag instead
-- 2025.03.02  move reader to new iframe module
-- 2025.05.31  allow .fit, .fits, and .fts files


local _log = require "logger" (_M)

local iframe  = require "iframe"        -- Lövell image frame
local json    = require "lib.json"

--[[
      NB: When a Thread is started, it only loads love.data, love.filesystem, and love.thread module. 
      Every other module has to be loaded with require. 
--]]

local lf = require "love.filesystem"
local lt = require "love.timer"

local IDLE = 1 / 10   -- limit idle cycles to ten per second

local DELAY = 2       -- interval (seconds) to rescan watched folder for new files

local files = {}      -- the growing list of read files in the watched folder

local mountpoint = "watched/"

local empty = _G.READONLY {}

-- sanity check on file directories...
do
  _log ("USER: " .. lf.getUserDirectory())
  _log ("APP:  " .. lf.getAppdataDirectory())
  _log ("SAVE: " .. lf.getSaveDirectory())
  _log ("SRC:  " .. lf.getSource())
  _log ("WORK: " .. lf.getWorkingDirectory())
end


------------------------
--
-- METADATA, for Jocular or Canisp files - read it if it's there in the dropped folder
--

local function readMetadata(filename)
  local metadata = json.read(mountpoint .. filename)  
  if metadata then
    metadata.name = metadata.Name        -- some confusion over naming styles!
  end
  return metadata
end

------------------------
--
--  MAIN LOOP
--

local folder          -- current watched folder
local first           -- new folder flag

local wakeup = 0

repeat
  
  lt.sleep(IDLE)       -- 2025.01.05  throttle idle cycles 

  ------------------------
  --
  --  NEW FOLDER
  --
  
  local metadata = empty
  local newFolder = newWatchFolder: pop()
  if newFolder then
    if newFolder == "EXIT" then break end
    folder = newFolder
    first = true
    files = {}              -- empty files list...
    newFITSfile: clear()    -- ...and the pipeline
    wakeup = 0              -- reset wakeup time
    
    metadata = readMetadata "info3.json"      -- Jocular
            or readMetadata "metadata.json"   -- Canisp
            or empty
  end

  ------------------------
  --
  --  REFRESH FOLDER DIRECTORY
  --
  
  local t = lt.getTime()
  if t > wakeup then
    wakeup = lt.getTime() + DELAY
    local dir = lf.getDirectoryItems (mountpoint)
--    table.sort(dir)
    
    ------------------------
    --
    --  READ NEW FILES
    --
    
    local retries = 0
    for _, file in ipairs(dir) do
      if file: match "%.fi?ts?$" and not files[file] then
        files[file] = true
        local frame = iframe.read(folder, file, mountpoint)
        if not frame then
          retries = retries + 1
          if retries < 10 then
            files[file] = false         -- mark as not read and try again later         
            _log "...incomplete file read..."
            lt.sleep(DELAY)             -- wait a bit more
          else
            _log("too many retries reading " .. file)
          end
          break 
        end
        
        -- add extra metadata, if present
        frame.telescope = metadata.telescope
        frame.object = metadata.name

        -- flag start of new stack sequence
        frame.first = first
        first = false
        
        newFITSfile: push(frame)
      end
    end
  end
  
until false

-----
