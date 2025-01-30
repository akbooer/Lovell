--
--  watcher.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.01.26",
  AUTHOR = "AK Booer",
  DESCRIPTION = "THREAD watches a folder for new FITS files",
}

--[[
      NB: When a Thread is started, it only loads love.data, love.filesystem, and love.thread module. 
      Every other module has to be loaded with require. 
--]]

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


local _log = require "logger" (_M)

local lf = require "love.filesystem"
local lt = require "love.timer"

local fits = require "lib.fits"
local json = require "lib.json"

local IDLE = 1 / 10   -- limit idle cycles to ten per second

local DELAY = 2       -- interval (seconds) to rescan watched folder for new files

local files = {}      -- the growing list of read files in the watched folder

local mountpoint = "watched/"

local empty = _G.READONLY {}

------------------------
--
-- metadata reader - read it if it's there in the dropped folder
--
local function readMetadata(filename)
  local metadata = json.read(mountpoint .. filename)  
  if metadata then
    metadata.name = metadata.Name        -- some confusion over naming styles!
  end
  return metadata
end

-----

-- analyse file name for sub type and filter
local scan_name do
  local subtype = " dark bias flat dark light "
  local filter  = " red green blue lum spec l ha oiii sii r g b h o s  "
  local FILTERMAP = {green='G', red='R', blue='B', ha='H', oiii='O', sii='S', lum='L'}

  function scan_name(name)
    name = name: lower()
    local subt, filt
    for word in name: gmatch "%a+" do
      local pattern = "%s(" .. word .. ")%s"    -- math isolated words
      subt = subt or subtype: match(pattern)
      filt = filt or filter:  match(pattern)
    end
    return subt or "light", FILTERMAP[filt] or filt or 'L'
  end
end

-- handle a variety of date formats
local function parse_date(datetime)
  local epoch
  local y, m, d, H, M
  if type(datetime)  == "string" then
    y,m,d, H, M = datetime: match "(%d+)%D(%d%d)%D(%d%d)%D+(%d%d)%D?(%d%d)"   -- (YY)YY-MM-DD
    if y then
      y = (#y == 2) and ("20" .. y) or y
      datetime = os.time {year = y, month = m, day = d, hour=H, min=M, isdst = false}
    end
  end
  if type(datetime) == "number" then
    epoch = datetime
    datetime = os.date("%d-%b-%Y  %H:%M", datetime): gsub("^0", '')      -- Coordinated Universal Time
  else
    datetime = ''
  end
  return datetime, epoch    -- string representation, and epoch
end

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
--  MAIN LOOP
--

local folder          -- current watched folder
local first           -- new folder flag

local wakeup = 0

repeat
  
  lt.sleep(IDLE)       -- 2025.01.05  limit idle cycles 

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
    
    metadata = readMetadata "info3.json" 
            or readMetadata "metadata.json" 
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
      if file: match "%.fits?$" and not files[file] then
        files[file] = true
        local path = mountpoint .. file
        _log("new file read - " .. file)
        local imageData, keywords, headers = fits.readImageData (path)
        if not imageData then
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
        local k = keywords
        local subtype, filter = scan_name(file)
        
        local datetime = k.DATE or k["DATE-OBS"] or k["DATE-AVG"] or k["DATE-END"] or k["DATE-LOC"] or k["DATE-STA"] 
        local modtime = (lf.getInfo(path) or {}) .modtime   -- last modified date
        local datestring, epoch = parse_date(datetime or modtime)
        
        ------------------------
        --
        --  create new IMAGE FRAME
        --
        
        local frame = {
          name = file,                  -- file name
          folder = folder,              -- file path
          first = first,          -- start of new stack sequence
          
--          subNumber = subNumber,
          imageData = imageData,        -- for conversion to image
          headers = headers,            -- raw FITS file headers
          keywords = keywords,          -- extracted from headers
          
          subtype = subtype,            -- bias, dark, light, flat, etc...
          filter = 'lum',  -- filter,              -- lum, red, green, blue, etc... * * * *

          exposure =  k.EXPOSURE or k.EXPTIME or (k.EXPOINUS or 0) * 1e-6,
          bayer = k.BAYERPAT, 
          temperature = k.TEMPERAT or k["SET-TEMP"] or k["SET_TEMP"] or k["CCD-TEMP"],
          date = datestring,
          epoch = epoch,
          gain = k.GAIN or k.EGAIN,
          creator = k.CREATOR or k.PROGRAM or k.SWCREATE,
          camera = k.INSTRUME,
          
          -- add extra metadata, if present
          telescope = metadata.telescope,
          object = metadata.name,
        }
        
        first = false
        newFITSfile: push(frame)
      end
    end
  end
until false

-----
