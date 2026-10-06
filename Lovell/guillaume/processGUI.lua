--
-- processGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2026.09.29"
  _M.DESCRIPTION = "GUI - processing/plugins configuration"

local _log = require "logger" (_M)

-- 2024.12.18  Version 0

-- 2025.06.12  improve layout handling

-- 2026.07.05  renamed processingGUI, with completely different layout, using plugins


local plugins = require "plugins"
local suit  = require "suit" .new()     -- make a new SUIT instance for ourselves
local DaD   = suit: DragAndDrop()       -- actually, a SUIT-able extension

local love = _G.love
local lg = love.graphics

local layout = suit.layout
local row, col = _M.rowcol(layout)

local hrule = ('–'): rep(25)                         -- for menu dividers
local grey = {normal = {fg = { 0.25, 0.25, 0.25}}}     -- grey text colour

local function index(x)
  for i, name in ipairs(x) do
    x[name] = i
  end
  return x
end

local OMIT = index {"channel"}

local sequence = plugins.process_sequence    -- get the current sequence

local target = {}
for i = 1, sequence._max do
  target[i] = '#' .. i
end
index(target)      -- two-way lookup of process index/id

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
  layout: push(650 + 20 , 150 + 15)
  
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
    local _,y = row(0,0)
    outline = {650, 150, 200, y - 160 + 30, 4, text = plugin.documentation}   -- 4 is corner radius
    
  else
    suit: Button(name, row(160, 30))
    outline = {text = docs}
  end
  
  layout: pop()
end

--[[
theme.color = {
	normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
	hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
	active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
}
--]]

local ghostly = { normal = {bg = { 0.3,0.3,0.3}, fg = {0.5,0.5,0.5}} }

local function DrawGhost(text, opt, x,y,w,h)
  local theme = suit.theme
  lg.setColor(unpack(ghostly.normal.bg))
	lg.rectangle("line", x, y, w, h, opt.cornerRadius or 4)
	
  lg.setFont(opt.font)
  lg.setColor(unpack(ghostly.normal.fg))
	y = y + theme.getVerticalOffsetForAlign(opt.valign, opt.font, h)
	lg.printf(text, x+2, y, w-4, opt.align or "center")
end

local function Ghost(name, ...)
  return suit: Label(name, {draw = DrawGhost}, ...)
end  

-------------------------
--
-- PLUGINS
--

-- create the menu of installed plugins
-- also index by id to yield filename of dynamic plugins (NB. static plugin ids may not be unique, eg. Chroma)
local menu, filename = {}, {}
for fname, plugin in sorted(plugins) do
  if not (OMIT[fname] or plugin.static) then
    menu[#menu+1] = fname
    filename[plugin.id] = fname
  end
end


-------------------------
--
-- UPDATE / DRAW
--


local Title = {
  
    ["Static Plugins"] = [[
Static plugins are part of the system workflow and, as such, are permanently installed and may not be dragged into the post-stack workflow.
]],

    ["Dynamic Plugins"] = [[
This column shows all the dynamic plugins.

These may be added to the workflow by dragging and dropping into an empty workflow slot.

They are executed in order, top to bottom, and any missing slots are skipped.
]],

    ["Workflow"] = [[
This column shows the active plugins in the current workflow.

Controls from these plugins appear on the main display.  

A plugin may be removed from the workflow by dragging away from a process slot, and it snaps back to its allocated position in the Dynamic Plugins column.
]],

    ["Info"] = [[
This column shows interesting information (possibly).
]],

    ["Clear All"] = [[
Clears all Dynamic Plugins from the workflow column.
]],

    ["Factory Reset"] = [[Reverts the workflow to initial factory settings.
]],
 } 

local function PPsequence()
  _log ("workflow changed:", pretty(sequence))
end

local function clear(item_name)
  local fname = filename[item_name]
  for i, plugin in sequence() do
    if plugin == fname then
      sequence[i] = nil
      break
    end
  end  
end

local function onDrop(item_name, target_name)
  clear(item_name)                    -- remove from wherever it was
  local i = target[target_name]       -- look up target sequence number
  if sequence[i] then                 -- slot is already filled...
    return false                      -- ...abandon drop sequence
  end
  sequence[i] = filename[item_name]   -- put in place
  PPsequence()
  return true
end

local function onClear(item_name)
  clear(item_name)
  PPsequence()
end

local target_opt = {}     -- unique target options, get colour added when dragging
local drag_opt = {}       -- unique draggable options
local dragging            -- flag true if actively dragging an item


local highlight do        -- highlight possible targets when dragging
  local m, c = 0.3, 0.2
  highlight = {normal = {bg = { 0.19*m+c,0.6*m+c,0.73*m+c}, fg = {1,1,1}}}
end

local function columnTitle(name, width)
  width = width or 160
  local button = suit: Button(name, row(width, 30))
  if button.hovered and not dragging then 
    info(name, Title[name]) 
  end
  row()
  return button
end

local function static_plugins (plugins)
  columnTitle [[Static Plugins]]
  
  for name, plugin in sorted(plugins) do
    if plugin.static then 
      local id = plugin.id
      id = id == "Chroma" and ("Chroma (" .. name:upper() .. ")") or id
      if Ghost(id, row()) .hovered and not dragging then
        info(name)
      end
    end  
  end     
end


local function destinations(target)
  columnTitle [[Workflow]]

  for i in ipairs(target) do
    local dest = target_opt[i] or {}    -- unique IDs
    target_opt[i] = dest
    dest.color = dragging and highlight or nil
    DaD: Targetable(target[i], dest, row(160, 30))
  end

  row()
  
  if columnTitle [[Clear All]] .hit then
    DaD: Clear()
    sequence: clear_all()
    PPsequence()
  end
  
  if columnTitle [[Factory Reset]] .hit then
    DaD: Clear()
    sequence: factory_reset()
    PPsequence()
  end
end

 
local function dynamic_plugins(menu)
  columnTitle [[Dynamic Plugins]]
  
  for i, name in ipairs(menu) do
    local plugin = plugins[name]
    
    local x,y, w,h = row(160, 30)
    
    local plug
    local ghost = Ghost(plugin.id, x,y, w,h)
    if not plugin.static then
      local opt = drag_opt[i] or {id = 'p'..i, onDrop = onDrop, onClear = onClear, gripHandle = true}
      plug = DaD: Draggable(plugin.id, opt, x,y, w,h) 
    end
    
    if (dragging == plugin.id) or (not dragging and (plug.hovered or ghost.hovered)) then
      info(name)
    end
    
  end 
end

local column = {50, 250, 450, 650}
local rows =  {100, 200}

function _M.update(dt)
  dt = dt
  outline = nil
  dragging = DaD: Dragging()
  
  suit: Button("Plugins and Process Workflow", column[2], 20, 2 * 160 + 40, 30)
 
  layout:reset(column[3], rows[1], 10,10)
  destinations(target)      -- must be created bofre dynamic plugins
 
  layout: reset(column[1], rows[1], 10, 10)
  static_plugins(plugins)
  
  layout: reset(column[2], rows[1], 10, 10)
  dynamic_plugins(menu)
  
  layout:reset(column[4], rows[1], 100, 10)
  columnTitle ([[Info]], 550)
   
  -- DaD internals updated to be in sync with sequence[] 
  DaD: Clear()
  for i, fname in sequence() do
    DaD: Drop(plugins[fname].id, target[i])
  end

end


function _M.draw()
  local d, b = 0.3, 0.7     -- dark, bright
  lg.setColor(b,b,b,1)
  lg.setLineWidth(1)
    
  if outline then
    if #outline == 5 then     -- x,y, w,h, radius
      lg.rectangle("line", unpack(outline))
    end
    lg.setColor(b,b,b,1)
    lg.printf(outline.text or '', 850 + 20, 160, 320)  -- "text", x,y, width
  end
  
  -- workflow line
  d = 0.25
  lg.setColor(d,d,d,1)
  lg.setLineWidth(5)
  local x = column[3] + 80  - 2
  lg.line(x, rows[2], x, rows[2] + 7 * (30 + 10))
  lg.setLineWidth(1)
  
  suit: draw()      -- background layer
  
  DaD: draw()       -- update dynamic layer AFTER the background
  
end
 


return _M

-----
