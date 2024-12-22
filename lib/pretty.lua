-- pretty (), 
-- pretty-print for Lua
-- 2014.06.26   @akbooer
-- 2015.11.29   use names for global variables (ie. don't expand _G or system libraries)
--              use fully qualified path names for circular references
--              improve formatting of isolated nils in otherwise contiguous numeric arrays
--              improve formatting of nested tables
-- 2016.01.09   fix for {a = false}
-- 2016.02.26   use rawget to investigate array numeric indices, preload enc[_G] = _G only
-- 2016.03.10   fix for {nil,nil, 3,nil,5}
-- 2019.06.25   fix for out of order discontiguous numeric indices {nil,nil,3, [42]=42, nil,nil,nil,7,8,9}
-- TODO: smarter quotes

----------------------------


local function pretty (Lua)                     -- 2014 - 2019.06.25   @akbooer
  local L, N_NILS = {}, 2                       -- number of allowed nils between contiguous numeric indices
  local tab, enc = '  ', {[_G] = "_G"}          -- don't expand global environment
  local function p(...) for _, x in ipairs {...} do if x~='' then L[#L+1] = x end; end; end
  local function ctrl(y) return ("\\%03d"): format (y:byte ()) end          -- deal with escapes, etc.
  local function quote(x) return x:match '"' and "'" or '"' end             -- pick appropriate quotation mark
  local function str_obj(x) local q = quote(x); return table.concat {q, x:gsub ("[\001-\031]", ctrl), q} end
  local function brk_idx(x) return '[' .. tostring(x) .. ']' end
  local function str_idx(x) return x:match "^[%a_][%w_]*$" or brk_idx(str_obj (x)) end
  local function val (x, depth, name) 
    if name == "_G" or enc[x] then p(enc[x] or "_G") return end             -- previously encoded
    local t = type(x)
    if t == "string" then p(str_obj (x))  return end
    if t ~= "table"  then p(tostring (x)) return end
    if not next(x) then p "{}" return end
    local id_num, id_str = {}, {}
    for i in pairs(x) do 
      if type(i) == "number" then id_num[#id_num+1]=i else id_str[#id_str+1]= i end 
    end
    
    enc[x] = name; depth = depth + 1; p '{'             -- start encoding this table
    table.sort (id_num); table.sort (id_str, function(a,b) return tostring(a) < tostring(b) end)
    local nl1, nl2 = '\n'..tab:rep (depth), '\n'..tab:rep (depth-1) 
    
    local i, num_lines = 1, 0
    local nl_num = ''
    for _,j in ipairs (id_num) do                                            -- numeric indices
      if (j > 0) and (i + N_NILS >= j) then                                  -- contiguous indices
        p(nl_num); nl_num=''
        for _ = i, j - 1 do p "nil," end
        val (x[j], depth, name..brk_idx (j)) ; p ','
        i = j + 1
      else                                                                  -- discontiguous indices
        nl_num = nl1
        num_lines = num_lines + 1
        local fmt_idx = brk_idx (j)
        p (nl_num, fmt_idx, " = "); val (x[j], depth, name..fmt_idx); p (',')
      end
    end

    local nl_str = (#id_str > 1 or #id_num > 0) and nl1 or ''
    for _,j in ipairs (id_str) do                                           -- non-numeric indices
      local fmt_idx = str_idx(tostring(j))
      p (nl_str, fmt_idx, " = "); val (x[j], depth, name..'.'..fmt_idx); p (',')
    end
    L[#L] = nil                                                             -- stomp over final comma
    if num_lines + #id_str > 1 then p(nl2) end                              -- indent file brace, if necessary
    enc[x] = nil; p '}'                                                     -- finish encoding this table
  end
  val(Lua, 0, '_') 
  return table.concat(L) 
end 
 
 
return pretty 

-----


