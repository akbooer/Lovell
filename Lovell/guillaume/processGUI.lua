--
-- processGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2026.07.05"
  _M.DESCRIPTION = "GUI - processing/plugins configuration"

local _log = require "logger" (_M)

-- 2024.12.18  Version 0

-- 2025.06.12  improve layout handling

-- 2026.07.05  renamed processingGUI, with completely different layout, using plugins


local plugins = require "plugins"
local vector  = require "lib.vector"

local suit  = require "suit" .new()     -- make a new SUIT instance for ourselves
local DaD   = suit: DragAndDrop()       -- actually, a SUIT-able extension

local love = _G.love
local lg = love.graphics

local layout = suit.layout
local row, col = _M.rowcol(layout)

local hrule = ('–'): rep(25)                         -- for menu dividers
local grey = {normal = {fg = { 0.5, 0.5, 0.5}}}     -- grey text colour

local NPROC = 8     -- maximum number of active plugins

local function index(x)
  for i, name in ipairs(x) do
    x[name] = i
  end
  return x
end


local OMIT = index {"channel"}


-- Utilities


-- sorted version of the pairs iterator
-- use like this:  for a,b in sorted (x, fct) do ... end
-- optional second parameter is sort function cf. table.sort
local function sorted (x, fct)
  local y, i = {}, 0
  for z in pairs(x) do y[#y+1] = z end
  table.sort (y, fct) 
  return function ()
    i = i + 1
    local z = y[i]
    return z, x[z]  -- if z is nil, then x[z] is nil, and loop terminates
  end
end


local outline

-- write useful info in the right hand column
local function info(name, docs)
  layout: push(620 + 15 , 150 + 15)
  
  local plugin = plugins[name]
  if plugin then
    suit: Label("file: " .. name, row(160, 30))
    suit: Button(plugin.id, row())
    row(0, 5)
    plugin: draw(suit)    -- draw the plugin controls
    
    -- extras
    if plugin.extras then
      suit: Label(hrule, {color = grey}, row())
      plugin: extras(suit)
    end
     
    --  add frame
    local x,y = row(0,0)
    outline = {620, 150, 200, y - 160 + 30, 4, text = plugin.documentation}   -- 4 is corner radius
    
  else
    suit: Button(name, row(160, 30))
    outline = {text = docs}
  end
  
  layout: pop()
end


local ghosts    -- leave a ghost outline of a plugin

local function Ghost(name, ...)
  local opt = {color = grey, ...}
  opt[5] = 4              -- add corner radius for outline
  ghosts = ghosts or {}
  ghosts[#ghosts + 1] = opt  
  return suit: Label(name, opt, ...)
end  

-------------------------
--
-- PLUGINS
--

-- create the menu of installed plugins
local menu = {}
for filename, plugin in sorted(plugins) do
  if not (OMIT[filename] or plugin.static) then
    menu[#menu+1] = filename
  end
end


-------------------------
--
-- UPDATE / DRAW
--

local Phelp = [[
This column shows all the plugins in the Lovell/plugins folder.

Static plugins are part of the system and permanently installed, others may be added to the workflow by dragging and dropping into a workflow slot.

They are executed in order, top to bottom, and any missing slots are skipped.
]]

local Whelp = [[
This column shows the active plugins  in the current workflow.

Controls from these plugins appear on the main display.  

A plugin may be removed from the workflow by dragging away from a process slot, and it snaps back to its allocated position in the Plugins column.
]]

local Ihelp = [[
This column shows interesting information (possibly)
]]

local Shelp = [[
Static plugins are part of the system workflow and, as such, are permanently installed and may not be dragged into the post-stack workflow.
]]

local function onDrop(...)
  _log("you dropped me:", pretty{...})
end

local c1, c2 = 100, 360

function _M.update(dt)
  dt = dt
  ghosts = {}
  outline = nil
  
  suit: Button("Plugins and Process Workflow", 300, 20, 300, 30)
  
--  local cellGrid = cellGrid()     -- dynamic calculation of number of rows/cols in grid to fit screen
 
  layout:reset(100,90,100,10)

  if suit: Button("Plugins", col(160,30)) .hovered then info("Plugins", Phelp) end
  if suit: Button("Workflow", col(160,30)) .hovered then info("Workflow", Whelp) end
  if suit: Button("Info", col(550)) .hovered then info("Info", Ihelp) end

  layout:reset(360,150,10,10)
  
  -- destinations
  local dest = {}
  for i = 1, NPROC do
    dest[i] = {}    -- unique IDs
    DaD: Targetable("#" .. i, dest[i], row(160, 30))
  end
  
  -- available plugins
  layout: reset(100, 150, 10, 10)
  
  for i, name in ipairs(menu) do
    local plugin = plugins[name]
    
    local x,y, w,h = row(160, 30)
    
    local drag
    local ghost = Ghost(plugin.id, x,y, w,h)
    if not plugin.static then
      drag = DaD: Draggable(plugin.id, {id = 'p' .. i, onDrop = onDrop}, x,y, w,h) 
    end
    
    if ghost.hovered or drag.hovered then
      info(name)
    end

  end 
  
  -- static plugins 
  row()
  if suit: Button("Static Plugins", row()) .hovered then info("Static Plugins", Shelp) end
  for name, plugin in pairs(plugins) do
    if plugin.static then 
      local id = plugin.id
      id = id == "Chroma" and ("Chroma (" .. name:upper() .. ")") or id
      if Ghost(id, row()) .hovered then
        info(name)
      end
    end  
  end  
end


function _M.draw()
  local d, b = 0.3, 0.7     -- dark, bright
  lg.setColor(d,d,d,1)
  
  for _, ghost in ipairs(ghosts) do
    lg.rectangle("line", unpack(ghost))   -- ghost outlines
  end
    
  if outline then
    if #outline == 5 then     -- x,y, w,h, radius
      lg.rectangle("line", unpack(outline))
    end
    lg.setColor(b,b,b,1)
    lg.printf(outline.text or '', 850, 160, 300)  -- "text", x,y, width
  end
    
  suit: draw()      -- background layer
  
  DaD: draw()       -- update dynamic layer AFTER the background
  
end
 


return _M

-----
