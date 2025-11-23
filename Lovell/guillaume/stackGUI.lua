--
-- stackGUI.lua
--

local _M = require "guillaume.objects" .GUIobject()

  _M.NAME = ...
  _M.VERSION = "2025.11.22"
  _M.DESCRIPTION = "stack GUI, view each stack frame"

-- 2025.01.22  Version 0
-- 2025.04.01  add RGBL exposure values for post-processing
-- 2025.05.14  remove subtraction of stack gradients (adds false colour)
-- 2025.06.07  add file names rejected from stack
-- 2025.11.21  add "dark/nodark flat/noflat" display (thanks SanjeevJoshi@CloudyNights)
-- 2025.11.22  add filter label


local _log = require "logger" (_M)


local suit = require "suit" .new()     -- make a new SUIT instance for ourselves

local poststack   = require "poststack"
local session     = require "session"
local controls = session.controls

local workflow    = require "workflow" .new "thumbnails"
workflow.controls = controls

local love = _G.love
local lg = love.graphics
local lt = love.timer

local empty = _G.READONLY {}
local deg = 180 / math.pi

local margin = 200

local PLAY, BLINK  = 0, 0
local playtime = 0          -- last time play position was updated

--[[

theme.color = {
	normal   = {bg = { 0.25, 0.25, 0.25}, fg = {0.73,0.73,0.73}},
	hovered  = {bg = { 0.19,0.6,0.73}, fg = {1,1,1}},
	active   = {bg = {1,0.6,  0}, fg = {1,1,1}}
}

--]]

local active = suit.theme.color.active.bg
local hovered = suit.theme.color.hovered.bg
local colour = suit.theme.color.text


local subs
local epoch = ''

local scroll = {value = 0}                -- stack scroller
local scrollOpt = {vertical = true}

local rate = {value = 0.5}                -- blink or play frame rate

local Aoptions = {align = "left",  color = {normal = {fg = active}}}      -- fixed labels
local Loptions = {align = "left",  color = {normal = {fg = hovered}}}     -- fixed labels
local Woptions = {align = "left"}


local frame = {
    image    = nil,     -- image  
    workflow = workflow,
  }

workflow.RGBL = {1,1,1,0, 0,0,0,0}       -- needed for poststack processing to handle this as RGB image

local floor = math.floor

local layout = suit.layout
local row, col = _M.rowcol(layout)

-------------------------
--
-- INIT
--

local sprites, matches do -- mark position of alignment stars, and matched pairs

  local idata = { 
            {1,1,1,1,1,1,1},
            {1,0,0,0,0,0,1},
            {1,0,0,0,0,0,1},
            {1,0,0,0,0,0,1},
            {1,0,0,0,0,0,1},
            {1,0,0,0,0,0,1},
            {1,1,1,1,1,1,1},
          }

--  local imageData = love.image.newImageData(5,5, "rgba8")
  local imageData = love.image.newImageData(7,7, "rgba8")

  imageData: mapPixel( 
    function(x,y, r,g,b,a)
      local i = idata[y+1][x+1]
      return i,i,i, i
    end)

  local marker = lg.newImage(imageData, {dpiscale=1, linear = true})  
  
  sprites = love.graphics.newSpriteBatch(marker, 1000)    -- a thousand stars?!
  matches = love.graphics.newSpriteBatch(marker, 1000)

end

-------------------------
--
-- UPDATE / DRAW
--

local W, H      -- screen dimensions
local w, h      -- thumbnail dimensions
local scale
local index

local min, max = math.min, math.max
  
local function pageup() scroll.value = 1  end
local function pagedown() scroll.value = 0 end
local function up(x) scroll.value = min(1, scroll.value + (x or 1) / #(subs or {1})) end
local function down(x) scroll.value = max(0, scroll.value - (x or 1) / #(subs or {1})) end

local lasttime = 0
local lastindex 
local showstars             -- toggle star display

-- control panel
local xy = "(%0.1f, %0.1f)"
local theta = "%0.3fº"
local rejected = {checked = false, text = "omit from stack"}

local function panel(subframe)
  layout:reset(50,150, 10,10)                       -- leaving space for CLOSE button
  local w = 120
  if suit: Button("Blink", row(w, 30)) .hit then
    BLINK = (BLINK == 0) and 1 or 0                 -- toggle blink
    PLAY = 0
  end
  if suit: Button("Play", row()) .hit then          -- toggle play
    PLAY = (PLAY == 0) and 1 or 0                
    BLINK = 0
  end
  suit: Label("rate", Loptions, row(w, 20))
  suit: Slider(rate, row(w, 10))
  row(w, 10)
  if suit: Button("Stop", row(w, 30)) .hit then      -- turn play (or blink) off
    PLAY = 0
    BLINK = 0
  end
  
  row(w,10)
  local dark, flat, filter = subframe.dark_calibration, subframe.flat_calibration, subframe.filter
  local masters = table.concat {dark and "  dark   " or "nodark   ", flat and "  flat   " or "noflat   ", filter}
  suit: Label(masters, Loptions, row(w, 30))
  row(w,10)

  if suit: Button("Show stars", row(w,30)) .hit then
    showstars = not showstars
  end
  if showstars then
    local stars = #(subframe.stars or empty)
    local matched = #(subframe.matched_pairs or empty)
    suit: Label("matched", Aoptions, row(w / 2, 20))
    suit: Label(matched, Woptions, col(w / 2 , 20))
    layout: left()
    suit: Label("found", Loptions, row())
    suit: Label(stars, Woptions, col())
    layout: left()
  else
    row(w, 50)
  end
  row(w, 40)
  
--  self: Label("filter: " .. (frame.filter or '?'), row(w, 20))

  local reject, name = controls.reject, subframe.name
  rejected.checked = reject[name]
  if suit: Checkbox(rejected, row(w, 20)) .hit then
    reject[name] = rejected.checked
  end
  
  local align = subframe.align
  if align then
    suit: Label("alignment", Loptions, row())
    suit: Label(xy: format(align[2], align[3]), Woptions, row())
    suit: Label(theta % (align[1] * deg), Woptions, row())
  else
    suit: Label("not aligned", Aoptions, row())
    suit: Label('', row())    -- maintain spacing of epoch label below
    suit: Label('', row())
  end
  suit: Label(epoch, Loptions, row(300,20))
end

-- vertical scroll
local function scrollbar(n)
  local x = (W + w * scale) / 2 + 30                        -- location of scrollbar
  local y = (H - scale * h) / 2
  if suit: Slider(scroll, scrollOpt, x, y, 12, h * scale) .hovered then
--    local _, my = lm.getPosition()
--    self: Label(my, Woptions, x + 20, my - 5, 50, 20)
  end
  index = floor((n - 0.01) * scroll.value) + 1
  suit: Label(index, Woptions, x + 20, y + (1 - scroll.value) * h * scale - 15, 50, 30)
  return index
end

-- Add stars to sprite batch for drawing.
local function markstars(sprites, stars, scale)
	sprites:clear()
  for i = 1, #stars do
    local star = stars[i]
    local x, y = star[1] * scale - 4, star[2] * scale - 4
		sprites:add(x, y)
	end
end
  
-- draw the top frame
local function draw_image()
  lg.reset()
  local thumbnail = workflow.output
  if not thumbnail then return end
  local ws, hs = w * scale, h * scale
  local x, y = (W - ws) / 2, H / 2
  local flipx = controls.flipLR.checked and -1 or 1
  local flipy = controls.flipUD.checked and -1 or 1
  lg.draw(thumbnail, W / 2, H / 2, 0, scale * flipx, scale * flipy, w / 2, h / 2) 
  
  lg.setColor(unpack(active))
  y = y - scale * h / 2
  lg.rectangle("line", x, y, ws, hs)

  if showstars then
    lg.setColor(unpack(hovered))
    lg.draw(sprites,  W / 2, H / 2, 0, scale * flipx, scale * flipy, w / 2, h / 2) 
    lg.setColor(unpack(active))
    lg.draw(matches,  W / 2, H / 2, 0, scale * flipx, scale * flipy, w / 2, h / 2) 
  end
  
end

-- draw the stack of (empty) frames
local function draw_stack()
  local colour = {unpack(hovered)}
  local ws, hs = w * scale, h * scale   -- image size
  
  local D = W                 -- distance of viewer from screen (in pixels!)
  local V = (H - hs) / 2      -- vertical height of viewer (above top of image)
  local d = 150                -- depth distance between each frame
  
  for i = #subs - index, 1, -1 do
    local shrink =  D / (D + i * d)     -- perspective scale
    local top = V * shrink
    local shrink2 = shrink ^ 2
    colour[4] = shrink2                  -- choose alpha to fade into distance
    local x, y = ws * shrink, hs * shrink
    local c = 0.2 * shrink2
    lg.setColor(c,c,c, 1)
    lg.rectangle("fill", (W - x) / 2 , top, x, y)
    lg.setColor(colour)
    lg.rectangle("line", (W - x) / 2 , top, x, y)
  end
end

-- tween
local function tween()
  local now = lt.getTime()
  if playtime > now then return end            -- nothing to do here
  playtime = now + (1 - rate.value)
  
  if PLAY ~= 0 then
    local v = scroll.value
    if PLAY > 0 then up() else down() end   -- move one frame
    if scroll.value == v then
      PLAY = -PLAY            -- hit the end, so change direction
    end
  
  elseif BLINK ~= 0  then
    if BLINK > 0 then up() else down() end   -- move one frame
    BLINK = -BLINK                            -- always change direction
  end
end


function _M.update()
  local timenow = lt.getTime()
  if timenow > lasttime + 1 then    -- we've just arrived at this page...
    lastindex = nil
  end
  lasttime = timenow
  
  local layout = suit.layout
  local stack = session.stack()
  
  if not stack then subs = nil return end
  
  W,H = lg.getDimensions()
  layout: reset(margin, 100, 10,10)
  
  subs = stack.subs
  w,h = subs[1].thumb: getDimensions()  
  local ws = stack.image: getWidth()
  scale = 0.70 * H / h          -- image is X % of screen height
  local n = #subs
  index = 1
  if n > 1 then
    scrollbar(n)
    tween()
  end
  
  local subframe = subs[index]
  epoch = os.date("%c", subframe.epoch)
  frame.image = subframe.thumb
  panel(subframe)
  if index ~= lastindex then
--    frame.gradients = stack.gradients           -- use the offset and gradients from the whole stack
    frame.bayer = stack.bayer
    poststack(frame)                            -- run poststack processing chain
    
    markstars(sprites, subframe.stars, w / ws)                        -- mark found stars
    markstars(matches, subframe.matched_pairs or empty, w / ws)       -- mark matched stars
    
  end
  lastindex = index
end


function _M.draw()
  if not subs then return end
  draw_stack ()
  draw_image ()
  suit: draw()            -- controls
  lg.setColor(1,1,1, 1)
end


-------------------------
--
-- KEYBOARD
--

local keypressed =  {
    ["home"]  = pageup,
    ["end"]   = pagedown,  
    pageup    = pageup,
    pagedown  = pagedown,
    up        = up,
    down      = down,
  }

function _M.keypressed(key)
  suit: keypressed(key)
  local action = keypressed[key]
  if action then action() end
end

-------------------------
--
-- Mouse
--

function _M.wheelmoved(_, wy)
  if wy > 0 then 
    down(0.5) 
  elseif wy < 0 then
    up(0.5)
  end
end


return _M

-----
