--
-- mergesort.lua
--

local _M = {
    NAME = ...,
    VERSION = "2023.05.11",
    AUTHOR = "AK Booer",
    DESCRIPTION = "Merge sort",
  }

-- 2023.05.11  @akbooer

--[[

   merge_sort(list, fct)

   This sort implementation performance exceeds that of the internal Lua quicksort
   for arrays of random numbers greater than ~5000 (takes about 2 mS.)  
   For very small arrays, it's about 10x worse than the internal one,
   but then the cpu time is in the order of microseconds anyway.
   It's also stable, retaining the original order of equal items.

--]]

local function merge_sort(L, less_than)
  local floor = math.floor
  local temp = {}     -- can't be done in place
  less_than = less_than or function(a,b) return a < b end
  
  local function msort(L, start, stop)
    if stop <= start then return end
    
    -- bisection
    local middle = floor((start + stop) / 2)
    local i, j = start, middle + 1
    msort(L, i, middle)
    msort(L, j, stop)
    
    -- copy to temporary
    local temp = temp
    for k = start, stop do
      temp[k] = L[k]
    end
    
    -- merge two sorted halves
    local k = i
    local less_than = less_than
    local a, b = temp[i], temp[j]
    while true do
      if less_than(b, a) then
        L[k] = b
        j = j + 1
        b = temp[j]
        if j > stop then 
          break 
        end
      else
        L[k] = a
        i = i + 1
        a = temp[i]
        if i > middle then 
          i = j                 -- use j for the remaining...
          break 
        end
      end
      k = k + 1
    end
    
    -- do the rest
    for k = k + 1, stop do
      L[k] = temp[i]
      i = i + 1
    end
  end
  
  msort(L, 1, #L)
end

return merge_sort

-----

