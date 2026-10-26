--
-- fitsheaders.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.10.25",
    DESCRIPTION = "FITS headers for current observation",
  }

-- 2026.06.06  Version 0
-- 2026.06.18  access stack object directly
-- 2026.10.25  add frame# slider


local _log = require "logger" (_M)

local controls = require "controls"


local love = _G.love
local lg = love.graphics

------------------------------
--
-- HEADERS
--

local cols = {
        {"Name",    w = 120, },
        {"Value",   w = 360, align = "left"},
        {"Comment", w = 600, },
      }

local widget = {cols = cols, data = {}}    -- SUIT-able Table widget

local slider = {value = 1, default = 1, min = 1, max = 1}

local subs
local frame = 1
local label = ''
local left = {align = "left"}

function _M.update(suit)
  
  local new_subs = controls.subs
  local new_frame = math.floor(slider.value)
  local subs_changed = subs ~= new_subs
  local frame_changed = new_frame ~= frame
  
  if subs_changed or frame_changed then
    
    -- update slider info
    subs = new_subs
    slider.max = #subs
    slider.value = math.max(1, math.min(slider.value, slider.max))
    frame = new_frame
    label = string.format("frame# %d of %d", frame, #subs)
    local Nsubs = #subs
    if not (subs and subs[frame]) then return end
    
    if subs_changed then    -- whole new dataset and widget
      widget = {cols = cols, data = {}}
    end
    local data = widget.data
    
    -- update header info
    local db = subs[frame].headers
    for i, info in ipairs(db) do
      local name, equals, value, slash, comment = info: match "([A-Z0-9-_]+)%s*(=?)%s*([^/]+)(/?)%s*(.*)"
      local eq = equals == "="
      data[i] = {name, eq and value or '', eq and comment or value}
    end
  end
  
  -- add slider to move through frames
  
  if subs and #subs > 0 then
    local sl = suit.layout
    sl: row(nil, -20)
    suit: Label(label, left, sl: row(200, 25))
    suit: Slider(slider,  sl: row(250, 14))
  end
  
end

function _M.load()
  return widget
end


return _M

-----

