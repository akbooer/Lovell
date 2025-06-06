--
-- logger module
--

local _M = {
    NAME = ...,
    VERSION = "2025.05.31",
    AUTHOR = "AK Booer",
    DESCRIPTION = "logging utility",
  }

-- 2024.10.10  Version 0
-- 2024.11.18  separate thread for file output and __call() metatable to access other functions

-- 2025.12.11  add global JSON with .read() 
-- 2025.02.17  remove json.write() (moved to json.lua)
-- 2025.03.29  add _err() for highlight error messages in log
-- 2025.05.31  save _G.VERSION


local gettime = require "socket" .gettime   -- sub-millisecond resolution

_G.pretty = require "lib.pretty"            -- global access for debugging only


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
-- LOGGING
--

-- return formatted current time (or given time) as a string
-- ISO 8601 date/time: YYYY-MM-DDThh:mm:ss or other specified format
local function formatted_time (date_format, now)
  now = now or gettime() 
  date_format = date_format or "%Y-%m-%dT%H:%M:%S"     -- ISO 8601
  local date = os.date (date_format, math.floor (now))
  local ms = math.floor (1000 * (now % 1)) 
  return ('%s.%03d'):format (date, ms)
end

local function log(...)
  local t = formatted_time "%Y-%m-%d %H:%M:%S"      -- use space delimeter, rather than 'T'
  logChannel: push (table.concat ({t, ...}, ' '))
end

local function err(...)
  log "************************"
  log(...)
  log "************************"
end

local function banner(about)
  local name = "%14s: " % ((about.NAME or ''): match "%w+$" or '?')
  local info = "version %s  %s" % {about.VERSION or '?', about.DESCRIPTION or ''}
  log(name, info)
  return name
end

function _M:new(about)
  local name = banner(about)
  if about.NAME == "main" then 
    banner(_M)                    -- announce this module after main module starts
    _G.VERSION = about.VERSION    -- save global version for GUI
  end
  return function(...) log(name, ...) end, function(...) err(name, ...) end
end

function _M.close()
  logChannel: push "EXIT"
end


return setmetatable(_M, {__call = _M.new})

-----
