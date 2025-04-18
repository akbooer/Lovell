--
-- FITS reader

--jit.off(true, true)

local _M = {
    NAME = ...,
    VERSION = "2025.04.08",
    AUTHOR = "AK Booer",
    DESCRIPTION = "FITS file utilities",
  }

-- 2024.09.25  Version 0, @akbooer
-- 2024.11.08  use love.filesystem
-- 2024.11.18  improve error checking
-- 2024.11.29  read() now takes an opened file object, rather than a filename
-- 2024.12.08  move readImageData() here from watcher.lua (for calibration use by masters.lua)

-- 2025.03.01  readImageData() now takes an opened file object (file system agnostic)
-- 2025.03.10  fix handling of unquoted string in header (Starlight Live DATE has no surrounding quotes)
-- 2025.03.27  change check for full file read (for lua.io and love.filesystem library compatibility)
-- 2025.04.08  add 32-bit handling


local _log = require "logger" (_M)

local bit = require "bit"
local ffi = require "ffi"
local newTimer = require "utils" .newTimer

local li = require "love.image"

local love = _G.love
local ld = love.data

-- these read routines are called with an open file handle, to remain file system agnostic...
-- ...usable by both love.filesystem.open() and Lua's native io.open()
-- As such, the file handle should be closed by the caller after these routines return

--[[
    
  see: https://fits.gsfc.nasa.gov/fits_primer.html

  Every HDU consists of an ASCII formatted `Header Unit' followed by an optional `Data Unit'. 
  Each header or data unit is a multiple of 2880 bytes long (36 x 80). If necessary, the header or data unit 
  is padded out to the required length with ASCII blanks or NULLs depending on the type of unit.
   
  Each header unit contains a sequence of fixed-length 80-character keyword records which have the general form:

    KEYNAME = value / comment string 

  The keyword names may be up to 8 characters long and can only contain uppercase letters A to Z, 
  the digits 0 to 9, the hyphen, and the underscore character. 

  The keyword name is (usually) followed by an equals sign and a space character in columns 9 and 10 of the record, 
  followed by the value of the keyword which may be either :
  
    an integer, 
    a floating point number, 
    a complex value (i.e., a pair of numbers), 
    a character string (enclosed in single quotes), 
    or a Boolean value (the letter T or F). 
    
  Some keywords, (e.g., COMMENT and HISTORY) are not followed by an equals sign and 
  in that case columns 9 - 80 of the record may contain any string of ASCII text. 

--]]

-- trim leading and trailing blanks
local function trim(s)
  return s: match "^%s*(.-)%s*$"
end


local function convert_type(v)
  local value = tonumber(v)                 -- note that this is nil for pairs of numbers (ie. complex values)
  if value then return value end            -- it IS a number
  
  value = v: match "%s*'([^']*)"
  if value then return trim(value) end            -- it's a quoted string
  
  value = v: match "%s+([TF])%s+"
  if value then return value == 'T' end     -- true or false
  
  -- otherwise, just return it as a string value
  return v
end

--[[

  Each header unit begins with a series of required keywords that specify the size and format of the following data unit. 
  A 2-dimensional image primary array header, for example, begins with the following keywords:

    SIMPLE  =                    T / file conforms to FITS standard
    BITPIX  =                   16 / number of bits per data pixel
    NAXIS   =                    2 / number of data axes
    NAXIS1  =                  440 / length of data axis 1
    NAXIS2  =                  300 / length of data axis 2

--]]

function _M.readHeaderUnit(file) 
  local done
  local keywords = {}
  local headers = {}
  -- there may be multiple blocks 
  repeat
    for _ = 1, 36 do
      local record = file: read (80)
      if not done then
        headers[#headers+1] = record
--        local name, equals, value, slash, comment = record: match "([A-Z0-9-_]+)%s*(=?)([^/]+)(/?)(.*)"
        local name, equals, value = record: match "([A-Z0-9-_]+)%s*(=?)([^/]+)"
        
        done = name == "END"
        
        if equals == "=" then
          keywords[name] = convert_type(value)
        end
      end
      
    end
  until done
--  _log (#headers, " header records")
  return keywords, headers
end

--[[

  The image pixels in a primary array or an image extension may have one of 5 supported data types:

    BITPIX 
    8       8-bit (unsigned) integer bytes
    16      16-bit (signed) integers
    32      32-bit (signed) integers
    -32     32-bit single precision floating point real numbers
    -64     64-bit double precision floating point real numbers 

  A 64-bit integer datatype has also been proposed and is currently in experimental use. 
  
  Unsigned 16-bit and 32-bit integers are supported by subtracting an offset from the raw pixel values (e.g., 32768 (2**15) 
  is subtracted from each unsigned 16-bit integer pixel value to shift the values into the range of a signed 16-bit integer) 
  before writing them to the FITS file. This offset is then added to the pixels when reading the FITS image to restore 
  the original values.

  The data in FITS files is always stored in "big-endian" byte order, where the first byte of numeric values 
  contains the most significant bits and the last byte contains the least significant bits.
  
--]]


-- called with an opened file object
function _M.read(file)
  
  local k, h = _M.readHeaderUnit(file)
  local bitpix, naxis1, naxis2, naxis3 = k.BITPIX, k.NAXIS1, k.NAXIS2, k.NAXIS3 or 1
  local size = naxis1 * naxis2 * naxis3 * math.abs(bitpix/8)
--  local data, n = file: read(size, "data")      -- "data" format
  local data = file: read(size) 
  assert(size == #data, "failed to read complete file")
  return data, k, h
end

function _M.write()
  --TODO:
end

-----------
--
-- byte swapping
--

-- 40ms for 12 Mpixels
-- swap bytes and add offset from FITS file header for unsigned integers
local function i16(data, out, n, bzero)
  local byteData = ld.newByteData(data)
  local inp = byteData: getPointer()
  local byt = ffi.cast('uint16_t*', inp)                            -- LuaJit FFI approach is fastest
  local r16 = ffi.cast('uint16_t*', out)
  for i = 0, n-1 do
    r16[i] = bit.bswap(bit.lshift(byt[i],16)) + bzero
  end  
  byteData: release()
end

-- swap bytes implementation for f32 or f64 input
local function float(fmt, data, out, n) 
  local f32 = ffi.cast('float*', out)                               -- output is only 32 bits
  local index
  for i = 0, n-1 do
    f32[i], index = love.data.unpack(fmt, data, index)              -- unpack is easiest for floats
  end  
end

local swapper =  {
    [false] = { [2] = i16},                                         -- integer
    [true]  = { [4]= function(...) float('>f', ...) end,
                [8]= function(...) float('>d', ...) end}}           -- floating point

-----------
--
-- return imageData format
--

function _M.readImageData(file)
  local elapsed = newTimer()
  local ok, data, k, h = pcall(_M.read, file)
  if not ok then return end       -- fail silently
  
  local bitpix, naxis1, naxis2 = k.BITPIX, k.NAXIS1, k.NAXIS2
  local fp, bytes = bitpix < 0, math.abs(bitpix) / 8
  local imageData = li.newImageData(naxis1, naxis2, fp and "r32f" or "r16")
  
  local swap = swapper[fp][bytes]
  if swap then
    local out = imageData: getPointer()
    swap(data, out, naxis1 * naxis2, k.BZERO)
  end
    
  local fmt = bytes*8 .. (fp and "-bit float" or "-bit integer")
  _log(elapsed ("%.3f ms, readImageData [%d x %d %s] %s", naxis1, naxis2, k.BAYERPAT or 'NONE', fmt))
  
  return imageData, k, h
end


return _M

-----
