--
--  iframe.lua
--

local _M = {
  NAME = ...,
  VERSION = "2025.11.26",
  AUTHOR = "AK Booer",
  DESCRIPTION = "Image frame wrapper / reader for FITS files",
}

local love = _G.love

-- 2025.03.02  separate module from watcher (needed also for masters and observation reloads)
-- 2025.03.27  improve error returns for Lua io library reads (when reloading observations)
-- 2025.05.15  add keyword OFFSET to frame (for calibration)
-- 2025.11.26  fold frame subtype to lower case


local _log = require "logger" (_M)

local fits = require "lib.fits"

local lf = require "love.filesystem"


------------------------
--
--  UTILITIES
--

-- analyse file name for sub type and filter
local scan_name do
  local subtype = " dark bias flat dark light "
  local filter  = " red green blue lum spec l ha oiii sii r g b h o s  "
  local FILTERMAP = {green='G', red='R', blue='B', ha='H', oiii='O', sii='S', lum='L'}

  function scan_name(name)
    name = name: lower()
    local subt, filt
    for word in name: gmatch "%a+" do
      local pattern = table.concat {"%s(", word, ")%s"}    -- match isolated words
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


------------------------
--
--  READ IMAGE FRAME
--

function _M.read(folder, filename, mountpoint, skip_data)
  local f, err             -- file handle and error message
  local modtime      -- last modified time, if available
  
  if not skip_data then _log("reading new file - " .. filename) end
  if mountpoint then
    local path = mountpoint .. filename
    f = love.filesystem.newFile(path, 'r' )
    modtime = (lf.getInfo(path) or {}) .modtime           -- last modified date
  else
    f, err = io.open(folder .. '/' .. filename, 'rb')     -- standard io library
    if not f then return f, err end                       -- return error to caller
  end
   
  local imageData, keywords, headers
  if f then
    local reader = skip_data and "readImageInfo" or "readImageData"
    imageData, keywords, headers = fits [reader] (f, skip_data)
    f: close()
  end
  if not imageData then return end    -- fail silently

  local k = keywords
  local subtype, filter = scan_name(filename)
  local datetime = k.DATE or k["DATE-OBS"] or k["DATE-AVG"] or k["DATE-END"] or k["DATE-LOC"] or k["DATE-STA"] 
  local datestring, epoch = parse_date(datetime or modtime)
  local bayer = k.BAYERPAT
  
  subtype = k.SUBTYPE or k.SUB_TYPE or subtype or nil
  
  local iframe = {
    name = filename,              -- file name
    folder = folder,              -- file path
    
    imageData = imageData,        -- for conversion to image
    headers = headers,            -- raw FITS file headers
    keywords = keywords,          -- extracted from headers
    
    subtype = subtype: lower(),   -- bias, dark, light, flat, etc...
    filter = filter: upper(),     -- L, R, G, B, ...

    exposure =  k.EXPOSURE or k.EXPTIME or (k.EXPOINUS or 0) * 1e-6,    -- convert to seconds
    bayer = bayer, 
    temperature = k.TEMPERAT or k["SET-TEMP"] or k["SET_TEMP"] or k["CCD-TEMP"],
    date = datestring,
    epoch = epoch,
    gain = k.GAIN or k.EGAIN,
    offset = k.OFFSET,
    creator = k.CREATOR or k.PROGRAM or k.SWCREATE,
    camera = k.INSTRUME,
  }
  
  return iframe
  
end


return _M

-----

