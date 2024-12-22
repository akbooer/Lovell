--
-- logger module
--

local _M = {
    NAME = ...,
    VERSION = "2024.12.11",
    AUTHOR = "AK Booer",
    DESCRIPTION = "logging utility",
  }

-- 2024.10.10  Version 0
-- 2024.11.18  separate thread for file output and __call() metatable to access other functions
-- 2025.12.11  add global JSON with .read() 


local gettime = require "socket" .gettime   -- sub-millisecond resolution

_G.pretty = require "lib.pretty"            -- global access for debugging only
_G.json   = require "lib.json"              -- make this globally accessible, with file read function (see below)


local logChannel = love.thread.getChannel "logChannel"


-------------------------
--
-- Python-like string formatting with % operator
-- see: http://lua-users.org/wiki/StringInterpolation
--
getmetatable ''.__mod = function(a, b)
  return type(b) == "table" 
    and a:format(unpack(b))
    or  a:format(b)
end

-------------------------
--
-- READONLY wrapper for tables
--
local function newindex() 
  error ("read-only", 2) 
end

function _G.READONLY(tbl)
  return setmetatable({}, {__index = tbl, __newindex = newindex})
end

-------------------------
--
-- JSON READER
--
function _G.json.read(path)
  local jdata, err
  local file = love.filesystem.newFile(path, 'r' )
  if file then 
--    _log("loading " .. path)
    local info = file: read()
    file: close()
    jdata, err = _G.json.decode(info)
  end
  return jdata, err
end

-------------------------
--
-- LOGGING
--

-- return formatted current time (or given time) as a string
-- ISO 8601 date/time: YYYY-MM-DDThh:mm:ss or other specified format
local function formatted_time (date_format, now)
  now = now or gettime() 
--  date_format = date_format or "%Y-%m-%dT%H:%M:%S"     -- ISO 8601
  date_format = date_format or "%Y-%m-%d %H:%M:%S"
  local date = os.date (date_format, math.floor (now))
  local ms = math.floor (1000 * (now % 1)) 
  return ('%s.%03d'):format (date, ms)
end

local function log(...)
  local t = formatted_time()
  logChannel: push (table.concat ({t, ...}, ' '))
end

local function banner(about)
  local name = "%12s: " % ((about.NAME or ''): match "%w+$" or '?')
  local info = "version %s  %s" % {about.VERSION or '?', about.DESCRIPTION or ''}
  log(name, info)
  return name
end

function _M:new(about)
  local name = banner(about)
  if about.NAME == "main" then banner(_M) end         -- announce this module after main module starts
  return function(...) log(name, ...) end
end

function _M.close()
  logChannel: push "EXIT"
end


return setmetatable(_M, {__call = _M.new})

-----
