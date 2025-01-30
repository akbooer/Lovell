--
-- spreadsheet.lua
--

local _M = {
    NAME = ...,
    VERSION = "2025.01.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "spreadsheet wrapper to virtualize table indexing",

  }

-- 2025.01.20  Version 0

local _log = require "logger" (_M)

local empty = _G.READONLY {}

local min, max = math.min, math.max

local love = _G.love
local lk = love.keyboard

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
  glide = glide * 0.9
end

-------------------------
--
-- SPREADSHEET
--
-- handles row-major or column-major format as input
-- always outputs row_major table constructed from input data according to options
--


-- SORT and FILTER the grid
function _M.new(self, cat, x,y, w,h)
  local data = cat.db
  local titles = data.titles
  local layout = self.layout
  local Ncol = #(titles or empty)
  local col_width = cat.col_width or empty
  local filter = cat.filter or empty
  local sorter = cat.sorter or empty
  
  layout: reset(x, y, 8, 0)

  --
  -- sorting... sorts the original database
  --
  
  local sorted = false
  for i = 1, Ncol do
    local sort = sorter[i]
    if self: Button(titles[i], layout:col((col_width[i] or 50) - 8, 25)) .hit and sort then
        sort.sorter(data, i, sort.reverse) 
        sort.reverse = not sort.reverse   -- swap direction for next time
        sorted = true
    end
  end
  
  --
  -- add Clear button for filters and sorting order
  --
  
  if filter ~= empty and sorter ~= empty then     -- add button to clear filters
    if self: Button("Clear", {valign = "middle"}, layout: col(80, 55)) .hit then
      for i = 1, Ncol do
        local filt = filter[i]
        if filt then 
          filt.text = '' 
          filt.previous = '' 
        end
        local sort = sorter[i]
        if sort then
          sort.reverse = false    -- revert to forward sort
        end
      end
      local sort = sorter[1]
      if sort then
        sort.sorter(data, 1, true) 
        sort.reverse = false       -- reverse next time 
        sorted = true
      end
    end
  end
  local top = 70
  layout: reset(10, y + 30, 8,0)
  
  --
  -- add filtering controls
  --
  
  local filtered = false
  for i = 1, Ncol do
    local filt = filter[i]
    if filt then
      self: Input(filt, layout:col((col_width[i] or 50) - 8, 25))
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
  
  if sorted or filtered or not cat.grid then
    
    -- create new grid
    local rows = {}
    for i = 1, #data do
      rows[i] = data[i]
    end
    cat.grid = {data = rows, scroll = {value = 1}}  -- set scroll bar back to top
    
    for i = 1, Ncol do
      local filt = filter[i]
      if filt then
        local text = filt.text
        cat.grid.data = filt.filter(cat.grid.data, i, text)
      end
    end
  end
  
  --
  -- row selection
  -- see: https://stackoverflow.com/a/62670884/22498830

  layout: reset(x + 5, top + 65)
  local grid = cat.grid
  if self: Table(grid, cat, layout:row(w - 30, h * 0.75)) .hit then
  
    local row = grid.row
    local lkd = lk.isDown
    local sel = cat.highlight or {anchor = row}
    cat.highlight = sel
    if lkd "lshift" or lkd "rshift" then 
      for i = min(sel.anchor, row), max(sel.anchor, row) do
        sel[i] = true
      end
      sel.anchor = row
    elseif lkd "lgui" or lkd "rgui" then 
       if sel[row] then
         sel[row] = nil
         sel.anchor = sel.anchor < row and row - 1 or row + 1
       else
        sel[row] = true
        sel.anchor = row
      end
    else
       cat.highlight = {[row] = true} 
       cat.highlight.anchor = row
    end
  end
  
  --
  -- scroll
  --
  
  tween(#grid.data, grid.scroll)
  
end




-------------------------
--
-- OLD
--

function _M.old(x, opts)

  opts = opts or empty
  local cfmt = opts.col_format or empty
  local ridx, cidx = opts.row_index, opts.col_index
  
  local rows, cols
  rows = ridx and (ridx.n or #ridx) or #x
  cols = cidx and (cidx.n or #cidx) or #(x[1] or empty)
  if x.column_major then
    rows, cols = cols, rows
  end
  
  local sheet = {}

  for r = 1, rows do
    local new_row = {}
    sheet[r] = new_row
    for c = 1, cols do
      local row, col
      row = ridx and ridx[r] or r
      col = cidx and cidx[c] or c
      if x.column_major then
        row, col = col, row
      end
      local value = x[row][col]
      local fmt = cfmt[col]
      new_row[c] = fmt and fmt(value) or value
    end
  end
  
  return sheet
end

-------------------------
--
-- TESTING
--

function _M.test()
  local x = {
    {'a', 'b'}, 
    {'c', 'd'}, 
    {'e', 'f'},
    {'g', 'h'},
    {'i', 'j'},
  }

  local options = {
    row_index = {5,3,1},        -- row ordering
    col_index = {2,2,1,1,2},    -- column ordering
    col_format = {nil, function(x) return x..x end},    -- column formatting
    }

  local y = _M.new(x, options)

  local r, c = #y, #y[1]
  print("rows", r)
  print("columns", c)
  for i = 1, r do
    print(unpack(y[i]))
  end
end


--_M.test()

return setmetatable(_M, {__call = function(self, ...) return _M.new(...) end})

-----
