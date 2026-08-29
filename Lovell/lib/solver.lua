--
--  solution methods
--

local matrix = require "lib.matrix"
  
local T = 'T'   -- transpose operator

getmetatable(matrix {}).__concat = function(self, mat) return self:concath(mat) end -- add missing '..' meta function

    
local _M = {}


-- solve Ax = b
function _M.solve(A, b)
	A = matrix(A)
	b = matrix(b)

  local AT = A ^ T
  local ATA = AT * A
  local ATb = AT * b
  local ATAATb = ATA .. ATb
 
 	ATAATb: dogauss()             -- Gauss-Jordan Method, result is in last column

  local abc = ATAATb ^ T
  return unpack( abc[#abc] )    -- result is in last row

end 


return _M

-----
