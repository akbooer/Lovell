--
-- csv.lua
--

local _M = {
    NAME = ...,
    VERSION = "2024.11.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "CSV file utilities",
  }

-- 2024.11.05  Version 0
-- 2024.11.20  use love.filesystem


local _log = require "logger" (_M)

local love = _G.love

-- read CSV file and return a table
function _M.read(filename)

  local f, errorstr = love.filesystem.newFile( filename, 'r' )
  if not f then return nil, table.concat {errorstr, filename, " : "} end
  
  local tbl = {}
  for line in love.filesystem.lines(filename) do
    local row = {}
    for item in line: gmatch "[^,]+" do
      row[#row+1] = item
    end
    tbl[#tbl+1] = row
  end
  f: close()
  _log ("read " .. filename)
  return tbl
end

-----

return _M

-----
