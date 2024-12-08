--
-- settingsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.11.28"
  _M.DESCRIPTION = "settings GÜI, session and observation info"

-- 2024.11.28  Version 0

local _log = require "logger" (_M)


local suit = require "suit"

local session   = require "session"
local observer  = require "observer"

local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local self = suit.new()     -- make a new SUIT instance for ourselves

local ses_settings = session.settings
local obs_settings = observer.settings
local controls = session.controls

local ses = controls.ses_notes
local obs = controls.obs_notes


local function clearButton(id)
  self.layout: row()
end
  
-------------------------
--
-- UPDATE / DRAW
--


function _M.update(dt)
  dt = dt
  local w,h = lg.getDimensions()
  local layout = self.layout
  layout: reset(20, 100)
  layout: row(80,30)
  self: Button("Clear", {id = "clearScope"}, layout:row())
  layout:row()
  self: Button("Clear", {id = "clearObs"},   layout:row())
  layout:row()
  self: Button("Clear", {id = "clearSes"},   layout:row())
  
  layout: reset(120, 100)
  self:Label("telescope", {align = "left"}, layout:row(200, 30))
  
  -- telescope
  local scope = controls.telescope
  if self:isHit "clearScope" then 
    scope.text = ''
  end
  
  
  self:Input(scope, {id = "scope", align = "left"}, layout:row(120, 30))

  -- obs notes
  
  self:Label("observing notes", {align = "left"}, layout:row(120, 30))
  self:Input(obs, {id = "obs_notes", align = "left"}, layout:row(w - 250))

  self:Label("session notes", {align = "left"}, layout:row())
  self:Input(ses, {id = "ses_notes", align = "left"}, layout:row(w - 250, 30))

  layout:row(180, 40)
  self:Button("open log file", { id = "openLog" }, layout:row())
  layout:col(40,40)
  self:Button("open snapshot folder", { id = "openSave" }, layout:col(180, 40))
  
  if self:isHit "openLog" then
    local url = "file://%s/Lövell.log"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end
 
 if self:isHit "openSave" then
    local url = "file://%s/snapshots"
    love.system.openURL(url % love.filesystem.getSaveDirectory())
  end  
end

function _M.draw()
  self: draw()
end
 
-------------------------
--
-- KEYBOARD
--

function _M.keypressed(key)
  self:keypressed(key)
end

function _M.textinput(...)      
  self:textinput(...)
end

-----

return _M

-----
