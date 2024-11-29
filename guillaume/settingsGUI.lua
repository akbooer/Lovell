--
-- settingsGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2024.11.28"
  _M.DESCRIPTION = "settings GÜI, session and observation info"

local _log = require "logger" (_M)

-- 2024.11.28  Version 0


local love = _G.love
local lg = love.graphics
local lf = love.filesystem

local suit = require "suit"
local settings = require "session" .settings


local self = suit.new()     -- make a new SUIT instance for ourselves

local scope = settings.telescope
local obs = settings.obs_notes
local ses = settings.ses_notes


-------------------------
--
-- UPDATE / DRAW
--


function _M.update(dt)
  dt = dt
  local w,h = lg.getDimensions()
  local layout = self.layout
  layout: reset(100, 100)
  self:Label("telescope", {id = "tscope", align = "left"}, layout:row(200, 30))
  self:Input(scope, {id = "scope", align = "left"}, layout:row())

  self:Label("observing notes", {align = "left"}, layout:row(w - 200, 30))
  self:Input(obs, {id = "obs_notes", align = "left"}, layout:row())

  self:Label("session notes", {align = "left"}, layout:row())
  self:Input(ses, {id = "ses_notes", align = "left"}, layout:row())

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
