-- Main module

local _M = {
  NAME = ...,
  VERSION = "2025.01.26",
  DESCRIPTION = "Lövell - Electronically Assisted Astronomy app built on the LÖVE framework", 
}

local logger = require "logger"    -- get access to logger.close() 
local _log = logger(_M)

-- 2024.09.25  Version 0

local love = _G.love
local lt = love.thread
local lf = love.filesystem
local lg = love.graphics
local ls = love.system

do -- log system info before other modules loaded
  local OS = ls.getOS()
  local processorCount = ls.getProcessorCount( )
  local renderer = tostring(lg.getRendererInfo())
  _log ("%s, %d processors, %s" % {OS, processorCount, renderer})
end

local session = require "session"
local masters = require "masters"
local GUI     = require "guillaume"


-------------------------
--
-- LOGFILE THREAD
--

lt.newThread "threads/logfile.lua" :start "logfile"

-------------------------
--
-- WATCHER THREAD
--

lt.newThread "threads/watcher.lua" :start "watcher"

local newWatchFolder = lt.getChannel "newWatchFolder"

-- NB: All callbacks are only called in main thread. 

-------------------------
--
-- FILE/FOLDER DROPPED

--

local mountpoint = "watched/"
local folder      -- current watched folder

-- start watching a new folder, the beginning of a new (or old) observation
function love.directorydropped(path)
  _log "------------------------"
  _log("folder dropped " .. path)
  if folder then 
    lf.unmount(folder) 
    folder = nil
  end
  local mount = lf.mount(path, mountpoint)
  if mount then 
    folder = path
  else
    _log "mount failed" 
  end
--  session.new(folder)
  newWatchFolder: push(path)      -- tell the watcher we're looking somewhere else
end

-- dropped file should be a calibration file: BIAS, DARK, FLAT, ...
function love.filedropped(file)
  local name = file:getFilename()
  _log("file dropped " .. name)
  masters.new(file)
end

-------------------------
--
-- UPDATE / DRAW / QUIT
--

function love.load(arg)
  
  if arg[#arg] == "-debug" then require "mobdebug" .start() end   -- enable debugging in ZeroBrane Studio

  io.stdout:setvbuf "line"   -- let print work immediately (for debugging, etc.)
  
  love.window.setDisplaySleepEnabled(true) 
  
  lf.createDirectory "snapshots"   -- located in the app's SAVE folder
  lf.createDirectory "settings"    -- ditto, for sundry settings
  lf.createDirectory "sessions"
  lf.createDirectory "masters"

--[[
  local info = {
      limits = lg.getSystemLimits( ), 
      supported = lg.getSupported(), 
      imageformats = lg.getImageFormats(),
      canvasformats = lg.getCanvasFormats(),
     }
  _log (pretty(info))
--]]

end

function love.update(dt)
  GUI.update(dt)                    -- update the GUI...
  session.update()                  -- ...and any session processing
end

function love.draw()
  GUI.draw()                        -- draw the screen
end

function love.quit()
  session.close()                   -- save current session
  _log "Lövell – system exit"
  logger.close()                    -- close the log file
end


-----
