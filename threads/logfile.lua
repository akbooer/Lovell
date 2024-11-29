--
--  logfile.lua
--

--[[
      NB: When a Thread is started, it only loads love.data, love.filesystem, and love.thread module. 
      Every other module has to be loaded with require. 
]]

local _M = {
  NAME = ...,
  VERSION = "2024.11.18",
  DESCRIPTION = "THREAD writes log files",
}

-- 2024.11.18  Version 0

local _log = require "logger" (_M)

local logChannel = love.thread.getChannel "logChannel"

--  alternative using LÖVE filesystem, but can only write to SAVE directory
--
  local logFile = love.filesystem.newFile "Lövell.log"
  logFile: setBuffer "line"
  logFile: open "w"
  
--

--local logFile = io.open ("Lovell.log", "w")
--logFile:setvbuf "line" 

--------------------
--
--  main loop
--

repeat
  
  local textline = logChannel: demand()    -- wait for message
  if textline == "EXIT" then 
    break 
  end
  
  logFile: write(textline)
  logFile: write '\n'
  
  print(textline)                 -- also log to console for easy access (during development, etc.)
  
until false

logFile: close()


return _M

-----
