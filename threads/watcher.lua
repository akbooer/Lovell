--
--  watcher.lua
--

local _M = {
  NAME = ...,
  VERSION = "2024.11.26",
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


local _log = require "logger" (_M)

local lf = require "love.filesystem"
local lt = require "love.timer"
local li = require "love.image"

local fits = require "lib.fits"
local ffi = require "ffi"
local newTimer = require "utils" .newTimer

local delay = 1     -- interval (seconds) to look for new files

local files = {}      -- the growing contents of the watched directory

--

local function readImageData(filename)
  local elapsed = newTimer()
  local ok, data, k, h = pcall(fits.read, filename)
  if not ok then 
--    _log("ERROR on read : " ..(data or '?'))
    return
  end
  local naxis1, naxis2= k["NAXIS1"], k["NAXIS2"]
  local ok2, imageData = pcall(li.newImageData, naxis1, naxis2, "r16", data)
  if not ok2 then
    _log("ERROR on imageData : " ..(imageData or '?'))
    return
  end
  data = nil
  local ptr = imageData:getFFIPointer()          -- grab byte pointer
  local byt = ffi.cast('uint8_t*', ptr)
  local r16 = ffi.cast('uint16_t*', ptr)

  -- swap bytes and add offsets from FITS file header
  local n = naxis1 * naxis2
  local j = 0
  local bzero = k["BZERO"]
  for i = 0, 2*n-1, 2 do
    byt[i], byt[i+1] = byt[i+1], byt[i]     -- swap bytes
    r16[j] = r16[j] + bzero
    j = j + 1
  end

  _log(elapsed ("%.3f ms, readImageData [%d x %d %s]", naxis1, naxis2, k.BAYERPAT or 'NONE'))
  return imageData, k, h
end

-- sanity check on file directories...
do
  _log ("USER: " .. lf.getUserDirectory())
  _log ("APP:  " .. lf.getAppdataDirectory())
  _log ("SAVE: " .. lf.getSaveDirectory())
  _log ("SRC:  " .. lf.getSource())
  _log ("WORK: " .. lf.getWorkingDirectory())
end

-- analyse file name for sub type and filter
local scan_name do
  local subtype = " darkflat flatdark dark bias flat dark light "
  local filter  = " red green blue lum spec l ha oiii sii r g b h o s  "
--  local COLORMAP = {Grayscale='mono', RAW16='mono'}
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

-- handle a variety of formats

local function parse_date(datetime)
  local d, t = datetime: match "(%d+%D%d%d%D%d%d)%D+(%d%d%D?%d%d)"   -- (YY)YY-MM-DD
  return (d and t) and (d..'  '..t) or datetime
end

--
--  main loop
--

local folder
local mountpoint = "watched/"
local subNumber  = 0


repeat
  lt.sleep(delay)

  local newFolder = newWatchFolder: pop()
  if newFolder then
    if newFolder == "EXIT" then break end
    if folder then lf.unmount(folder) end
    local mount = lf.mount(newFolder, mountpoint)
    if not mount then 
      _log "mount failed" 
    end
    _log("new folder " .. (newFolder))
    folder = newFolder
    files = {}              -- empty files list...
    newFITSfile: clear()    -- ...and the pipeline
    subNumber = 0
  end

  local dir = lf.getDirectoryItems (mountpoint)
  table.sort(dir)

  for _,file in ipairs(dir) do
    if file: match "%.fit$" and not files[file] then
      files[file] = true
      local imageData, keywords, headers = readImageData (mountpoint .. file)
      if not imageData then
        files[file] = false         -- mark as not read and try again later         
        _log "...incomplete file read..."
        break 
      end
      subNumber = subNumber + 1
      local k = keywords
      local subtype, filter = scan_name(file)
--      _log(subtype, filter)
      
      local datetime = k.DATE or k["DATE-OBS"] or k["DATE-AVG"] or k["DATE-END"] or k["DATE-LOC"] or k["DATE-STA"] or ''
      local date, time = parse_date(datetime)
      
      local new = {
        name = file, 
        subNumber = subNumber,
        folder = folder,
        imageData = imageData, 
        keywords = keywords,
        headers = headers,
        
        subtype = subtype,
        filter = filter,

        exposure =  k.EXPOSURE or k.EXPTIME or (k.EXPOINUS or 0) *1e-6,
        bayer = k.BAYERPAT, 
        temperature = k.TEMPERAT or k["SET-TEMP"] or k["SET_TEMP"] or k["CCD-TEMP"],
        date = date,
        time = time,
        gain = k.GAIN or k.EGAIN,
        creator = k.CREATOR or k.PROGRAM or k.SWCREATE,
        camera = k.INSTRUME,
      }
      
      newFITSfile: push(new)
      _log("new file read - " .. file)
    end
  end
until false

-----
