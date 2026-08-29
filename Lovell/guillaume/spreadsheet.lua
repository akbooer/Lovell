--
-- spreadsheet.lua
--

local _M = {
    NAME = ...,
    VERSION = "2026.06.09",
    AUTHOR = "AK Booer",
    DESCRIPTION = "spreadsheet wrapper to virtualize table indexing",

  }

-- 2025.01.20  Version 0
-- 2025.02.11  move sorters and filters into here
-- 2025.03.19  set scroll to top when clearing sorting and filters
-- 2025.05.18  change Table widget parameters to align with those of spreadsheet

-- 2026.06.09  refactor sorting and filtering, allowing user-defined function for any column


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
  local data = cat.data 
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
  
    text    = function(a,b) return a < b  end,
    
    number  = function(a,b) 
                a = tonumber(a) or 0
                b = tonumber(b) or 0 
                return a < b 
              end,
  }

-------------------------
--
-- FILTERS
--
 -- col.filter, data, cat.row_index
 
local filter = {

  text = function(x, text)
    return (x or ''): lower(): find(text) 
  end,

  number = function(x, inequality, reference)
    x = tonumber(x) or 0
    if not x then return false end
    if inequality == '<' then
      return x < reference 
    elseif inequality == '>' then
      return x > reference 
    else
      return x == reference 
    end
  end,

}

_M.filter = filter    -- make available externally (for user-defined filters)

local pattern = {
  
  text = function(text) 
    return '^' .. text:lower() : gsub('*','.*')       -- change wildcard to Lua  syntax, start from beginning
  end,
  
  number = function(text)
    local inequality, reference = text: match "([<>])%s*([%+%-]?%d+%.?%d*)"
    reference = tonumber(reference)
    return inequality, reference                -- search template can be '>n' or '<n' or just 'n' (for equality) 
  end,
   
}

local function apply_filter(cat, col, ...)
    local ok, data, ridx = cat.cols[col].filter, cat.data, cat.row_index
    local n = 0
    for i = 1, ridx.n or #ridx do
      local row = ridx[i]
      if ok(data[row][col], ...) then
        n = n + 1
        ridx[n] = row
      end
    end
    ridx.n = n
end

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
  scroll.value = min(1, max(0, scroll.value + 2 * glide / (nrow + 100)))
  glide = wheel or glide
  wheel = nil
  glide = glide * 0.94   -- deceleration rate
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
  local data = cat.data
  layout: reset(x, y, padding, 0)
    
  --
  -- sorting... sorts the original database
  --
  
  local sorted = false
  if not cat.sort_index then reset_sort_index(cat) end
  
  for i, col in nextCol(cat) do
       
  local x,y, w,h = layout:col(col.w or Wdefault, 25)
    if self: Button(col.label or col[1], x,y, w,h) .hit then
      
       local sort = col.sort or sorter[col.type] or sorter.text   -- can be user-defined function
   
       mergesort(cat.sort_index, function (a,b)
                                    if col.reverse then a,b = b,a end
                                    return sort (data[a][i] or '', data[b][i] or '')
                                 end)
          
        col.reverse = not col.reverse   -- swap direction for next time
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
        local input = col.input
        input.text = '' 
        input.previous = '' 
        col.reverse = false    -- revert to forward sort
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
    col.filter = col.filter or filter[col.type]  or filter.text     -- can be user-defined function
    col.input = col.input or {text = ''}                    -- Input widget for filter text
    local input = col.input
    local x,y, w,h = layout:col(col.w or Wdefault, 25)
    self: Input(input, x,y, w,h)
    local text = input.text: gsub("[%%%[%]]", '')    -- remove invalid Lua search string items: %  [ ]
    input.text = text
    if text ~= input.previous or sorted then
      filtered = true
      input.previous = text
    end
  end
   
  --
  -- actual filtering of the grid
  --
  
--  if sorted or filtered or not cat.grid then
  if filtered or sorted or cat.filter or not cat.grid then
    reset_row_index(cat)
    cat.grid = cat.grid or {data = data, scroll = {value = 1}}    -- set grid to complete dataset
    -- TODO: clear selection?
    for i, col in nextCol(cat) do
      local input = col.input.text
      if #input > 0 then 
        local template = pattern[col.type] or pattern.text
        apply_filter(cat, i, template(input))
      end
    end
  end

  layout: reset(x + 5, top + 65)
  local grid = cat.grid
  
  if self: Table(grid, cat, layout:row(w - 30, h * 0.75)) .hit then
  
    --
    -- row selection
    -- see: https://stackoverflow.com/a/62670884/22498830
    --
    
    local isDown = lk.isDown
    local row, ridx = grid.row, cat.row_index
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
