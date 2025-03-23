--
-- spreadsheet.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.03.19",
    AUTHOR = "AK Booer",
    DESCRIPTION = "spreadsheet wrapper to virtualize table indexing",

  }

-- 2025.01.20  Version 0
-- 2025.02.11  move sorters and filters into here
-- 2025.03.19  set scroll to top when clearing sorting and filters


local _log = require "logger" (_M)

local mergesort = require "lib.mergesort"

local empty = _G.READONLY {}

local min, max = math.min, math.max

local love = _G.love
local lk = love.keyboard

local Wdefault = 100      -- default column width

-------------------------
--
-- UTILS
--

-- column iterator
local function nextCol(cat)
  local idx = cat.col_index
  local cols = cat.cols or empty
  local i = 0
  local N = #(idx or cols)
  idx = idx or empty
  return function()
    i = i + 1
    local j = idx[i] or i <= N and i or nil
    return j, cols[j]
  end
end

-- row index, reset to full sort index
local function reset_row_index(cat) 
  local ridx = cat.row_index or {}
  cat.row_index = ridx
  local sidx = cat.sort_index
  local n = #sidx
  for i = 1, n do
    ridx[i] = sidx[i]   -- sorted ordering
  end
  ridx.n = n            -- full length
end

-- sort index
local function reset_sort_index(cat) 
  local sidx = cat.sort_index or {}
  cat.sort_index = sidx
  local data = cat.DB 
  for i = 1, #data do
    sidx[i] = i         -- original ordering
  end
end

-------------------------
--
-- SORTERS
--
-- these sorts are run on the entire input table...
-- ...since we've no idea what rows the filters will be selecting
--

local sorter = {

  text = function(dir, data, ridx, col)
    local function compare(a,b)
      if dir then a,b = b,a end
      return (data[a][col] or '') < (data[b][col] or '')
    end
    
    mergesort(ridx, compare)
  end,

  number = function(dir, data, ridx, col)
    local function compare(a,b)
      if dir then a,b = b,a end
      a, b = tonumber(data[a][col]) or 0, tonumber(data[b][col]) or 0
      return a < b
    end
    
    mergesort(ridx, compare)
  end,

  new = function(self, stype)
    local sorter = type(stype) == "function" and stype or self[stype]   -- allow user-defined function
    return {sorter = sorter, reverse = false}
  end,

}

setmetatable(sorter, {__call = sorter.new})

_M.sorter = sorter      -- make available externally

-------------------------
--
-- FILTERS
--

local function apply_filter(ok, data, ridx, col)
    local n = 0
    for i = 1, ridx.n or #ridx do
      local row = ridx[i]
      if ok(data[row][col]) then
        n = n + 1
        ridx[n] = row
      end
    end
    ridx.n = n
end

local filter = {

  text = function(text, _, ...)                     -- scale parameter unused
    if #text == 0 then return end                   -- nothing to do
    text = '^' .. text:lower() : gsub('*','.*')     -- change wildcard to Lua string version, start from beginning
    local function ok(x) return (tostring(x) or ''): lower(): match(text) end
    
    apply_filter(ok, ...)
  end,

  -- search text can be >n <n 
  number = function(text, scale, ...)
    local inequality, value = text: match "([<>])%s*([%+%-]?%d+%.?%d*)"
    value = tonumber(value) 
    if not value then return end            -- nothing to do
    value = value * (scale or 1)
    
    local ok
    if inequality == '<' then
      ok = function(x) return (tonumber(x) or 0) < value end
    elseif inequality == '>' then
      ok = function(x) return (tonumber(x) or 0) > value end
    else
      ok = function(x) return (tonumber(x) or 0) == value end
    end
    
    apply_filter(ok, ...)
  end,

  new = function(self, ftype)
    local filter = type(ftype) == "function" and ftype or self[ftype]   -- allow user-defined function
    return {filter = filter, text = ''}
  end

}

setmetatable(filter, {__call = filter.new})

_M.filter = filter      -- make available externally

-------------------------
--
-- SCROLLING
--

local wheel
local glide = 0

function _M.wheelmoved(_, wy)
  wheel = wy
end

  -- smooth scroll wheel
local function tween(nrow, scroll)
  scroll.value = min(1, max(0, scroll.value + 4 * glide / (nrow + 100)))
  glide = wheel or glide
  wheel = nil
  glide = glide * 0.9   -- deceleration rate
end

-------------------------
--
-- SPREADSHEET
--
--

local padding = 2

-- create new spreadsheet
function _M.new(self, cat, x,y, w,h)
  local layout = self.layout
  local data = cat.DB
  layout: reset(x, y, padding, 0)

  --
  -- init sorters, filters and sort index
  --
  
  for _, col in nextCol(cat) do
    col.type = col.type or "text"
    col.sort = col.sort or sorter(col.type) or sorter "text"
    col.filter = col.filter or filter(col.type, col.scale)
  end

  if not cat.sort_index then
    reset_sort_index(cat)
  end
  
  --
  -- sorting... sorts the original database
  --
  
  local sorted = false
  for i, col in nextCol(cat) do
    local sort = col.sort
    local x,y, w,h = layout:col(col.w or Wdefault, 25)
    if self: Button(col.label or col[1], x,y, w,h) .hit and sort then
        sort.sorter(sort.reverse, data, cat.sort_index, i) 
        sort.reverse = not sort.reverse   -- swap direction for next time
        sorted = true
    end
  end
  
  --
  -- add Clear button for filters and sorting order
  --
  
  do     -- add button to clear filters
    if self: Button("Clear", {valign = "middle"}, layout: col(80, 55)) .hit then
      reset_sort_index(cat)
      cat.grid.scroll.value = 1   -- set scroll bar back to top
      sorted = true
      for _, col in nextCol(cat) do
        local filt = col.filter
        if filt then 
          filt.text = '' 
          filt.previous = '' 
        end
        local sort = col.sort
        if sort then
          sort.reverse = false    -- revert to forward sort
        end
      end
    end
  end
  
  --
  -- add filtering controls
  --
  
  local top = 70
  layout: reset(10, y + 30, padding,0)
  local filtered = false
  -- have to apply ALL the filters if ANY changes...
  -- ... just a backspace will do it, and there's no filter 'undo' !
  for _, col in nextCol(cat) do
    local filt = col.filter
    local x,y, w,h = layout:col(col.w or Wdefault, 25)
    if filt then
      self: Input(filt, x,y, w,h)
      local text = filt.text: gsub("[%%%[%]%-%+]", '')    -- remove invalid Lua search string items
      filt.text = text
      if text ~= filt.previous or sorted then
        filtered = true
        filt.previous = text
      end
    end
  end
   
  --
  -- actual filtering of the grid
  --
  
--  if sorted or filtered or not cat.grid then
  if filtered or sorted or cat.filter or not cat.grid then
    reset_row_index(cat)
    cat.grid = cat.grid or {data = data, scroll = {value = 1}}
    -- TODO: clear selection?
    for i, col in nextCol(cat) do
      local filt = col.filter
      if filt then
        filt.filter(filt.text, col.scale, cat.grid.data, cat.row_index, i)
      end
    end
  end
  
  -- create options for Table
  if not cat.tableOpts then
    local cwid, cfmt, caln = {}, {}, {}
    local cols = cat.cols
    for i = 1, #cols do
      local col = cols[i]
      cwid[i] = col.w or Wdefault
      cfmt[i] = col.format
      caln[i] = col.align
    end
    cat.tableOpts = {   -- persistent tables, so create once here
        row_index = cat.row_index, 
        col_index = cat.col_index, 
        col_width = cwid, 
        col_format = cfmt,
        col_align = caln,
      }
  end
  cat.tableOpts.highlight = cat.highlight   -- dynamically changes, so update here

  layout: reset(x + 5, top + 65)
  local grid = cat.grid
  
  if self: Table(grid, cat.tableOpts, layout:row(w - 30, h * 0.75)) .hit then
  
    -- row selection
    -- see: https://stackoverflow.com/a/62670884/22498830
    local row = grid.row
    local ridx, cidx = cat.row_index, cat.col_index
    local isDown = lk.isDown
    local sel = cat.highlight or {anchor = row}
    cat.highlight = sel
    if isDown "lshift" or isDown "rshift" then 
      for i = min(sel.anchor, row), max(sel.anchor, row) do
        sel[ridx[i]] = true
      end
      sel.anchor = row
    elseif isDown "lgui" or isDown "rgui" then 
       if sel[ridx[row]] then
         sel[ridx[row]] = nil
         sel.anchor = sel.anchor < row and row - 1 or row + 1
       else
        sel[ridx[row]] = true
        sel.anchor = row
      end
    else
       cat.highlight = {[ridx[row]] = true} 
       cat.highlight.anchor = row
    end
  end
  
  --
  -- scroll
  --
  
  tween(cat.row_index.n, grid.scroll)
  
end


return setmetatable(_M, {__call = function(self, ...) return _M.new(...) end})

-----
