--
--  readwer.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.11.05",
  AUTHOR = "AK Booer",
  DESCRIPTION = "THREAD watches or reloads FITS file folders",
}

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

-- 2026.11.01  renamed "reader", complete rewrite, combining "watcher" and "reloader" threads
-- 2026.11.03  add RELOAD function foro both READ and WATCH modes
-- 2026.11.05  move filesystem mount logic to here from main module


local _log = require "logger" (_M)

local iframe  = require "iframe"        -- Lövell image frame
local json    = require "lib.json"

--[[
      NB: When a Thread is started, it only loads love.data, love.filesystem, and love.thread module. 
      Every other module has to be loaded with require. 
--]]

local love = _G.love

local lf = love.filesystem
local lt = require "love.timer"

local reader      = love.thread.getChannel "reader"         -- command input
local newFITSfile = love.thread.getChannel "newFITSfile"    -- data output

local IDLE  = 1 / 10    -- limit idle cycles to ten per second
local DELAY = 2         -- interval (seconds) to rescan watched folder for new files
local RETRY = 10        -- maximum number of attempts to read file


local empty = _G.READONLY {}

-- sanity check on file directories...
do
  _log ("USER: " .. lf.getUserDirectory())
  _log ("APP:  " .. lf.getAppdataDirectory())
  _log ("SAVE: " .. lf.getSaveDirectory())
  _log ("SRC:  " .. lf.getSource())
  _log ("WORK: " .. lf.getWorkingDirectory())
end


local frame           -- the current frame

------------------------
--
--   UTILITIES
--

local function is_fits(name)
  return name: lower() : match "%.fi?ts?$" and name or nil
end

-- limit cycle rate of main loop
local throttle do
  
  local last_time = 0
  
  function throttle(delay)
    local t = lt.getTime()
    local wait = delay - (t - last_time)
    last_time = t
    if wait > 0 then
      lt.sleep(wait)
    end
  end
  
end

  
-- message can be one or two word string, or table with one or more elements, 
-- the first of which should be a string
local function get_message()
  local message = reader: pop()
  if type(message) == "table" then
    return unpack(message)
  elseif type(message) == "string" then
    return message: match "(%S+)%s*(%S*)"
  end
end


local function send_frame()
  if not frame then return end
  if newFITSfile: getCount() == 0 then            -- wait for previous to be processed
    newFITSfile: push(frame)
    frame = nil                                   -- say we're done with it
  end
end


------------------------
--
--  READER of previous observations
--

local Reader  = {}

do
  
  local sep = package.config:sub(1,1)                             -- OS-dependent path separator
  local get = {['/']  = "ls '%s'", ['\\'] = 'dir "%s" /b'}        -- wrap in quotes to allow spaces in folder path
  local folder
  local dir = {i = 0}
  
  -- the info parameter is, in fact, a complete table from the observation database
  function Reader: directory(info)
    
    if not info or #info == 0 then return end
    
    self.info = info
    folder = info[12]
    _log("READING", folder)
    
    dir = {i = 0}
    local cmd = get[sep] % folder
    local f = io.popen (cmd)                        -- read folder directory
    for item in f: lines() do
      item = item: gsub("\\",'/')                   -- ensure consistent path separators
      dir[#dir+1] = is_fits(item)                   -- only consider FITS files
    end
    f: close()
    if #dir == 0 then _log "no files found" end
    
  end


  function Reader: read()
    
    local i = dir.i + 1
    if i > #dir then return end                   -- we've read them all
    dir.i = i
    
    frame = iframe.read(folder, dir[i])   
        
    if not frame then 
      _log ("ERROR reading", dir[i])
    else
      -- add extra metadata
      local info = self.info
      frame.telescope = info[10]
      frame.object = info[1]
      frame.first = i == 1                        -- flag start of new stack sequence
    end
      
  end
  
  
  function Reader: reload()
    dir.i = 0                   -- reset files read counter
  end
  
end

------------------------
--
--  WATCHER of new observations
--

local Watcher = {}

do
  local folder                      -- current watched folder
  local metadata
  local files                       -- the growing list of read files in the watched folder

  local mountpoint = "watched/"     -- LÖVE file system mountpoint for watched folder
  local wakeup = 0
  local dir = {i = 0}

  -- METADATA, for Jocular or Canisp files - read it if it's there in the dropped folder
  local function readMetadata(filename)
    local metadata = json.read(mountpoint .. filename)  
    if metadata then
      metadata.name = metadata.name or metadata.Name        -- some confusion over naming styles!
    end
    return metadata
  end

  local function mount(path)  
    if folder then 
      lf.unmount(folder) 
      folder = nil
    end
    local mount = lf.mount(path, mountpoint)
    if mount then 
      folder = path
    else
      _log "mount failed" 
    end
  end

  function Watcher: directory(path)
    
    -- read new directory with metadata, if present
    if path and #path > 0 then 
      mount(path)
      if folder then
        _log("WATCHING", folder)
        files = {first = true}      
        wakeup = 0                  -- reset wakeup time
        
        metadata = readMetadata "info3.json"      -- Jocular
                or readMetadata "metadata.json"   -- Canisp
                or empty
              
      end
    end

    --  refresh folder directory frequently, watching for new files
    local t = lt.getTime()
    if t > wakeup then
      wakeup = t + DELAY
      local newdir = lf.getDirectoryItems (mountpoint)
      dir = {i = 0}
      for _, item in ipairs(newdir) do
        dir[#dir+1] = is_fits(item)                   -- only consider FITS files
      end
    end
    
  end
      
  
  function Watcher: read()
    
    while dir.i < #dir do                         -- directory is rescanned every DELAY seconds
      dir.i = dir.i + 1
      local file = dir[dir.i]
      local n = files[file] or RETRY              -- maximum number of retries
      
      if n > 0 then
        n = n - 1
        frame = iframe.read(folder, file, mountpoint)
        if frame then
          files[file] = 0                         -- say we're done with this file
          -- add extra metadata, if present
          frame.telescope = metadata.telescope
          frame.object = metadata.name
          frame.first = files.first               -- flag start of new stack sequence
          files.first = false
        else
          files[file] = n
          if n > 0 then
            _log "...incomplete file read..."
          else
            _log("too many retries reading " .. file)
          end
        end
        break 
        
      end
    end
  end
  
  
  function Watcher: reload()
    files = {first = true}                  -- say we haven't seen any yet
  end

end


------------------------
--
--  MODES - READ or WATCH
-- each mode implements its own RELOAD function
--

local mode = {
        MODE = "READ",         -- the current mode
        WATCH =  Watcher,
        READ = Reader,
        }

function mode: set(new_mode)
  if not new_mode then return end
  if new_mode == "RELOAD" then
    self[self.MODE] :reload()
    _log "RELOAD"
  else
    self.MODE = new_mode
  end
end

function mode: directory(path)
  self[self.MODE] :directory(path)
end

function mode: read()
  if frame then return end                      -- haven't sent the previous one
  self[self.MODE] :read()
end


------------------------
--
--  MAIN LOOP
--

repeat
  
  throttle(IDLE)                              -- throttle idle cycles 
  
  local command, newfolder = get_message()    -- possibly get a messsage
  
  mode: set(command)                          -- possibly change mode
  
  mode: directory(newfolder)                  -- possibly update directory
  
  mode: read()                                -- possibly read next file
  
  send_frame()                                -- possibly send
    
until command == "EXIT"

-----
