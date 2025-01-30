--
-- csv.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "CSV file utilities",
  }

-- 2024.11.05  Version 0
-- 2024.11.20  use love.filesystem

-- 2025.01.08  add row_major and column_major options
-- 2025.01.20  fix skipping empty columns, and extra blank final column


local _log = require "logger" (_M)

local love = _G.love
local lf = love.filesystem

local empty = _G.READONLY {}


local function row_major(filename, tbl)
  tbl = tbl or {}
  local nr = 0
  for line in love.filesystem.lines(filename) do
    nr = nr + 1
    local nc = 1
    local row = {line: match "[^,]*"}         -- first column
    for item in line: gmatch ",([^,]*)" do    -- remaining columns
      nc = nc + 1
      row[nc] = item
    end
    tbl[nr] = row
  end
  tbl._row_major = true
  return tbl
end

local function column_major(filename, tbl)
  tbl = tbl or {}
  local nr = 0
  for line in lf.lines(filename) do
    nr = nr + 1
    local nc = 0
    local column
    for item in line: gmatch "([^,]*),?" do
      nc = nc + 1
      column = tbl[nc] or {}
      column[nr] = item
      tbl[nc] = column
    end
  end
  tbl[#tbl] = nil           -- drop last blank column
  tbl._column_major = true
  return tbl
end

-- read CSV file and return a table
local function readfile(filename, order, tbl)
  local f, errorstr = lf.newFile(filename, 'r' )
  if not f then 
    _log (errorstr)
    return nil, errorstr
  end
  tbl = order(filename, tbl)
  f: close()
  _log ("read " .. filename)
  return tbl
end

---

function _M.read_row_wise(filename, tbl)
  return readfile(filename, row_major, tbl)
end

function _M.read_column_wise(filename, tbl)
  return readfile(filename, column_major, tbl)
end

_M.read = _M.read_row_wise    -- default is row-major ordering


return _M

-----
