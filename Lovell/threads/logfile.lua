--
--  logfile.lua
--

local _M = {
  NAME = ...,
  VERSION = "2026.03.29",
  DESCRIPTION = "THREAD writes log files",
}

-- 2024.11.18  Version 0

-- 2026.03.29  tidy up

local love = _G.love

local logChannel = love.thread.getChannel "logChannel"

local logFile = love.filesystem.newFile "Lövell.log"

logFile: setBuffer "line"
logFile: open "w"
  
--------------------
--
--  main loop
--

repeat
  
  local textline = logChannel: demand()    -- wait for message
  
  if textline == "EXIT" then break end
  
  logFile: write(textline)
  logFile: write '\n'
  
  print(textline)                 -- also log to console for easy access (during development, etc.)
  
until false

logFile: close()


return _M

-----
