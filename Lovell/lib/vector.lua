--

local _M = {
    NAME = ...,
    VERSION = "2026.08.20",
    AUTHOR = "AK Booer",
    DESCRIPTION = "vector arithmetic",

  }

-- 2026.05.05  Version 0 - component-wise calculations with second vector or scalar
-- 2026.06.03  add concat operator ..
-- 2026.07.05  add modulus operator %, power ^, and unary minus -
-- 2026.07.06  allow alpha subscripts and swizzles with GLSL syntax: V.xy, C.rgb, etc...
-- 2026.07.18  add .uv texture coordinates
-- 2026.07.22  add :max() and :min() 
-- 2026.07.28  add :mean() 
-- 2026.08.02  add :ones() and :zeros()
-- 2026.08.20  add .new(...)  [make a new vector]


local _log = require "logger" (_M)

local empty = _G.READONLY {}
local pretty = _G.pretty

local meta = {}

local function add(a,b) return a + b end
local function sub(a,b) return a - b end
local function mul(a,b) return a * b end
local function div(a,b) return a / b end
local function mod(a,b) return a % b end
local function pow(a,b) return a ^ b end
local function unm(a)   return   - a end

local function vector(a)
  return setmetatable(a or {}, meta)    -- allow v = vector()
end

local function map(fct, a,b)
  local x = {}
  local c = type(b) == "table" and b or empty
  for i = 1, #a do
    x[i] = fct(a[i], c[i] or b)
  end
  return vector(x)
end

local function fill(a, b)
  local v = {}
  for i = 1, #a do v[i] = b end
  return vector(v)
end


-- could do equality with __eq(), but might confuse with normal pointer equality for tables.
-- can't do inequalities, because return has to be a boolean scalar, not a vector  :-(

function meta:__add(x) return map(add, self, x) end
function meta:__sub(x) return map(sub, self, x) end
function meta:__mul(x) return map(mul, self, x) end
function meta:__div(x) return map(div, self, x) end
function meta:__mod(x) return map(mod, self, x) end
function meta:__pow(x) return map(pow, self, x) end
function meta:__unm(x) return map(unm, self, x) end


function meta:__concat(y) 
  local x = {}
  local n = #self
   y = type(y) == "table" and y or {y}
  for i = 1, n do x[i] = self[i] end
  for i = 1, #y do x[i + n] = y[i] end
  return vector(x)    
end

-- other functions   X: min(Y), etc...
  
local fct = {new = vector}

function fct.min(a, b) return map(math.min, a, b) end
function fct.max(a, b) return map(math.max, a, b) end

function fct.sum(a)
  local sum = 0
  for i = 1, #a do sum = sum + a[i] end
  return sum
end

function fct.dot(a, b)
  return fct.sum(map(mul, a, b))
end

function fct.mean(a) return fct.sum(a) / #a end

function fct.zeros(a) return fill(a, 0) end
function fct.ones(a)  return fill(a, 1) end
  

local index =             -- name index for GLSL-type component access and swizzles
  {
    x = 1, y = 2, z = 3, w = 4,       --  Vectors: x, y, z, w
    r = 1, g = 2, b = 3, a = 4,       --  Colors:  r, g, b, a
    s = 1, t = 2, p = 3, q = 4,       --  Texture: s, t, p, q
    u = 1, v = 2,                     --...also texture: u, v
  }

-- allow swizzles like .rrr, .xy, etc..., for both get and set
local function chars (swizzle, vector)
  if type(swizzle) ~= "string" then error("vector subscript is not a string", 3) end
  local len = #swizzle
  local i = 0
  return function ()
    i = i + 1
    if i > len then return end
    local c = swizzle:sub(i,i)
    local idx = index[c]
    if not idx then error(string.format ("vector subscript is not valid '%s' in '%s'", c, swizzle), 3) end
    return i, idx, vector[idx]
  end
end

function meta:__index(swizzle)
  
  if fct[swizzle] then 
    return function (a, b) 
      return fct[swizzle] (a, b) 
    end
  end
  
  if index[swizzle] then return self[index[swizzle]] end    -- fast track scalars
  
  local v = {}                                              -- swizzle returns a vector
  for i, _, val in chars(swizzle, self) do
    v[i] = val 
  end
  return vector(v)  
end

function meta:__newindex(swizzle, value)
  if index[swizzle] then rawset(self, index[swizzle], value) return end   -- fast track scalars
  local vec = type(value) == "table"                                      -- allow scalar value for swizzles
  for i, idx in chars(swizzle, self) do
    rawset(self, idx, vec and value[i] or value) 
  end
end

local function p(x) 
  print(pretty(x))
end

function _M.test()
  local V = vector{1,2,3,4}
  p {V = V}
  p {["V[3]"] = V[3]}
  p {["V + 5"] = V + 5}
  p {["V * 5"] = V * 5}
  p {["V / 5"] = V / 5}
  p {["V + 5"] = V + 5}
  p {["V + V"] = V + V}
  p {["V / V + 1"] = V / V + 1}
  p {["V ^ V"] = V ^ V}
  p {["V % 2"] = V % 2}
  p {["-V"] = -V}    -- yup, unary minus too
  p {["V .. V"] = V .. V}
  
  p {["min(V,2)"] = V: min(2)}
  p {["max(V,3)"] = V: max(3)}
  p {["sum(V)"] = V: sum()}
  p {["mean(V)"] = V: mean()}
  p {["V:dot(V)"] = V: dot(V)}  
  p {["V:ones()"] = V: ones()}
  p {["V:zeros()"] = V: zeros()}

  p {["abgr"] = {V.a, V.b, V.g, V.r}}
  p {["V.rgbaxyzwstpquv"] = V.rgbaxyzwstpquv}
  p "setting green and alpha"
  V.g, V.a = "green", "alpha"
  p {["V"] = V}
  p "setting blue and red"
  V.br = {"blue", "red"}
  p {["V"] = V}
  p {["V.rrrrr"] = V.rrrrr}
  p {["V.g"] = V.g}
  p {["V.zyx"] = V.zyx}
  
  p "setting V.ga to zero"
  V.ga = "zero"
  p {["V"] = V}
    
end

--_M.test()

return  vector

-----
